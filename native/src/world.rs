//! Мир в ядре: плотная копия персонажей (шаг 1 переезда симуляции в Rust).
//!
//! Главные данные пока — словари GDScript (state.characters). Ядро держит их
//! копию в плотных записях с числовыми номерами: строки (персонажи, культуры,
//! веры, роды, черты, титулы, модификаторы, перки) заменены номерами из
//! таблиц. Каждое изменение персонажа в GDScript сообщается ядру (sync), а
//! режим сверки (diff, verify) сравнивает копию со словарями и называет
//! расходящиеся поля — так ловятся места, которые забыли сообщить.
//!
//! Все методы берут &self: данные под RwLock, ядро можно звать и из потока
//! симуляции, и из интерфейса.

use std::collections::HashMap;
use std::sync::RwLock;

use godot::prelude::*;

/// «Нет» для номеров (персонаж, род, культура…).
pub(crate) const NO: u32 = u32::MAX;
/// «Нет» для дат (жив, без срока).
pub(crate) const NO_DATE: i32 = i32::MIN;

/// Таблица строк ↔ номеров.
#[derive(Default)]
pub(crate) struct Names {
    pub(crate) list: Vec<GString>,
    pub(crate) map: HashMap<GString, u32>,
}

impl Names {
    pub(crate) fn intern(&mut self, s: GString) -> u32 {
        if let Some(i) = self.map.get(&s) {
            return *i;
        }
        let i = self.list.len() as u32;
        self.list.push(s.clone());
        self.map.insert(s, i);
        i
    }

    pub(crate) fn find(&self, s: &GString) -> u32 {
        self.map.get(s).copied().unwrap_or(NO)
    }

    pub(crate) fn name(&self, i: u32) -> GString {
        self.list.get(i as usize).cloned().unwrap_or_default()
    }
}

/// Запись персонажа в ядре.
#[derive(Clone, Default, PartialEq, Debug)]
pub(crate) struct Rec {
    pub(crate) birth: i32,
    pub(crate) death: i32,
    pub(crate) female: bool,
    pub(crate) gold: f64,
    pub(crate) prestige: f64,
    pub(crate) piety: f64,
    pub(crate) stress: f64,
    pub(crate) health: f64,
    /// Навыки в порядке Data.skills.
    pub(crate) skills: Vec<f64>,
    pub(crate) culture: u32,
    pub(crate) faith: u32,
    pub(crate) dynasty: u32,
    pub(crate) liege: u32,
    pub(crate) father: u32,
    pub(crate) mother: u32,
    pub(crate) spouses: Vec<u32>,
    pub(crate) children: Vec<u32>,
    pub(crate) traits: Vec<u32>,
    pub(crate) titles: Vec<u32>,
    pub(crate) claims: Vec<u32>,
    pub(crate) prison: bool,
    /// (модификатор, срок или NO_DATE).
    pub(crate) modifiers: Vec<(u32, i32)>,
    pub(crate) perks: Vec<u32>,
    /// (о ком, модификатор мнения, величина, срок или NO_DATE) — в порядке словаря.
    pub(crate) opinions: Vec<(u32, u32, f64, i32)>,
}

/// Все таблицы и записи.
#[derive(Default)]
pub(crate) struct Data {
    pub(crate) skills: Vec<GString>,
    pub(crate) chars: Names,
    pub(crate) cultures: Names,
    pub(crate) faiths: Names,
    pub(crate) dynasties: Names,
    pub(crate) traits: Names,
    pub(crate) titles: Names,
    pub(crate) modifiers: Names,
    pub(crate) perks: Names,
    pub(crate) opinion_mods: Names,
    /// Записи по номеру персонажа (None — ещё не сообщён или удалён).
    pub(crate) recs: Vec<Option<Rec>>,
}

// ------------------------------------------------------------ чтение значений

pub(crate) fn num(v: &Variant) -> f64 {
    match v.get_type() {
        VariantType::FLOAT => v.to::<f64>(),
        VariantType::INT => v.to::<i64>() as f64,
        VariantType::BOOL => {
            if v.to::<bool>() {
                1.0
            } else {
                0.0
            }
        }
        _ => 0.0,
    }
}

