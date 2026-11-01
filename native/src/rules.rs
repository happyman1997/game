//! Разбор правил в ядре: условия (триггеры) и значения (формулы) из данных
//! один раз переводятся в дерево и дальше считаются в Rust.
//!
//! Повторяет интерпретатор engine/script/interp.gd: тот же порядок разбора
//! ключей, те же сравнения и операции над числами. Родные проверки
//! (has_trait, is_adult, gold, liege…) читают копию персонажей в ядре
//! (world.rs); всё остальное — встроенные и моддерские проверки, значения,
//! ссылки и списки — вызывается из GDScript по зарегистрированным Callable,
//! а неизвестные ключи целиком отдаются интерпретатору GDScript (он же и
//! сообщит об ошибке). Эффекты остаются в GDScript.
//!
//! Блоки данных узнаются по адресу словаря или массива; разобранный блок
//! держит ссылку на исходный, поэтому адрес не переиспользуется, пока блок в
//! кэше. Замки берутся только на поиск в кэше: вычисление может уйти в
//! GDScript, а оттуда — снова в ядро.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock, RwLock};
use std::time::Instant;

use godot::prelude::*;
use godot::sys::GodotFfi;

use crate::world::{gstr, num, CoreWorld, Data, NO, NO_DATE};

const MAX_DEPTH: u32 = 60;

// ------------------------------------------------------------ дерево

/// Сравнение: число (≥), да/нет, оператор со значением, несколько операторов.
pub(crate) enum Cond {
    Ge(f64),
    Yes(bool),
    Op(Op, Box<V>),
    /// Строка, не похожая на сравнение: actual ≥ значения.
    GeV(Box<V>),
    Many(Vec<(Op, V)>),
    False,
}

#[derive(Clone, Copy)]
pub(crate) enum Op {
    Ge,
    Gt,
    Le,
    Lt,
    Eq,
    Ne,
}

fn cmp_op(op: Op, a: f64, b: f64) -> bool {
    match op {
        Op::Ge => a >= b,
        Op::Gt => a > b,
        Op::Le => a <= b,
        Op::Lt => a < b,
        Op::Eq => (a - b).abs() < 1e-9,
        Op::Ne => (a - b).abs() >= 1e-9,
    }
}

fn op_of(s: &str) -> Option<Op> {
    Some(match s {
        "gte" | ">=" | "min" => Op::Ge,
        "gt" | ">" => Op::Gt,
        "lte" | "<=" | "max" => Op::Le,
        "lt" | "<" => Op::Lt,
        "eq" | "==" | "=" => Op::Eq,
        "ne" | "!=" => Op::Ne,
        _ => return None,
    })
}

/// Шаг пути к скоупу.
pub(crate) enum Step {
    Root,
    This,
    Prev,
    Scope(GString),
    /// character:id, title:id… — если такой объект есть.
    Prefixed(GString, GString),
    Link(u32),
    /// Первый шаг: голый id титула или персонажа.
    Bare(GString),
    Fail,
}

/// Родные проверки персонажа.
#[derive(Clone, Copy)]
pub(crate) enum Nt {
    IsAlive,
    IsFemale,
    IsMale,
    IsAdult,
    IsChild,
    IsRuler,
    IsIndependent,
    IsVassal,
    IsCourtier,
    IsMarried,
    IsLowborn,
    HasAnyClaim,
    IsImprisoned,
    HasTrait,
    HasModifier,
    HasPerk,
    Culture,
    Faith,
    SameCultureAs,
    SameFaithAs,
    IsSpouseOf,
    IsParentOf,
    IsChildOf,
    IsSiblingOf,
    IsVassalOf,
    IsLiegeOf,
    IsCourtierOf,
}

/// Родные значения персонажа.
#[derive(Clone, Copy)]
pub(crate) enum Nv {
    Gold,
    Prestige,
    Piety,
    Stress,
    StressLevel,
    Age,
    NumSpouses,
    NumClaims,
    NumTraits,
    Tier,
}

/// Родные ссылки персонажа.
#[derive(Clone, Copy)]
pub(crate) enum Nl {
    Liege,
    Father,
    Mother,
    Spouse,
    PrimaryTitle,
}

pub(crate) enum T {
    Const(bool),
    All(Vec<T>),
    Any(Vec<T>),
    Not(Box<T>),
    /// Родная проверка: (что, аргумент, номер в реестре, путь-аргумент для отношений).
    Native(Nt, Variant, u32, Option<Vec<Step>>),
    /// Зарегистрированный триггер: номер в реестре и аргумент.
    Call(u32, Variant),
    /// Ключ целиком — интерпретатору GDScript.
    Key(Variant, Variant),
    /// Сменить скоуп по пути и проверить внутри.
    In(Vec<Step>, Box<T>),
    /// scope:x — сохранённое значение (сравнить) или скоуп (проверить внутри).
    ScopeKey(GString, Cond, Box<T>),
    Cmp(V, Cond),
    /// Параметризованное значение: opinion: { target, value }.
    ParamCmp(Option<u32>, Vec<Step>, Cond),
    AnyOf(u32, Box<T>, Count),
    /// Именованный триггер данных (scripted_triggers): (имя, отрицание).
    Scripted(GString, bool, OnceLock<Arc<T>>),
    Exists(Vec<Step>),
    ExistsSelf,
    Is(Vec<Step>),
    /// Блок триггера целиком — GDScript (то, что ядро не разбирает).
    Block(Variant),
}

pub(crate) enum Count {
    Cmp(Cond),
    All,
    Percent(Cond),
}

pub(crate) enum V {
    Num(f64),
    Sum(Vec<V>),
    Ops(Vec<VOp>),
    /// Путь: шаги и последнее имя.
    Path(Vec<Step>, Last),
    Define(Vec<GString>),
    Neg(Box<V>),
    /// Выражение целиком — GDScript.
    Expr(Variant),
}

pub(crate) enum Last {
    /// scope:x — сохранённое значение, иначе как имя.
    ScopeVal(GString, Box<Named>),
    Named(Named),
}

pub(crate) enum Named {
    Native(Nv),
    /// Зарегистрированное значение: номер, аргумент-путь или сырой аргумент.
    Call(u32, NArg),
    Script(GString, OnceLock<Arc<V>>),
    /// Имя целиком — GDScript (var:, global_var:, неизвестное).
    Gd(GString),
}

pub(crate) enum NArg {
    None,
    Raw(GString),
    Path(Vec<Step>),
}

pub(crate) enum VOp {
    Set(V),
    /// (условие, значение, со знаком минус).
    Add(Vec<(Option<T>, V, bool)>),
    Mul(V),
    Div(V),
    Min(V),
    Max(V),
    Round,
    Floor,
    Ceil,
    Abs,
    If(Vec<(T, Vec<VOp>)>),
    /// Неизвестная операция — всё выражение в GDScript.
    Bad,
}

// ------------------------------------------------------------ реестр

pub(crate) struct Reg {
    trig_list: Vec<GString>,
    val_list: Vec<GString>,
    link_list: Vec<GString>,
    list_list: Vec<GString>,
    /// Зарегистрированные триггеры: имя → (eval, разрешённые скоупы).
    trig_names: HashMap<GString, u32>,
    trig_eval: Vec<Callable>,
    trig_scopes: Vec<Option<Vec<GString>>>,
    val_names: HashMap<GString, u32>,
    val_get: Vec<Callable>,
    val_scopes: Vec<Option<Vec<GString>>>,
    val_raw: Vec<bool>,
    link_names: HashMap<GString, u32>,
    link_resolve: Vec<Callable>,
    link_from: Vec<Option<Vec<GString>>>,
    /// Родные ссылки (по номеру ссылки).
    link_native: Vec<Option<Nl>>,
    list_names: HashMap<GString, u32>,
    list_fn: Vec<Callable>,
    list_from: Vec<Option<Vec<GString>>>,
    constants: HashMap<GString, f64>,
    native_t: HashMap<GString, Nt>,
    native_v: HashMap<GString, Nv>,
    scripted_triggers: VarDictionary,
    script_values: VarDictionary,
    defines: VarDictionary,
    /// Интерпретатор GDScript для того, что ядро не разбирает.
    gd_key: Callable,
    gd_value: Callable,
    gd_named: Callable,
    gd_trigger: Callable,
    gd_exists: Callable,
    adult_age: f64,
    title_tiers: HashMap<GString, i64>,
    impure: Vec<GString>,
}

/// Готовые строки.
struct S {
    character: GString,
    type_: Variant,
    id: Variant,
    root: StringName,
    prev: StringName,
    scopes: StringName,
    values: StringName,
}

impl S {
    fn new() -> Self {
        S {
            character: "character".into(),
            type_: "type".to_variant(),
            id: "id".to_variant(),
            root: "root".into(),
            prev: "prev".into(),
            scopes: "scopes".into(),
            values: "values".into(),
        }
    }
}

// ------------------------------------------------------------ строки

fn is_yes(v: &Variant) -> bool {
    match v.get_type() {
        VariantType::BOOL => v.to::<bool>(),
        VariantType::STRING | VariantType::STRING_NAME => {
            let s = gstr(v).unwrap_or_default().to_string();
            s == "yes" || s == "true"
        }
        VariantType::INT => v.to::<i64>() == 1,
        _ => false,
    }
}

/// _yes в builtins: null тоже «да».
fn yes_or_nil(v: &Variant) -> bool {
    v.is_nil() || is_yes(v)
}

/// Разбор пути по точкам вне скобок (Interp.split_path).
fn split_path(path: &str) -> Vec<String> {
    let mut out = Vec::new();
    if !path.contains('(') {
        for s in path.split('.') {
            let t = s.trim();
            if !t.is_empty() {
                out.push(t.to_string());
            }
        }
        return out;
    }
    let mut depth = 0i32;
    let mut cur = String::new();
    for c in path.chars() {
        if c == '(' {
            depth += 1;
        }
        if c == ')' {
            depth -= 1;
        }
        if c == '.' && depth == 0 {
            if !cur.trim().is_empty() {
                out.push(cur.trim().to_string());
            }
            cur.clear();
        } else {
            cur.push(c);
        }
    }
    if !cur.trim().is_empty() {
        out.push(cur.trim().to_string());
    }
    out
}

/// «имя(аргумент)» → (имя, аргумент); None — некорректное имя.
fn parse_name(s: &str) -> Option<(String, String)> {
    let ok = |c: char| c.is_ascii_alphanumeric() || c == '_' || c == ':';
    match s.find('(') {
        None => {
            if !s.is_empty() && s.chars().all(ok) {
                Some((s.to_string(), String::new()))
            } else {
                None
            }
        }
        Some(i) => {
            let name = &s[..i];
            if name.is_empty() || !name.chars().all(ok) || !s.ends_with(')') {
                return None;
            }
            Some((name.to_string(), s[i + 1..s.len() - 1].to_string()))
        }
    }
}

/// Сравнение из строки: (оператор, правая часть).
fn parse_cmp(s: &str) -> Option<(Op, String)> {
    let t = s.trim_start();
    for op in [">=", "<=", "==", "!=", ">", "<", "="] {
        if let Some(rest) = t.strip_prefix(op) {
            let r = rest.trim_start();
            if r.is_empty() {
                return None;
            }
            return Some((op_of(op)?, r.to_string()));
        }
    }
    None
}

fn strip_call(key: &str) -> &str {
    match key.find('(') {
        Some(i) => &key[..i],
        None => key,
    }
}

const PREFIXED: [(&str, &str); 7] = [
    ("character:", "character"),
    ("title:", "title"),
    ("province:", "province"),
    ("dynasty:", "dynasty"),
    ("war:", "war"),
    ("scheme:", "scheme"),
    ("artifact:", "artifact"),
];

fn is_rel(nt: Nt) -> bool {
    matches!(
        nt,
        Nt::SameCultureAs
            | Nt::SameFaithAs
            | Nt::IsSpouseOf
            | Nt::IsParentOf
            | Nt::IsChildOf
            | Nt::IsSiblingOf
            | Nt::IsVassalOf
            | Nt::IsLiegeOf
            | Nt::IsCourtierOf
    )
}

/// Истинность значения, которое вернул GDScript (как bool() в GDScript).
fn vbool(v: &Variant) -> bool {
    match v.get_type() {
        VariantType::NIL => false,
        VariantType::BOOL => v.to::<bool>(),
        VariantType::INT => v.to::<i64>() != 0,
        VariantType::FLOAT => v.to::<f64>() != 0.0,
        _ => v.booleanize(),
    }
}

const SPECIAL: [&str; 19] = [
    "AND", "and", "OR", "or", "NOT", "not", "NAND", "NOR", "nor", "always", "exists", "is", "this", "custom_tooltip",
    "custom_description", "desc", "text", "", "",
];

// ------------------------------------------------------------ разбор

impl Reg {
    fn is_scope_start(&self, seg: &str) -> bool {
        seg == "root"
            || seg == "this"
            || seg == "prev"
            || seg.starts_with("scope:")
            || PREFIXED.iter().any(|(p, _)| seg.starts_with(p))
            || self.link_names.contains_key(&GString::from(seg))
    }

    fn has_named_value(&self, vname: &str) -> bool {
        let g = GString::from(vname);
        self.val_names.contains_key(&g)
            || self.script_values.contains_key(&g.to_variant())
            || vname.starts_with("var:")
            || vname.starts_with("global_var:")
    }

    fn compile_steps(&self, path: &str) -> Vec<Step> {
        let segs = split_path(path);
        segs.iter().enumerate().map(|(i, s)| self.step_of(s, i == 0)).collect()
    }

    fn step_of(&self, seg: &str, first: bool) -> Step {
        match seg {
            "root" => return Step::Root,
            "this" => return Step::This,
            "prev" => return Step::Prev,
            _ => {}
        }
        if let Some(n) = seg.strip_prefix("scope:") {
            return Step::Scope(n.into());
        }
        for (p, ty) in PREFIXED {
            if let Some(id) = seg.strip_prefix(p) {
                return Step::Prefixed((*ty).into(), id.into());
            }
        }
        if let Some(i) = self.link_names.get(&GString::from(seg)) {
            return Step::Link(*i);
        }
        if first {
            return Step::Bare(seg.into());
        }
        Step::Fail
    }

    fn cond(&self, arg: &Variant) -> Cond {
        match arg.get_type() {
            VariantType::INT | VariantType::FLOAT => Cond::Ge(num(arg)),
            VariantType::BOOL => Cond::Yes(arg.to::<bool>()),
            VariantType::STRING | VariantType::STRING_NAME => {
                let s = gstr(arg).unwrap_or_default().to_string();
                if s == "yes" || s == "no" {
                    return Cond::Yes(s == "yes");
                }
                match parse_cmp(&s) {
                    Some((op, rest)) => Cond::Op(op, Box::new(self.value_str(&rest))),
                    None => Cond::GeV(Box::new(self.value(arg))),
                }
            }
            VariantType::DICTIONARY => {
                let d = arg.to::<VarDictionary>();
                let mut out = Vec::new();
                for (k, v) in d.iter_shared() {
                    let ks = gstr(&k).map(|s| s.to_string()).unwrap_or_default();
                    if let Some(op) = op_of(&ks) {
                        out.push((op, self.value(&v)));
                    }
                }
                Cond::Many(out)
            }
            _ => Cond::False,
        }
    }

    // ---------------------------------------------- триггеры

    pub(crate) fn trigger(&self, block: &Variant) -> T {
        match block.get_type() {
            VariantType::NIL => T::Const(true),
            VariantType::BOOL => T::Const(block.to::<bool>()),
            VariantType::STRING | VariantType::STRING_NAME => {
                let s = gstr(block).unwrap_or_default();
                let st = s.to_string();
                if st == "yes" || st == "no" {
                    return T::Const(st == "yes");
                }
                if self.scripted_triggers.contains_key(&s.to_variant()) {
                    return T::Scripted(s, false, OnceLock::new());
                }
                T::Block(block.clone())
            }
            VariantType::ARRAY => T::All(block.to::<VarArray>().iter_shared().map(|b| self.trigger(&b)).collect()),
            VariantType::DICTIONARY => {
                let d = block.to::<VarDictionary>();
                let mut out = Vec::new();
                for (k, v) in d.iter_shared() {
                    match gstr(&k) {
                        Some(ks) => out.push(self.trigger_key(&ks, &v)),
                        None => out.push(T::Block(block.clone())),
                    }
                }
                if out.len() == 1 {
                    out.pop().unwrap()
                } else {
                    T::All(out)
                }
            }
            _ => T::Const(false),
        }
    }

    fn or_block(&self, arg: &Variant) -> T {
        match arg.get_type() {
            VariantType::ARRAY => T::Any(arg.to::<VarArray>().iter_shared().map(|b| self.trigger(&b)).collect()),
            VariantType::DICTIONARY => {
                let d = arg.to::<VarDictionary>();
                T::Any(
                    d.iter_shared()
                        .map(|(k, v)| match gstr(&k) {
                            Some(ks) => self.trigger_key(&ks, &v),
                            None => T::Const(false),
                        })
                        .collect(),
                )
            }
            _ => self.trigger(arg),
        }
    }