pub(crate) fn date(v: &Variant) -> i32 {
    match v.get_type() {
        VariantType::INT => v.to::<i64>() as i32,
        VariantType::FLOAT => v.to::<f64>().round() as i32,
        _ => NO_DATE,
    }
}

pub(crate) fn gstr(v: &Variant) -> Option<GString> {
    match v.get_type() {
        VariantType::STRING => Some(v.to::<GString>()),
        VariantType::STRING_NAME => Some(GString::from(&v.to::<StringName>())),
        _ => None,
    }
}

fn truthy(v: &Variant) -> bool {
    match v.get_type() {
        VariantType::NIL => false,
        VariantType::BOOL => v.to::<bool>(),
        VariantType::INT => v.to::<i64>() != 0,
        _ => true,
    }
}

/// Ключи словаря персонажа (один раз).
pub(crate) struct Keys {
    pub(crate) id: Variant,
    birth: Variant,
    death: Variant,
    female: Variant,
    gold: Variant,
    prestige: Variant,
    piety: Variant,
    stress: Variant,
    health: Variant,
    skills: Variant,
    culture: Variant,
    faith: Variant,
    dynasty: Variant,
    liege: Variant,
    father: Variant,
    mother: Variant,
    spouses: Variant,
    children: Variant,
    traits: Variant,
    titles: Variant,
    claims: Variant,
    prison: Variant,
    modifiers: Variant,
    lifestyle: Variant,
    perks: Variant,
    opinions: Variant,
    expires: Variant,
    mod_: Variant,
    value: Variant,
}

impl Keys {
    pub(crate) fn new() -> Self {
        let k = |s: &str| StringName::from(s).to_variant();
        Keys {
            id: k("id"),
            birth: k("birth"),
            death: k("death"),
            female: k("female"),
            gold: k("gold"),
            prestige: k("prestige"),
            piety: k("piety"),
            stress: k("stress"),
            health: k("health"),
            skills: k("skills"),
            culture: k("culture"),
            faith: k("faith"),
            dynasty: k("dynasty"),
            liege: k("liege"),
            father: k("father"),
            mother: k("mother"),
            spouses: k("spouses"),
            children: k("children"),
            traits: k("traits"),
            titles: k("titles"),
            claims: k("claims"),
            prison: k("prison"),
            modifiers: k("modifiers"),
            lifestyle: k("lifestyle"),
            perks: k("perks"),
            opinions: k("opinions"),
            expires: k("expires"),
            mod_: k("mod"),
            value: k("value"),
        }
    }
}

fn opt_name(t: &mut Names, v: &Variant) -> u32 {
    gstr(v).map(|s| t.intern(s)).unwrap_or(NO)
}

fn name_list(t: &mut Names, v: &Variant) -> Vec<u32> {
    let mut out = Vec::new();
    if v.get_type() == VariantType::ARRAY {
        for x in v.to::<VarArray>().iter_shared() {
            if let Some(s) = gstr(&x) {
                out.push(t.intern(s));
            }
        }
    }
    out
}