    fn trigger_key(&self, key: &GString, arg: &Variant) -> T {
        let k = key.to_string();
        let ks = k.as_str();
        if SPECIAL.contains(&ks) && !ks.is_empty() {
            return match ks {
                "AND" | "and" => self.trigger(arg),
                "OR" | "or" => self.or_block(arg),
                "NOT" | "not" | "NAND" => T::Not(Box::new(self.trigger(arg))),
                "NOR" | "nor" => T::Not(Box::new(self.or_block(arg))),
                "always" => T::Const(is_yes(arg)),
                "exists" => {
                    if (arg.get_type() == VariantType::BOOL && arg.to::<bool>())
                        || gstr(arg).map(|s| s.to_string() == "yes").unwrap_or(false)
                    {
                        T::ExistsSelf
                    } else {
                        match gstr(arg) {
                            Some(p) => T::Exists(self.compile_steps(&p.to_string())),
                            None => T::Key(key.to_variant(), arg.clone()),
                        }
                    }
                }
                "is" | "this" => match gstr(arg) {
                    Some(p) => T::Is(self.compile_steps(&p.to_string())),
                    None => T::Key(key.to_variant(), arg.clone()),
                },
                "custom_tooltip" | "custom_description" => match arg.get_type() {
                    VariantType::ARRAY => T::All(
                        arg.to::<VarArray>()
                            .iter_shared()
                            .map(|x| {
                                if x.get_type() == VariantType::DICTIONARY {
                                    self.trigger(&x.to::<VarDictionary>().get_or_nil("trigger"))
                                } else {
                                    T::Const(true)
                                }
                            })
                            .collect(),
                    ),
                    VariantType::DICTIONARY => self.trigger(&arg.to::<VarDictionary>().get_or_nil("trigger")),
                    _ => T::Const(true),
                },
                _ => T::Const(true),
            };
        }
        // быстрый путь — зарегистрированный триггер
        if !ks.starts_with("any_") {
            if let Some(i) = self.trig_names.get(key) {
                return self.reg_trigger(*i, key, arg);
            }
        }
        // scope:x без точек
        if let Some(name) = ks.strip_prefix("scope:") {
            if !name.contains('.') {
                return T::ScopeKey(name.into(), self.cond(arg), Box::new(self.trigger(arg)));
            }
        }
        if let Some(lname) = ks.strip_prefix("any_") {
            if let Some(li) = self.list_names.get(&GString::from(lname)) {
                return self.any_of(*li, arg);
            }
        }
        if let Some(i) = self.trig_names.get(key) {
            return self.reg_trigger(*i, key, arg);
        }
        if self.scripted_triggers.contains_key(&key.to_variant()) {
            let neg = !(is_yes(arg) || arg.is_nil());
            return T::Scripted(key.clone(), neg, OnceLock::new());
        }
        if let Some(li) = self.link_names.get(key) {
            return T::In(vec![Step::Link(*li)], Box::new(self.trigger(arg)));
        }
        if self.has_named_value(strip_call(ks)) {
            if arg.get_type() == VariantType::DICTIONARY {
                let d = arg.to::<VarDictionary>();
                if d.contains_key(&"target".to_variant()) {
                    let tgt = d.get_or_nil("target");
                    let steps = match gstr(&tgt) {
                        Some(p) => self.compile_steps(&p.to_string()),
                        None => return T::Key(key.to_variant(), arg.clone()),
                    };
                    let vi = self.val_names.get(key).copied();
                    let c = d.get("value").map(|v| self.cond(&v)).unwrap_or_else(|| Cond::Op(Op::Ge, Box::new(V::Num(0.0))));
                    return T::ParamCmp(vi, steps, c);
                }
            }
            return T::Cmp(self.named_path(ks), self.cond(arg));
        }
        if ks.contains('.') || self.is_scope_start(ks) {
            let segs = split_path(ks);
            let last = segs.last().cloned().unwrap_or_default();
            if self.has_named_value(strip_call(&last)) {
                return T::Cmp(self.value_str(ks), self.cond(arg));
            }
            return T::In(self.compile_steps(ks), Box::new(self.trigger(arg)));
        }
        T::Key(key.to_variant(), arg.clone())
    }

    fn reg_trigger(&self, i: u32, key: &GString, arg: &Variant) -> T {
        if let Some(nt) = self.native_t.get(key) {
            let steps = if is_rel(*nt) { gstr(arg).map(|p| self.compile_steps(&p.to_string())) } else { None };
            return T::Native(*nt, arg.clone(), i, steps);
        }
        T::Call(i, arg.clone())
    }

    fn any_of(&self, li: u32, arg: &Variant) -> T {
        let mut cond = self.trigger(arg);
        let mut count = Count::Cmp(Cond::Op(Op::Ge, Box::new(V::Num(1.0))));
        if arg.get_type() == VariantType::DICTIONARY {
            let mut d = arg.to::<VarDictionary>().duplicate_shallow();
            let c = d.get("count");
            let p = d.get("percent");
            d.erase(&"count".to_variant());
            d.erase(&"percent".to_variant());
            cond = self.trigger(&d.to_variant());
            if let Some(c) = c {
                if gstr(&c).map(|s| s.to_string() == "all").unwrap_or(false) {
                    count = Count::All;
                } else {
                    count = Count::Cmp(self.cond(&c));
                }
            }
            if let Some(p) = p {
                if !matches!(count, Count::All) {
                    count = Count::Percent(self.cond(&p));
                }
            }
        } else if is_yes(arg) {
            cond = T::Const(true);
        }
        T::AnyOf(li, Box::new(cond), count)
    }

    // ---------------------------------------------- значения

    pub(crate) fn value(&self, expr: &Variant) -> V {
        match expr.get_type() {
            VariantType::NIL => V::Num(0.0),
            VariantType::INT | VariantType::FLOAT => V::Num(num(expr)),
            VariantType::BOOL => V::Num(if expr.to::<bool>() { 1.0 } else { 0.0 }),
            VariantType::STRING | VariantType::STRING_NAME => self.value_str(&gstr(expr).unwrap_or_default().to_string()),
            VariantType::ARRAY => V::Sum(expr.to::<VarArray>().iter_shared().map(|e| self.value(&e)).collect()),
            VariantType::DICTIONARY => {
                let ops = self.ops(&expr.to::<VarDictionary>());
                if ops.iter().any(|o| matches!(o, VOp::Bad)) {
                    V::Expr(expr.clone())
                } else {
                    V::Ops(ops)
                }
            }
            _ => V::Num(0.0),
        }
    }

    fn ops(&self, d: &VarDictionary) -> Vec<VOp> {
        let mut out = Vec::new();
        for (k, arg) in d.iter_shared() {
            let ks = gstr(&k).map(|s| s.to_string()).unwrap_or_default();
            out.push(match ks.as_str() {
                "value" | "base" => VOp::Set(self.value(&arg)),
                "add" | "subtract" => {
                    let neg = ks == "subtract";
                    let items: Vec<Variant> = if arg.get_type() == VariantType::ARRAY {
                        arg.to::<VarArray>().iter_shared().collect()
                    } else if arg.is_nil() {
                        Vec::new()
                    } else {
                        vec![arg.clone()]
                    };
                    VOp::Add(
                        items
                            .iter()
                            .map(|it| {
                                if it.get_type() == VariantType::DICTIONARY {
                                    let id = it.to::<VarDictionary>();
                                    if id.contains_key(&"limit".to_variant()) || id.contains_key(&"trigger".to_variant()) {
                                        let t = id.get("limit").unwrap_or_else(|| id.get_or_nil("trigger"));
                                        return (Some(self.trigger(&t)), self.value(&id.get("value").unwrap_or(Variant::from(0))), neg);
                                    }
                                    if id.contains_key(&"value".to_variant()) && id.contains_key(&"desc".to_variant()) {
                                        return (None, self.value(&id.get_or_nil("value")), neg);
                                    }
                                }
                                (None, self.value(it), neg)
                            })
                            .collect(),
                    )
                }
                "multiply" => VOp::Mul(self.value(&arg)),
                "divide" => VOp::Div(self.value(&arg)),
                "min" => VOp::Min(self.value(&arg)),
                "max" => VOp::Max(self.value(&arg)),
                "round" | "floor" | "ceil" | "abs" => {
                    if !is_yes(&arg) {
                        continue;
                    }
                    match ks.as_str() {
                        "round" => VOp::Round,
                        "floor" => VOp::Floor,
                        "ceil" => VOp::Ceil,
                        _ => VOp::Abs,
                    }
                }
                "if" => {
                    let items: Vec<Variant> = if arg.get_type() == VariantType::ARRAY {
                        arg.to::<VarArray>().iter_shared().collect()
                    } else if arg.is_nil() {
                        Vec::new()
                    } else {
                        vec![arg.clone()]
                    };
                    let mut branches = Vec::new();
                    for b in items {
                        if b.get_type() != VariantType::DICTIONARY {
                            continue;
                        }
                        let bd = b.to::<VarDictionary>();
                        let mut rest = bd.duplicate_shallow();
                        rest.erase(&"limit".to_variant());
                        rest.erase(&"desc".to_variant());
                        let ops = self.ops(&rest);
                        if ops.iter().any(|o| matches!(o, VOp::Bad)) {
                            return vec![VOp::Bad];
                        }
                        branches.push((self.trigger(&bd.get_or_nil("limit")), ops));
                    }
                    VOp::If(branches)
                }
                "desc" | "base_desc" => continue,
                _ => VOp::Bad,
            });
        }
        out
    }

    /// Строка-значение (Interp._eval_value_path).
    fn value_str(&self, s: &str) -> V {
        let t = s.trim();
        if t.is_empty() {
            return V::Num(0.0);
        }
        if let Some(x) = parse_float(t) {
            return V::Num(x);
        }
        if let Some(c) = self.constants.get(&GString::from(t)) {
            return V::Num(*c);
        }
        if let Some(rest) = t.strip_prefix("defines.") {
            return V::Define(rest.split('.').map(GString::from).collect());
        }
        if let Some(rest) = t.strip_prefix('-') {
            return V::Neg(Box::new(self.value_str(rest)));
        }
        self.named_path(t)
    }

    /// Путь со значением в конце: scope:actor.gold, opinion(scope:x), liege.prestige.
    fn named_path(&self, t: &str) -> V {
        let segs = split_path(t);
        if segs.is_empty() {
            return V::Num(0.0);
        }
        let n = segs.len();
        let steps: Vec<Step> = segs[..n - 1].iter().enumerate().map(|(i, s)| self.step_of(s, i == 0)).collect();
        let last = &segs[n - 1];
        let named = self.named(last);
        let l = match last.strip_prefix("scope:") {
            Some(x) => Last::ScopeVal(x.into(), Box::new(named)),
            None => Last::Named(named),
        };
        V::Path(steps, l)
    }

    fn named(&self, name_with_arg: &str) -> Named {
        let Some((vname, arg)) = parse_name(name_with_arg) else { return Named::Gd(name_with_arg.into()) };
        if vname.starts_with("var:") || vname.starts_with("global_var:") {
            return Named::Gd(name_with_arg.into());
        }
        let g = GString::from(vname.as_str());
        if let Some(i) = self.val_names.get(&g) {
            if arg.is_empty() {
                if let Some(nv) = self.native_v.get(&g) {
                    return Named::Native(*nv);
                }
                return Named::Call(*i, NArg::None);
            }
            if self.val_raw[*i as usize] {
                return Named::Call(*i, NArg::Raw(arg.as_str().into()));
            }
            return Named::Call(*i, NArg::Path(self.compile_steps(&arg)));
        }
        if self.script_values.contains_key(&g.to_variant()) {
            return Named::Script(g, OnceLock::new());
        }
        Named::Gd(name_with_arg.into())
    }
}

/// Число из строки так же, как String.is_valid_float в Godot (без inf/nan).
fn parse_float(s: &str) -> Option<f64> {
    let b = s.as_bytes();
    if b.is_empty() {
        return None;
    }
    let ok = b.iter().all(|c| c.is_ascii_digit() || matches!(c, b'.' | b'-' | b'+' | b'e' | b'E'));
    if !ok || !b.iter().any(|c| c.is_ascii_digit()) {
        return None;
    }
    s.parse::<f64>().ok()
}

// ------------------------------------------------------------ скоуп

#[derive(Clone)]
pub(crate) struct Sc {
    ty: GString,
    id: GString,
    /// Номер персонажа в копии (NO — не персонаж или нет в копии).
    ch: u32,
}

// ------------------------------------------------------------ вычисление

struct Ev<'a> {
    prof: Option<&'a Mutex<HashMap<String, (u64, u64)>>>,
    r: &'a Reg,
    s: &'a S,
    w: &'a CoreWorld,
    ctx: Gd<Object>,
    ctx_v: Variant,
    date: i32,
    scopes: Option<VarDictionary>,
    values: Option<VarDictionary>,
    root: Option<Option<Sc>>,
    /// prev: None — ещё не читали из контекста GDScript.
    prev: Option<Option<Sc>>,
    /// prev в GDScript-контексте изменён ядром — вернуть после вычисления.
    prev_dirty: bool,
    orig_prev: Option<Variant>,
    depth: u32,
}