impl Data {
    /// Разбирает словарь персонажа в запись (новые строки попадают в таблицы).
    pub(crate) fn read(&mut self, k: &Keys, c: &VarDictionary) -> Rec {
        let g = |key: &Variant| c.get_or_nil(key);
        let mut r = Rec {
            birth: date(&g(&k.birth)),
            death: date(&g(&k.death)),
            female: truthy(&g(&k.female)),
            gold: num(&g(&k.gold)),
            prestige: num(&g(&k.prestige)),
            piety: num(&g(&k.piety)),
            stress: num(&g(&k.stress)),
            health: num(&g(&k.health)),
            culture: opt_name(&mut self.cultures, &g(&k.culture)),
            faith: opt_name(&mut self.faiths, &g(&k.faith)),
            dynasty: opt_name(&mut self.dynasties, &g(&k.dynasty)),
            liege: opt_name(&mut self.chars, &g(&k.liege)),
            father: opt_name(&mut self.chars, &g(&k.father)),
            mother: opt_name(&mut self.chars, &g(&k.mother)),
            spouses: name_list(&mut self.chars, &g(&k.spouses)),
            children: name_list(&mut self.chars, &g(&k.children)),
            traits: name_list(&mut self.traits, &g(&k.traits)),
            titles: name_list(&mut self.titles, &g(&k.titles)),
            claims: name_list(&mut self.titles, &g(&k.claims)),
            prison: !g(&k.prison).is_nil(),
            ..Default::default()
        };
        let sk = g(&k.skills);
        if sk.get_type() == VariantType::DICTIONARY {
            let sd = sk.to::<VarDictionary>();
            r.skills = self.skills.iter().map(|s| num(&sd.get_or_nil(s))).collect();
        } else {
            r.skills = vec![0.0; self.skills.len()];
        }
        let mods = g(&k.modifiers);
        if mods.get_type() == VariantType::ARRAY {
            for m in mods.to::<VarArray>().iter_shared() {
                if m.get_type() != VariantType::DICTIONARY {
                    continue;
                }
                let md = m.to::<VarDictionary>();
                if let Some(s) = gstr(&md.get_or_nil(&k.id)) {
                    r.modifiers.push((self.modifiers.intern(s), date(&md.get_or_nil(&k.expires))));
                }
            }
        }
        let ls = g(&k.lifestyle);
        if ls.get_type() == VariantType::DICTIONARY {
            r.perks = name_list(&mut self.perks, &ls.to::<VarDictionary>().get_or_nil(&k.perks));
        }
        let ops = g(&k.opinions);
        if ops.get_type() == VariantType::DICTIONARY {
            for (target, list) in ops.to::<VarDictionary>().iter_shared() {
                let Some(ts) = gstr(&target) else { continue };
                let t = self.chars.intern(ts);
                if list.get_type() != VariantType::ARRAY {
                    continue;
                }
                for e in list.to::<VarArray>().iter_shared() {
                    if e.get_type() != VariantType::DICTIONARY {
                        continue;
                    }
                    let ed = e.to::<VarDictionary>();
                    let m = opt_name(&mut self.opinion_mods, &ed.get_or_nil(&k.mod_));
                    r.opinions.push((t, m, num(&ed.get_or_nil(&k.value)), date(&ed.get_or_nil(&k.expires))));
                }
            }
        }
        r
    }

    /// Номер персонажа по словарю (заводит, если новый).
    pub(crate) fn slot(&mut self, k: &Keys, c: &VarDictionary) -> Option<usize> {
        let id = gstr(&c.get_or_nil(&k.id))?;
        let i = self.chars.intern(id) as usize;
        if self.recs.len() <= i {
            self.recs.resize(i + 1, None);
        }
        Some(i)
    }

    pub(crate) fn sync(&mut self, k: &Keys, c: &VarDictionary) {
        let rec = self.read(k, c);
        if let Some(i) = self.slot(k, c) {
            self.recs[i] = Some(rec);
        }
    }

    /// Поля, в которых копия расходится со словарём.
    pub(crate) fn diff(&mut self, k: &Keys, c: &VarDictionary) -> Vec<&'static str> {
        let fresh = self.read(k, c);
        let Some(i) = self.slot(k, c) else { return vec!["id"] };
        let Some(old) = self.recs[i].as_ref() else { return vec!["нет в ядре"] };
        let mut out = Vec::new();
        macro_rules! cmp {
            ($($f:ident),*) => { $( if old.$f != fresh.$f { out.push(stringify!($f)); } )* };
        }
        cmp!(birth, death, female, gold, prestige, piety, stress, health, skills, culture, faith, dynasty, liege, father, mother,
            spouses, children, traits, titles, claims, prison, modifiers, perks, opinions);
        out
    }
}