impl<'a> Ev<'a> {
    fn data(&self) -> std::sync::RwLockReadGuard<'_, Data> {
        self.w.data.read().unwrap()
    }

    fn sc_of(&self, v: &Variant) -> Option<Sc> {
        if v.get_type() != VariantType::DICTIONARY {
            return None;
        }
        let d = v.to::<VarDictionary>();
        let ty = gstr(&d.get_or_nil(&self.s.type_))?;
        let id = gstr(&d.get_or_nil(&self.s.id))?;
        let ch = if ty == self.s.character { self.data().chars.find(&id) } else { NO };
        Some(Sc { ty, id, ch })
    }

    fn to_var(&self, sc: &Option<Sc>) -> Variant {
        match sc {
            None => Variant::nil(),
            Some(s) => {
                let mut d = VarDictionary::new();
                d.set("type", &s.ty);
                d.set("id", &s.id);
                d.to_variant()
            }
        }
    }

    fn scopes(&mut self) -> VarDictionary {
        if self.scopes.is_none() {
            self.scopes = Some(self.ctx.get(&self.s.scopes).try_to::<VarDictionary>().unwrap_or_default());
        }
        self.scopes.clone().unwrap()
    }

    fn values(&mut self) -> VarDictionary {
        if self.values.is_none() {
            self.values = Some(self.ctx.get(&self.s.values).try_to::<VarDictionary>().unwrap_or_default());
        }
        self.values.clone().unwrap()
    }

    /// Перед вызовом GDScript: prev в контексте — как у ядра.
    fn sync_prev(&mut self) {
        if !self.prev_dirty {
            return;
        }
        self.prev_dirty = false;
        match self.prev.clone() {
            // prev ядро не меняло (или уже вернуло): в контексте — исходный
            None => {
                if let Some(p) = self.orig_prev.clone() {
                    self.ctx.set(&self.s.prev, &p);
                }
            }
            Some(v) => {
                if self.orig_prev.is_none() {
                    self.orig_prev = Some(self.ctx.get(&self.s.prev));
                }
                let pv = self.to_var(&v);
                self.ctx.set(&self.s.prev, &pv);
            }
        }
    }

    fn call(&mut self, f: &Callable, args: &[Variant]) -> Variant {
        self.sync_prev();
        let arr: VarArray = args.iter().cloned().collect();
        f.callv(&arr)
    }

    /// Вызов GDScript с замером (если замер включён): what — что зовём.
    fn callp(&mut self, what: &dyn Fn(&Reg) -> String, f: &Callable, args: &[Variant]) -> Variant {
        match self.prof {
            None => self.call(f, args),
            Some(p) => {
                let t = Instant::now();
                let r = self.call(f, args);
                let ns = t.elapsed().as_nanos() as u64;
                let k = what(self.r);
                let mut m = p.lock().unwrap();
                let e = m.entry(k).or_insert((0, 0));
                e.0 += 1;
                e.1 += ns;
                r
            }
        }
    }

    fn scope_ok(&self, allowed: &Option<Vec<GString>>, sc: &Option<Sc>) -> bool {
        match allowed {
            None => true,
            Some(list) => match sc {
                None => false,
                Some(s) => list.contains(&s.ty),
            },
        }
    }

    // ---------------------------------------------- пути

    fn step(&mut self, cur: &Option<Sc>, st: &Step) -> Option<Sc> {
        match st {
            Step::Root => {
                if self.root.is_none() {
                    let r = self.ctx.get(&self.s.root);
                    self.root = Some(self.sc_of(&r));
                }
                self.root.clone().unwrap()
            }
            Step::This => cur.clone(),
            Step::Prev => {
                if self.prev.is_none() {
                    let p = self.ctx.get(&self.s.prev);
                    self.prev = Some(self.sc_of(&p));
                }
                self.prev.clone().unwrap()
            }
            Step::Scope(n) => {
                let v = self.scopes().get_or_nil(n);
                self.sc_of(&v)
            }
            Step::Prefixed(ty, id) => {
                let sc = Sc { ty: ty.clone(), id: id.clone(), ch: NO };
                let mut sc = sc;
                if *ty == self.s.character {
                    sc.ch = self.data().chars.find(id);
                }
                let v = self.to_var(&Some(sc.clone()));
                let ex = self.call(&self.r.gd_exists.clone(), &[self.ctx_v.clone(), v]);
                if vbool(&ex) {
                    Some(sc)
                } else {
                    None
                }
            }
            Step::Link(li) => {
                let cur = cur.as_ref()?;
                let li = *li as usize;
                if !self.scope_ok(&self.r.link_from[li], &Some(cur.clone())) {
                    return None;
                }
                if let Some(nl) = self.r.link_native[li] {
                    return self.native_link(nl, cur);
                }
                let f = self.r.link_resolve[li].clone();
                let cv = self.to_var(&Some(cur.clone()));
                let res = self.callp(&|r: &Reg| format!("link:{}", r.link_list[li]), &f, &[self.ctx_v.clone(), cv]);
                self.sc_of(&res)
            }
            Step::Bare(seg) => {
                // титул или персонаж по голому id (только первый шаг)
                let st = self.call(&self.r.gd_exists.clone(), &[self.ctx_v.clone(), self.bare_ref("title", seg)]);
                if vbool(&st) {
                    return Some(Sc { ty: "title".into(), id: seg.clone(), ch: NO });
                }
                let ch = self.data().chars.find(seg);
                let alive_rec = ch != NO && self.w.fresh(&[ch]).recs.get(ch as usize).map(|r| r.is_some()).unwrap_or(false);
                if alive_rec {
                    return Some(Sc { ty: self.s.character.clone(), id: seg.clone(), ch });
                }
                None
            }
            Step::Fail => None,
        }
    }

    fn bare_ref(&self, ty: &str, id: &GString) -> Variant {
        let mut d = VarDictionary::new();
        d.set("type", ty);
        d.set("id", id);
        d.to_variant()
    }

    fn walk(&mut self, start: &Option<Sc>, steps: &[Step]) -> Option<Sc> {
        let mut cur = start.clone();
        for st in steps {
            cur = self.step(&cur, st);
            cur.as_ref()?;
        }
        cur
    }

    fn native_link(&self, nl: Nl, cur: &Sc) -> Option<Sc> {
        if cur.ch == NO {
            return None;
        }
        let d = self.w.fresh(&[cur.ch]);
        let rec = d.recs.get(cur.ch as usize)?.as_ref()?;
        let target = match nl {
            Nl::Liege => rec.liege,
            Nl::Father => rec.father,
            Nl::Mother => rec.mother,
            Nl::Spouse => rec.spouses.first().copied().unwrap_or(NO),
            Nl::PrimaryTitle => {
                let t = rec.titles.first().copied()?;
                return Some(Sc { ty: "title".into(), id: d.titles.name(t), ch: NO });
            }
        };
        if target == NO {
            return None;
        }
        Some(Sc { ty: self.s.character.clone(), id: d.chars.name(target), ch: target })
    }

    // ---------------------------------------------- триггеры

    fn t(&mut self, n: &T, sc: &Option<Sc>) -> bool {
        match n {
            T::Const(b) => *b,
            T::All(v) => v.iter().all(|x| self.t(x, sc)),
            T::Any(v) => v.iter().any(|x| self.t(x, sc)),
            T::Not(x) => !self.t(x, sc),
            T::Native(nt, arg, i, steps) => {
                let i = *i as usize;
                if !self.scope_ok(&self.r.trig_scopes[i], sc) {
                    return false;
                }
                let is_char = sc.as_ref().map(|s| s.ty == self.s.character).unwrap_or(false);
                if !is_char {
                    // культура и вера провинции — в GDScript
                    return self.call_trigger(i, arg, sc);
                }
                self.native_t(*nt, arg, steps, sc)
            }
            T::Call(i, arg) => {
                let i = *i as usize;
                if !self.scope_ok(&self.r.trig_scopes[i], sc) {
                    return false;
                }
                self.call_trigger(i, arg, sc)
            }
            T::Key(k, arg) => {
                let sv = self.to_var(sc);
                let f = self.r.gd_key.clone();
                let kk = k.stringify().to_string();
                vbool(&self.callp(&move |_r: &Reg| format!("key:{}", kk), &f, &[self.ctx_v.clone(), sv, k.clone(), arg.clone()]))
            }
            T::Block(b) => self.gd_trigger_block(sc, b),
            T::In(steps, inner) => {
                let sub = self.walk(sc, steps);
                if sub.is_none() {
                    return false;
                }
                self.inside(sc, &sub, inner)
            }
            T::ScopeKey(name, cond, inner) => {
                let vals = self.values();
                if let Some(v) = vals.get(name) {
                    let a = num(&v);
                    return self.cond(a, cond, sc);
                }
                let sv = self.scopes().get_or_nil(name);
                let sub = self.sc_of(&sv);
                if sub.is_none() {
                    return false;
                }
                self.inside(sc, &sub, inner)
            }
            T::Cmp(v, cond) => {
                let a = self.v(v, sc);
                self.cond(a, cond, sc)
            }
            T::ParamCmp(vi, steps, cond) => {
                let t = self.walk(sc, steps);
                if t.is_none() {
                    return false;
                }
                let actual = match vi {
                    Some(i) => {
                        let f = self.r.val_get[*i as usize].clone();
                        let sv = self.to_var(sc);
                        let tv = self.to_var(&t);
                        num(&self.call(&f, &[self.ctx_v.clone(), sv, tv]))
                    }
                    None => 0.0,
                };
                self.cond(actual, cond, sc)
            }
            T::AnyOf(li, inner, count) => {
                let li = *li as usize;
                let f = self.r.list_fn[li].clone();
                let sv = self.to_var(sc);
                let items = self.callp(&|r: &Reg| format!("list:{}", r.list_list[li]), &f, &[self.ctx_v.clone(), sv]);
                let arr: VarArray = items.try_to::<VarArray>().unwrap_or_default();
                let total = arr.len();
                let mut n = 0usize;
                for it in arr.iter_shared() {
                    let sub = self.sc_of(&it);
                    if self.inside(sc, &sub, inner) {
                        n += 1;
                    }
                }
                match count {
                    Count::All => n == total,
                    Count::Percent(c) => {
                        let p = if total > 0 { n as f64 / total as f64 } else { 0.0 };
                        self.cond(p, c, sc)
                    }
                    Count::Cmp(c) => self.cond(n as f64, c, sc),
                }
            }
            T::Scripted(name, neg, cell) => {
                let body = cell.get_or_init(|| {
                    let def = self.r.scripted_triggers.get_or_nil(name);
                    Arc::new(self.r.trigger(&body_of(&def, "trigger")))
                });
                if self.depth > MAX_DEPTH {
                    return self.gd_trigger_block(sc, &name.to_variant());
                }
                self.depth += 1;
                let r = self.t(body, sc);
                self.depth -= 1;
                if *neg {
                    !r
                } else {
                    r
                }
            }
            T::ExistsSelf => match sc {
                None => false,
                Some(s) => {
                    if s.ty == self.s.character {
                        s.ch != NO && self.w.fresh(&[s.ch]).recs.get(s.ch as usize).map(|r| r.is_some()).unwrap_or(false)
                    } else {
                        let v = self.to_var(sc);
                        let f = self.r.gd_exists.clone();
                        vbool(&self.call(&f, &[self.ctx_v.clone(), v]))
                    }
                }
            },
            T::Exists(steps) => self.walk(sc, steps).is_some(),
            T::Is(steps) => {
                let o = self.walk(sc, steps);
                match (sc, &o) {
                    (Some(a), Some(b)) => a.ty == b.ty && a.id == b.id,
                    _ => false,
                }
            }
        }
    }

    fn gd_trigger_block(&mut self, sc: &Option<Sc>, b: &Variant) -> bool {
        let sv = self.to_var(sc);
        let f = self.r.gd_trigger.clone();
        vbool(&self.callp(&|_r: &Reg| "block".to_string(), &f, &[self.ctx_v.clone(), sv, b.clone()]))
    }

    fn call_trigger(&mut self, i: usize, arg: &Variant, sc: &Option<Sc>) -> bool {
        let f = self.r.trig_eval[i].clone();
        let sv = self.to_var(sc);
        vbool(&self.callp(&|r: &Reg| format!("tr:{}", r.trig_list[i]), &f, &[self.ctx_v.clone(), sv, arg.clone()]))
    }

    /// Проверка во вложенном скоупе (prev — откуда пришли).
    fn inside(&mut self, from: &Option<Sc>, sub: &Option<Sc>, inner: &T) -> bool {
        if self.depth > MAX_DEPTH {
            return false;
        }
        let old = std::mem::replace(&mut self.prev, Some(from.clone()));
        self.prev_dirty = true;
        self.depth += 1;
        let r = self.t(inner, sub);
        self.depth -= 1;
        self.prev = old;
        self.prev_dirty = true;
        r
    }

    fn cond(&mut self, actual: f64, c: &Cond, sc: &Option<Sc>) -> bool {
        match c {
            Cond::Ge(x) => actual >= *x,
            Cond::Yes(y) => (actual != 0.0) == *y,
            Cond::Op(op, v) => {
                let b = self.v(v, sc);
                cmp_op(*op, actual, b)
            }
            Cond::GeV(v) => actual >= self.v(v, sc),
            Cond::Many(list) => {
                for (op, v) in list {
                    let b = self.v(v, sc);
                    if !cmp_op(*op, actual, b) {
                        return false;
                    }
                }
                true
            }
            Cond::False => false,
        }
    }

    fn rec_ok(&self, sc: &Option<Sc>) -> Option<u32> {
        let s = sc.as_ref()?;
        if s.ty != self.s.character || s.ch == NO {
            return None;
        }
        Some(s.ch)
    }

    /// Аргумент-персонаж (путь к скоупу) для проверок отношения.
    fn arg_char(&mut self, sc: &Option<Sc>, arg: &Variant, steps: &Option<Vec<Step>>) -> Option<u32> {
        if arg.get_type() == VariantType::DICTIONARY {
            let o = self.sc_of(arg)?;
            return if o.ty == self.s.character && o.ch != NO { Some(o.ch) } else { None };
        }
        let steps = steps.as_ref()?;
        let o = self.walk(sc, steps)?;
        if o.ty == self.s.character && o.ch != NO {
            Some(o.ch)
        } else {
            None
        }
    }

    fn native_t(&mut self, nt: Nt, arg: &Variant, steps: &Option<Vec<Step>>, sc: &Option<Sc>) -> bool {
        // все родные — триггеры персонажа (scopes: character)
        let Some(s) = sc.as_ref() else { return false };
        if s.ty != self.s.character {
            return false;
        }
        let ci = s.ch;
        let date = self.date;
        let adult_age = self.r.adult_age;
        // отношения: аргумент — другой персонаж
        let other = if is_rel(nt) { self.arg_char(sc, arg, steps) } else { None };
        let d = match other {
            Some(oi) => self.w.fresh(&[ci, oi]),
            None => self.w.fresh(&[ci]),
        };
        let rec = match d.recs.get(ci as usize).and_then(|r| r.as_ref()) {
            Some(r) => r,
            None => {
                // персонажа нет: ct-триггеры — ложь; is_imprisoned — сравнение с «нет»
                return matches!(nt, Nt::IsImprisoned) && !yes_or_nil(arg);
            }
        };
        let yes = yes_or_nil(arg);
        let age = || -> f64 {
            let end = if rec.death != NO_DATE { rec.death } else { date };
            ((end - rec.birth) as f64 / 365.0).floor()
        };
        let names_in = |t: &crate::world::Names, list: &[u32], a: &Variant| -> bool {
            match a.get_type() {
                VariantType::ARRAY => a.to::<VarArray>().iter_shared().any(|x| match gstr(&x) {
                    Some(s) => {
                        let i = t.find(&s);
                        i != NO && list.contains(&i)
                    }
                    None => false,
                }),
                _ => {
                    let s = gstr(a).unwrap_or_else(|| GString::from(a.stringify()));
                    let i = t.find(&s);
                    i != NO && list.contains(&i)
                }
            }
        };
        match nt {
            Nt::IsAlive => (rec.death == NO_DATE) == yes,
            Nt::IsFemale => rec.female == yes,
            Nt::IsMale => !rec.female == yes,
            Nt::IsAdult => (age() >= adult_age) == yes,
            Nt::IsChild => !(age() >= adult_age) == yes,
            Nt::IsRuler => !rec.titles.is_empty() == yes,
            Nt::IsIndependent => (!rec.titles.is_empty() && rec.liege == NO) == yes,
            Nt::IsVassal => (!rec.titles.is_empty() && rec.liege != NO) == yes,
            Nt::IsCourtier => (rec.titles.is_empty() && rec.liege != NO) == yes,
            Nt::IsMarried => !rec.spouses.is_empty() == yes,
            Nt::IsLowborn => (rec.dynasty == NO) == yes,
            Nt::HasAnyClaim => !rec.claims.is_empty() == yes,
            Nt::IsImprisoned => rec.prison == yes,
            Nt::HasTrait => names_in(&d.traits, &rec.traits, arg),
            Nt::HasPerk => !arg.is_nil() && names_in(&d.perks, &rec.perks, arg),
            Nt::HasModifier => {
                let ids: Vec<u32> = rec.modifiers.iter().map(|m| m.0).collect();
                match arg.get_type() {
                    VariantType::ARRAY => names_in(&d.modifiers, &ids, arg),
                    VariantType::NIL => false,
                    _ => names_in(&d.modifiers, &ids, arg),
                }
            }
            Nt::Culture | Nt::Faith => {
                let (t, v) = if matches!(nt, Nt::Culture) { (&d.cultures, rec.culture) } else { (&d.faiths, rec.faith) };
                let mine = if v == NO { None } else { Some(t.name(v)) };
                match arg.get_type() {
                    VariantType::ARRAY => match &mine {
                        Some(m) => arg.to::<VarArray>().iter_shared().any(|x| gstr(&x).as_ref() == Some(m)),
                        None => arg.to::<VarArray>().iter_shared().any(|x| x.is_nil()),
                    },
                    VariantType::NIL => mine.is_none(),
                    _ => match &mine {
                        Some(m) => gstr(arg).as_ref() == Some(m),
                        None => false,
                    },
                }
            }
            _ => {
                let Some(oi) = other else { return false };
                let Some(o) = d.recs.get(oi as usize).and_then(|r| r.as_ref()) else { return false };
                match nt {
                    Nt::SameCultureAs => o.culture == rec.culture,
                    Nt::SameFaithAs => o.faith == rec.faith,
                    Nt::IsSpouseOf => rec.spouses.contains(&oi),
                    Nt::IsParentOf => o.father == ci || o.mother == ci,
                    Nt::IsChildOf => rec.father == oi || rec.mother == oi,
                    Nt::IsSiblingOf => {
                        ci != oi && ((rec.father != NO && rec.father == o.father) || (rec.mother != NO && rec.mother == o.mother))
                    }
                    Nt::IsVassalOf => !rec.titles.is_empty() && rec.liege == oi,
                    Nt::IsLiegeOf => o.liege == ci && !o.titles.is_empty(),
                    Nt::IsCourtierOf => rec.titles.is_empty() && rec.liege == oi,
                    _ => false,
                }
            }
        }
    }

    // ---------------------------------------------- значения

    fn v(&mut self, n: &V, sc: &Option<Sc>) -> f64 {
        match n {
            V::Num(x) => *x,
            V::Sum(list) => {
                let mut s = 0.0;
                for x in list {
                    s += self.v(x, sc);
                }
                s
            }
            V::Ops(ops) => self.ops(0.0, ops, sc),
            V::Define(path) => {
                let mut cur = self.r.defines.to_variant();
                for p in path {
                    if cur.get_type() != VariantType::DICTIONARY {
                        return 0.0;
                    }
                    cur = cur.to::<VarDictionary>().get_or_nil(p);
                }
                match cur.get_type() {
                    VariantType::INT | VariantType::FLOAT => num(&cur),
                    _ => 0.0,
                }
            }
            V::Neg(x) => -self.v(x, sc),
            V::Expr(e) => {
                let sv = self.to_var(sc);
                let f = self.r.gd_value.clone();
                num(&self.callp(&|_r: &Reg| "expr".to_string(), &f, &[self.ctx_v.clone(), sv, e.clone()]))
            }
            V::Path(steps, last) => {
                // «scope:x» без точек: сохранённое значение
                if steps.is_empty() {
                    if let Last::ScopeVal(name, _) = last {
                        if let Some(v) = self.values().get(name) {
                            return num(&v);
                        }
                    }
                }
                let cur = if steps.is_empty() { sc.clone() } else { self.walk(sc, steps) };
                if !steps.is_empty() && cur.is_none() {
                    return 0.0;
                }
                match last {
                    Last::ScopeVal(name, named) => {
                        if let Some(v) = self.values().get(name) {
                            return num(&v);
                        }
                        self.named(named, &cur)
                    }
                    Last::Named(named) => self.named(named, &cur),
                }
            }
        }
    }

    fn ops(&mut self, start: f64, ops: &[VOp], sc: &Option<Sc>) -> f64 {
        let mut v = start;
        for op in ops {
            match op {
                VOp::Set(x) => v = self.v(x, sc),
                VOp::Add(items) => {
                    for (cond, x, neg) in items {
                        if let Some(c) = cond {
                            if !self.t(c, sc) {
                                continue;
                            }
                        }
                        let a = self.v(x, sc);
                        v += if *neg { -a } else { a };
                    }
                }
                VOp::Mul(x) => v *= self.v(x, sc),
                VOp::Div(x) => {
                    let d = self.v(x, sc);
                    v = if d == 0.0 { 0.0 } else { v / d };
                }
                VOp::Min(x) => v = v.max(self.v(x, sc)),
                VOp::Max(x) => v = v.min(self.v(x, sc)),
                VOp::Round => v = v.round(),
                VOp::Floor => v = v.floor(),
                VOp::Ceil => v = v.ceil(),
                VOp::Abs => v = v.abs(),
                VOp::If(branches) => {
                    for (t, rest) in branches {
                        if !self.t(t, sc) {
                            continue;
                        }
                        v = self.ops(v, rest, sc);
                    }
                }
                VOp::Bad => {}
            }
        }
        v
    }

    fn named(&mut self, n: &Named, sc: &Option<Sc>) -> f64 {
        match n {
            Named::Native(nv) => {
                let Some(ci) = self.rec_ok(sc) else { return 0.0 };
                let date = self.date;
                let d = self.w.fresh(&[ci]);
                let Some(rec) = d.recs.get(ci as usize).and_then(|r| r.as_ref()) else { return 0.0 };
                match nv {
                    Nv::Gold => rec.gold,
                    Nv::Prestige => rec.prestige,
                    Nv::Piety => rec.piety,
                    Nv::Stress => rec.stress,
                    Nv::StressLevel => (rec.stress / 100.0).floor(),
                    Nv::Age => {
                        let end = if rec.death != NO_DATE { rec.death } else { date };
                        ((end - rec.birth) as f64 / 365.0).floor()
                    }
                    Nv::NumSpouses => rec.spouses.len() as f64,
                    Nv::NumClaims => rec.claims.len() as f64,
                    Nv::NumTraits => rec.traits.len() as f64,
                    Nv::Tier => match rec.titles.first() {
                        None => 0.0,
                        Some(t) => self.r.title_tiers.get(&d.titles.name(*t)).copied().unwrap_or(0) as f64,
                    },
                }
            }
            Named::Call(i, a) => {
                if sc.is_none() {
                    return 0.0;
                }
                let i = *i as usize;
                if !self.scope_ok(&self.r.val_scopes[i], sc) {
                    return 0.0;
                }
                let argv = match a {
                    NArg::None => Variant::nil(),
                    NArg::Raw(s) => s.to_variant(),
                    NArg::Path(steps) => {
                        let o = self.walk(sc, steps);
                        self.to_var(&o)
                    }
                };
                let f = self.r.val_get[i].clone();
                let sv = self.to_var(sc);
                num(&self.callp(&|r: &Reg| format!("val:{}", r.val_list[i]), &f, &[self.ctx_v.clone(), sv, argv]))
            }
            Named::Script(name, cell) => {
                if sc.is_none() {
                    return 0.0;
                }
                let body = cell.get_or_init(|| {
                    let def = self.r.script_values.get_or_nil(name);
                    if def.get_type() == VariantType::DICTIONARY {
                        let mut dd = def.to::<VarDictionary>().duplicate_shallow();
                        dd.erase(&"id".to_variant());
                        Arc::new(self.r.value(&dd.to_variant()))
                    } else {
                        Arc::new(self.r.value(&def))
                    }
                });
                if self.depth > MAX_DEPTH {
                    return 0.0;
                }
                self.depth += 1;
                let r = self.v(body, sc);
                self.depth -= 1;
                r
            }
            Named::Gd(name) => {
                let sv = self.to_var(sc);
                let f = self.r.gd_named.clone();
                let nn = name.to_string();
                num(&self.callp(&move |_r: &Reg| format!("named:{}", nn), &f, &[self.ctx_v.clone(), sv, name.to_variant()]))
            }
        }
    }
}

/// Тело именованного блока: поле field или вся запись без id/desc (Interp.body_of).
fn body_of(def: &Variant, field: &str) -> Variant {
    if def.get_type() != VariantType::DICTIONARY {
        return def.clone();
    }
    let d = def.to::<VarDictionary>();
    if let Some(v) = d.get(field) {
        return v;
    }
    let mut rest = d.duplicate_shallow();
    rest.erase(&"id".to_variant());
    rest.erase(&"desc".to_variant());
    rest.to_variant()
}

// ------------------------------------------------------------ класс

/// Адрес словаря или массива (их Godot-объекта) — ключ кэша.
fn addr(v: &Variant) -> Option<usize> {
    match v.get_type() {
        VariantType::DICTIONARY => {
            let d = v.to::<VarDictionary>();
            // SAFETY: Dictionary в Godot — один указатель на внутренние данные.
            Some(unsafe { *(d.sys() as *const usize) })
        }
        VariantType::ARRAY => {
            let a = v.to::<VarArray>();
            // SAFETY: Array в Godot — один указатель на внутренние данные.
            Some(unsafe { *(a.sys() as *const usize) })
        }
        _ => None,
    }
}

struct Cache {
    trig: HashMap<usize, (Arc<T>, Variant)>,
    val: HashMap<usize, (Arc<V>, Variant)>,
}