#[derive(GodotClass)]
#[class(base = RefCounted)]
pub struct CoreWorld {
    pub(crate) data: RwLock<Data>,
    pub(crate) keys: Keys,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for CoreWorld {
    fn init(base: Base<RefCounted>) -> Self {
        CoreWorld { data: RwLock::new(Data::default()), keys: Keys::new(), base }
    }
}

#[godot_api]
impl CoreWorld {
    /// Навыки (порядок их хранения в записи) — до первого sync.
    #[func]
    fn setup(&self, skills: PackedStringArray) {
        let mut d = self.data.write().unwrap();
        d.skills = skills.as_slice().to_vec();
    }

    /// Сообщить ядру о персонаже (после любого изменения его словаря).
    #[func]
    fn sync(&self, c: VarDictionary) {
        self.data.write().unwrap().sync(&self.keys, &c);
    }

    /// Все персонажи разом (state.characters) — при создании и загрузке.
    #[func]
    fn sync_all(&self, chars: VarDictionary) {
        let mut d = self.data.write().unwrap();
        for (_, c) in chars.iter_shared() {
            if c.get_type() == VariantType::DICTIONARY {
                d.sync(&self.keys, &c.to::<VarDictionary>());
            }
        }
    }

    /// Персонаж удалён из state.characters.
    #[func]
    fn forget(&self, id: GString) {
        let mut d = self.data.write().unwrap();
        let i = d.chars.find(&id);
        if i != NO && (i as usize) < d.recs.len() {
            d.recs[i as usize] = None;
        }
    }

    /// Расходящиеся поля одного персонажа.
    #[func]
    fn diff(&self, c: VarDictionary) -> PackedStringArray {
        let out = self.data.write().unwrap().diff(&self.keys, &c);
        out.iter().map(|s| GString::from(*s)).collect()
    }

    /// Сверка со всеми персонажами: {id: [поля]} — только расхождения.
    /// Персонаж есть в ядре, но нет в словаре, — поле «удалён».
    #[func]
    fn verify(&self, chars: VarDictionary) -> VarDictionary {
        let mut d = self.data.write().unwrap();
        let mut out = VarDictionary::new();
        let mut seen = vec![false; d.recs.len()];
        for (id, c) in chars.iter_shared() {
            if c.get_type() != VariantType::DICTIONARY {
                continue;
            }
            let cd = c.to::<VarDictionary>();
            if let Some(s) = gstr(&id) {
                let i = d.chars.find(&s);
                if i != NO && (i as usize) < seen.len() {
                    seen[i as usize] = true;
                }
            }
            let bad = d.diff(&self.keys, &cd);
            if !bad.is_empty() {
                let arr: PackedStringArray = bad.iter().map(|s| GString::from(*s)).collect();
                out.set(&id, &arr);
            }
        }
        for (i, s) in seen.iter().enumerate() {
            if !*s && d.recs[i].is_some() {
                let arr: PackedStringArray = [GString::from("удалён")].into_iter().collect();
                out.set(&d.chars.name(i as u32), &arr);
            }
        }
        out
    }

    /// Сколько персонажей в ядре.
    #[func]
    fn count(&self) -> i32 {
        self.data.read().unwrap().recs.iter().filter(|r| r.is_some()).count() as i32
    }

    /// Запись персонажа словарём (для отладки и тестов).
    #[func]
    fn record(&self, id: GString) -> VarDictionary {
        let d = self.data.read().unwrap();
        let mut out = VarDictionary::new();
        let i = d.chars.find(&id);
        let Some(Some(r)) = d.recs.get(i as usize) else { return out };
        let ids = |t: &Names, v: &[u32]| -> PackedStringArray { v.iter().map(|x| t.name(*x)).collect() };
        out.set("gold", r.gold);
        out.set("prestige", r.prestige);
        out.set("birth", r.birth);
        out.set("alive", r.death == NO_DATE);
        out.set("culture", &d.cultures.name(r.culture));
        out.set("faith", &d.faiths.name(r.faith));
        out.set("liege", &d.chars.name(r.liege));
        out.set("traits", &ids(&d.traits, &r.traits));
        out.set("titles", &ids(&d.titles, &r.titles));
        out.set("spouses", &ids(&d.chars, &r.spouses));
        out.set("perks", &ids(&d.perks, &r.perks));
        out.set("opinions", r.opinions.len() as i64);
        out
    }
}