const CACHE_MAX: usize = 50_000;

#[derive(GodotClass)]
#[class(base = RefCounted)]
pub struct CoreRules {
    prof_on: AtomicBool,
    prof: Mutex<HashMap<String, (u64, u64)>>,
    reg: RwLock<Option<Arc<Reg>>>,
    cache: Mutex<Cache>,
    s: S,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for CoreRules {
    fn init(base: Base<RefCounted>) -> Self {
        CoreRules { prof_on: AtomicBool::new(false), prof: Mutex::new(HashMap::new()), reg: RwLock::new(None), cache: Mutex::new(Cache { trig: HashMap::new(), val: HashMap::new() }), s: S::new(), base }
    }
}

fn scopes_of(d: &VarDictionary, key: &str) -> Option<Vec<GString>> {
    let v = d.get(key)?;
    if v.get_type() != VariantType::ARRAY {
        return None;
    }
    Some(v.to::<VarArray>().iter_shared().filter_map(|x| gstr(&x)).collect())
}

#[godot_api]
impl CoreRules {
    /// Реестры скриптового языка и всё, что нужно для разбора (engine.rules()).
    #[func]
    fn setup(&self, cfg: VarDictionary) {
        let dict = |k: &str| cfg.get(k).and_then(|v| v.try_to::<VarDictionary>().ok()).unwrap_or_default();
        let call = |k: &str| cfg.get(k).and_then(|v| v.try_to::<Callable>().ok()).unwrap_or_else(Callable::invalid);
        let mut r = Reg {
            trig_list: Vec::new(),
            val_list: Vec::new(),
            link_list: Vec::new(),
            list_list: Vec::new(),
            trig_names: HashMap::new(),
            trig_eval: Vec::new(),
            trig_scopes: Vec::new(),
            val_names: HashMap::new(),
            val_get: Vec::new(),
            val_scopes: Vec::new(),
            val_raw: Vec::new(),
            link_names: HashMap::new(),
            link_resolve: Vec::new(),
            link_from: Vec::new(),
            link_native: Vec::new(),
            list_names: HashMap::new(),
            list_fn: Vec::new(),
            list_from: Vec::new(),
            constants: HashMap::new(),
            native_t: HashMap::new(),
            native_v: HashMap::new(),
            scripted_triggers: dict("scripted_triggers"),
            script_values: dict("script_values"),
            defines: dict("defines"),
            gd_key: call("gd_key"),
            gd_value: call("gd_value"),
            gd_named: call("gd_named"),
            gd_trigger: call("gd_trigger"),
            gd_exists: call("gd_exists"),
            adult_age: cfg.get("adult_age").map(|v| num(&v)).unwrap_or(16.0),
            title_tiers: HashMap::new(),
            impure: Vec::new(),
        };
        for (k, v) in dict("triggers").iter_shared() {
            let (Some(name), Ok(d)) = (gstr(&k), v.try_to::<VarDictionary>()) else { continue };
            let i = r.trig_eval.len() as u32;
            r.trig_eval.push(d.get("eval").and_then(|c| c.try_to::<Callable>().ok()).unwrap_or_else(Callable::invalid));
            r.trig_scopes.push(scopes_of(&d, "scopes"));
            r.trig_list.push(name.clone());
            r.trig_names.insert(name, i);
        }
        for (k, v) in dict("values").iter_shared() {
            let (Some(name), Ok(d)) = (gstr(&k), v.try_to::<VarDictionary>()) else { continue };
            let i = r.val_get.len() as u32;
            r.val_get.push(d.get("get").and_then(|c| c.try_to::<Callable>().ok()).unwrap_or_else(Callable::invalid));
            r.val_scopes.push(scopes_of(&d, "scopes"));
            r.val_raw.push(d.get("raw_arg").map(|x| x.try_to::<bool>().unwrap_or(false)).unwrap_or(false));
            r.val_list.push(name.clone());
            r.val_names.insert(name, i);
        }
        let natives = dict("natives");
        let has_native = |kind: &str, name: &GString| -> bool {
            natives.get(kind).and_then(|v| v.try_to::<VarDictionary>().ok()).map(|d| d.contains_key(&name.to_variant())).unwrap_or(false)
        };
        for (k, v) in dict("links").iter_shared() {
            let (Some(name), Ok(d)) = (gstr(&k), v.try_to::<VarDictionary>()) else { continue };
            let i = r.link_resolve.len() as u32;
            r.link_resolve.push(d.get("resolve").and_then(|c| c.try_to::<Callable>().ok()).unwrap_or_else(Callable::invalid));
            r.link_from.push(scopes_of(&d, "from"));
            let nl = if has_native("links", &name) {
                match name.to_string().as_str() {
                    "liege" | "employer" => Some(Nl::Liege),
                    "father" => Some(Nl::Father),
                    "mother" => Some(Nl::Mother),
                    "spouse" => Some(Nl::Spouse),
                    "primary_title" => Some(Nl::PrimaryTitle),
                    _ => None,
                }
            } else {
                None
            };
            r.link_native.push(nl);
            r.link_list.push(name.clone());
            r.link_names.insert(name, i);
        }
        for (k, v) in dict("lists").iter_shared() {
            let (Some(name), Ok(d)) = (gstr(&k), v.try_to::<VarDictionary>()) else { continue };
            let i = r.list_fn.len() as u32;
            r.list_fn.push(d.get("list").and_then(|c| c.try_to::<Callable>().ok()).unwrap_or_else(Callable::invalid));
            r.list_from.push(scopes_of(&d, "from"));
            r.list_list.push(name.clone());
            r.list_names.insert(name, i);
        }
        for (k, v) in dict("constants").iter_shared() {
            if let Some(name) = gstr(&k) {
                r.constants.insert(name, num(&v));
            }
        }
        for (k, v) in dict("title_tiers").iter_shared() {
            if let Some(name) = gstr(&k) {
                r.title_tiers.insert(name, num(&v) as i64);
            }
        }
        let tmap: [(&str, Nt); 28] = [
            ("is_alive", Nt::IsAlive),
            ("is_female", Nt::IsFemale),
            ("is_male", Nt::IsMale),
            ("is_adult", Nt::IsAdult),
            ("is_child", Nt::IsChild),
            ("is_ruler", Nt::IsRuler),
            ("is_landed", Nt::IsRuler),
            ("is_independent", Nt::IsIndependent),
            ("is_vassal", Nt::IsVassal),
            ("is_courtier", Nt::IsCourtier),
            ("is_married", Nt::IsMarried),
            ("is_lowborn", Nt::IsLowborn),
            ("has_any_claim", Nt::HasAnyClaim),
            ("is_imprisoned", Nt::IsImprisoned),
            ("has_trait", Nt::HasTrait),
            ("has_modifier", Nt::HasModifier),
            ("has_perk", Nt::HasPerk),
            ("culture", Nt::Culture),
            ("faith", Nt::Faith),
            ("same_culture_as", Nt::SameCultureAs),
            ("same_faith_as", Nt::SameFaithAs),
            ("is_spouse_of", Nt::IsSpouseOf),
            ("is_parent_of", Nt::IsParentOf),
            ("is_child_of", Nt::IsChildOf),
            ("is_sibling_of", Nt::IsSiblingOf),
            ("is_vassal_of", Nt::IsVassalOf),
            ("is_liege_of", Nt::IsLiegeOf),
            ("is_courtier_of", Nt::IsCourtierOf),
        ];
        for (n, nt) in tmap {
            let g = GString::from(n);
            if has_native("triggers", &g) {
                r.native_t.insert(g, nt);
            }
        }
        let vmap: [(&str, Nv); 10] = [
            ("gold", Nv::Gold),
            ("prestige", Nv::Prestige),
            ("piety", Nv::Piety),
            ("stress", Nv::Stress),
            ("stress_level", Nv::StressLevel),
            ("age", Nv::Age),
            ("num_spouses", Nv::NumSpouses),
            ("num_claims", Nv::NumClaims),
            ("num_traits", Nv::NumTraits),
            ("tier", Nv::Tier),
        ];
        for (n, nv) in vmap {
            let g = GString::from(n);
            if has_native("values", &g) {
                r.native_v.insert(g, nv);
            }
        }
        if let Some(v) = cfg.get("impure") {
            if let Ok(a) = v.try_to::<VarArray>() {
                r.impure = a.iter_shared().filter_map(|x| gstr(&x)).collect();
            }
        }
        *self.reg.write().unwrap() = Some(Arc::new(r));
        let mut c = self.cache.lock().unwrap();
        c.trig.clear();
        c.val.clear();
    }

    /// Разобранный блок триггера (из кэша по адресу или новый).
    fn trig_of(&self, reg: &Reg, block: &Variant) -> Arc<T> {
        let Some(a) = addr(block) else { return Arc::new(reg.trigger(block)) };
        {
            let c = self.cache.lock().unwrap();
            if let Some((t, _)) = c.trig.get(&a) {
                return t.clone();
            }
        }
        let t = Arc::new(reg.trigger(block));
        let mut c = self.cache.lock().unwrap();
        if c.trig.len() > CACHE_MAX {
            c.trig.clear();
        }
        c.trig.insert(a, (t.clone(), block.clone()));
        t
    }

    fn val_of(&self, reg: &Reg, expr: &Variant) -> Arc<V> {
        let Some(a) = addr(expr) else { return Arc::new(reg.value(expr)) };
        {
            let c = self.cache.lock().unwrap();
            if let Some((v, _)) = c.val.get(&a) {
                return v.clone();
            }
        }
        let v = Arc::new(reg.value(expr));
        let mut c = self.cache.lock().unwrap();
        if c.val.len() > CACHE_MAX {
            c.val.clear();
        }
        c.val.insert(a, (v.clone(), expr.clone()));
        v
    }

    fn ev<'a>(&'a self, reg: &'a Reg, world: &'a CoreWorld, ctx: Gd<Object>, date: i64) -> Ev<'a> {
        let ctx_v = ctx.to_variant();
        Ev {
            prof: if self.prof_on.load(Ordering::Relaxed) { Some(&self.prof) } else { None },
            r: reg,
            s: &self.s,
            w: world,
            ctx,
            ctx_v,
            date: date as i32,
            scopes: None,
            values: None,
            root: None,
            prev: None,
            prev_dirty: false,
            orig_prev: None,
            depth: 0,
        }
    }

    fn finish(ev: &mut Ev) {
        if let Some(p) = ev.orig_prev.take() {
            ev.ctx.set(&ev.s.prev, &p);
        }
    }

    /// Условие: 1 — верно, 0 — нет, −1 — ядро не готово (считает GDScript).
    #[func]
    fn trigger(&self, block: Variant, ctx: Gd<Object>, scope: Variant, world: Gd<CoreWorld>, date: i64) -> i64 {
        let Some(reg) = self.reg.read().unwrap().clone() else { return -1 };
        let t = self.trig_of(&reg, &block);
        let w = world.bind();
        let mut ev = self.ev(&reg, &w, ctx, date);
        let sc = ev.sc_of(&scope);
        let r = ev.t(&t, &sc);
        Self::finish(&mut ev);
        r as i64
    }

    /// Значение; NaN — ядро не готово (считает GDScript).
    #[func]
    fn value(&self, expr: Variant, ctx: Gd<Object>, scope: Variant, world: Gd<CoreWorld>, date: i64) -> f64 {
        let Some(reg) = self.reg.read().unwrap().clone() else { return f64::NAN };
        let v = self.val_of(&reg, &expr);
        let w = world.bind();
        let mut ev = self.ev(&reg, &w, ctx, date);
        let sc = ev.sc_of(&scope);
        let r = ev.v(&v, &sc);
        Self::finish(&mut ev);
        r
    }

    /// Нечистый ли блок (в нём есть случайность) — для двойной проверки.
    #[func]
    fn is_impure(&self, block: Variant) -> bool {
        let Some(reg) = self.reg.read().unwrap().clone() else { return true };
        if reg.impure.is_empty() {
            return false;
        }
        let s = block.stringify().to_string();
        reg.impure.iter().any(|n| s.contains(&n.to_string()))
    }

    /// Сколько блоков разобрано (для замеров).
    #[func]
    fn cached(&self) -> i64 {
        let c = self.cache.lock().unwrap();
        (c.trig.len() + c.val.len()) as i64
    }

    /// Замер вызовов GDScript из ядра: включить/выключить (сбрасывает счётчики).
    #[func]
    fn set_profile(&self, on: bool) {
        self.prof_on.store(on, Ordering::Relaxed);
        self.prof.lock().unwrap().clear();
    }

    /// Счётчики замера: {что: [вызовов, мкс]}.
    #[func]
    fn profile(&self) -> VarDictionary {
        let mut out = VarDictionary::new();
        for (k, (n, ns)) in self.prof.lock().unwrap().iter() {
            let arr: VarArray = [Variant::from(*n as i64), Variant::from(*ns as f64 / 1000.0)].into_iter().collect();
            out.set(k.as_str(), &arr);
        }
        out
    }

    /// Сбросить кэш разобранных блоков.
    #[func]
    fn clear(&self) {
        let mut c = self.cache.lock().unwrap();
        c.trig.clear();
        c.val.clear();
    }
}
