//! Сражение в ядре: перестрелка → сеча по дням → слом и погоня.
//!
//! Само, без решений во время боя: всё решено до него — из кого войска, кто
//! ведёт, где принят бой. Войска по видам (данные regiment_types и
//! defines.battle.levy): сила в сече и в перестрелке, стойкость, дух,
//! погоня, прикрытие отхода, натиск конницы, противовесы, местность.
//! Армии не дерутся до последнего: дух падает от потерь, бегства ополчения,
//! гибели рыцарей; сломленная сторона бежит, победитель гонит.
//! Нрав полководца действует сам: горячий бросает конницу раньше, осторожный
//! позже, трус ломается первым. Рыцари в гуще сходятся поединками.
//!
//! Вход и выход — словари (см. CoreBattle.fight); всё случайное — от seed,
//! один и тот же бой даёт один и тот же исход на всех системах.

use godot::prelude::*;

use crate::rng::Rng;
use crate::world::{gstr, num};

#[derive(Clone)]
struct Unit {
    key: GString,
    kind: GString,
    category: GString,
    men: f64,
    start: f64,
    melee: f64,
    ranged: f64,
    toughness: f64,
    morale: f64,
    pursuit: f64,
    screen: f64,
    charge: f64,
    quality: f64,
    levy: bool,
    counters: Vec<(GString, f64)>,
    fled: f64,
    /// Сколько врагов сразил отряд (перестрелка, сеча, погоня) — для опыта.
    dealt: f64,
}

struct Commander {
    id: Variant,
    /// Очки перевеса (военное дело, прибавки, навыки, местность) — считает GDScript.
    adv: f64,
    aggression: f64,
    caution: f64,
    craven: bool,
    pursuit: f64,
    orderly: f64,
    death_mult: f64,
    front: f64,
    // навыки полководца (черты command)
    charge: f64,
    charge_day: f64,
    ranged: f64,
    volleys: i64,
    rearguard: f64,
    steady: f64,
    levy_steady: f64,
    losses: f64,
    luck: f64,
}

struct Knight {
    id: Variant,
    prowess: f64,
    death_mult: f64,
    out: bool,
}

struct Side {
    units: Vec<Unit>,
    cmd: Option<Commander>,
    knights: Vec<Knight>,
    morale: f64,
    mult: f64,
    defense: f64,
    start_men: f64,
    host: Host,
}

/// Умения воинства стороны (специализация войска; считает GDScript, когда они
/// действуют): ополчение не бежит, страх врагу, вождь под охраной, засада,
/// уход без погони, заклинания в перестрелке.
#[derive(Default)]
struct Host {
    levy_hold: bool,
    terror: f64,
    guard: bool,
    ambush: f64,
    slip: bool,
    spells: f64,
}

/// Настройки боя (defines.battle).
struct P {
    max_days: i64,
    min_days: i64,
    skirmish_scale: f64,
    melee_scale: f64,
    morale_per_loss: f64,
    break_morale: f64,
    craven_break: f64,
    rout_frac: f64,
    levy_flee_morale: f64,
    levy_flee_rate: f64,
    flee_morale: f64,
    exchange_shock: f64,
    exchange_cap: f64,
    pursuit_cap: f64,
    refuse_ratio: f64,
    pursuit_scale: f64,
    charge_day: f64,
    luck_min: f64,
    luck_max: f64,
    morale_noise: f64,
    advantage_effect: f64,
    advantage_cap: f64,
    max_counter: f64,
    knight_melee: f64,
    duels_per_day: i64,
    duel_per_prowess: f64,
    knight_kill: f64,
    knight_wound: f64,
    knight_capture: f64,
    knight_morale: f64,
    knight_slain_morale: f64,
    chase_min: f64,
    chase_max: f64,
    loser_cmd_death: f64,
    winner_cmd_death: f64,
    front_safe: f64,
    front_wound: f64,
    exposure_melee: Vec<(GString, f64)>,
    exposure_ranged: Vec<(GString, f64)>,
}

fn f(d: &VarDictionary, k: &str, def: f64) -> f64 {
    match d.get(k) {
        Some(v) if matches!(v.get_type(), VariantType::INT | VariantType::FLOAT) => num(&v),
        _ => def,
    }
}

fn dict(d: &VarDictionary, k: &str) -> VarDictionary {
    d.get(k).and_then(|v| v.try_to::<VarDictionary>().ok()).unwrap_or_default()
}

fn arr(d: &VarDictionary, k: &str) -> VarArray {
    d.get(k).and_then(|v| v.try_to::<VarArray>().ok()).unwrap_or_default()
}

fn pairs(d: &VarDictionary) -> Vec<(GString, f64)> {
    d.iter_shared().filter_map(|(k, v)| gstr(&k).map(|s| (s, num(&v)))).collect()
}

impl P {
    fn read(d: &VarDictionary) -> Self {
        P {
            max_days: f(d, "max_days", 5.0) as i64,
            min_days: f(d, "min_days", 2.0) as i64,
            skirmish_scale: f(d, "skirmish_scale", 0.03),
            melee_scale: f(d, "melee_scale", 0.05),
            morale_per_loss: f(d, "morale_per_loss", 220.0),
            break_morale: f(d, "break_morale", 25.0),
            craven_break: f(d, "craven_break", 15.0),
            rout_frac: f(d, "rout_frac", 0.35),
            levy_flee_morale: f(d, "levy_flee_morale", 45.0),
            levy_flee_rate: f(d, "levy_flee_rate", 0.12),
            flee_morale: f(d, "flee_morale", 0.3),
            exchange_shock: f(d, "exchange_shock", 300.0),
            exchange_cap: f(d, "exchange_cap", 20.0),
            pursuit_cap: f(d, "pursuit_cap", 0.35),
            refuse_ratio: f(d, "refuse_ratio", 3.0),
            pursuit_scale: f(d, "pursuit_scale", 0.1),
            charge_day: f(d, "charge_day", 2.0),
            luck_min: f(d, "luck_min", 0.85),
            luck_max: f(d, "luck_max", 1.15),
            morale_noise: f(d, "morale_noise", 0.0),
            advantage_effect: f(d, "advantage_effect", 0.03),
            advantage_cap: f(d, "advantage_cap", 25.0),
            max_counter: f(d, "max_counter", 0.75),
            knight_melee: f(d, "knight_melee", 8.0),
            duels_per_day: f(d, "duels_per_day", 2.0) as i64,
            duel_per_prowess: f(d, "duel_per_prowess", 0.05),
            knight_kill: f(d, "knight_kill", 0.12),
            knight_wound: f(d, "knight_wound", 0.3),
            knight_capture: f(d, "knight_capture", 0.15),
            knight_morale: f(d, "knight_morale", 3.0),
            knight_slain_morale: f(d, "knight_slain_morale", 5.0),
            chase_min: f(d, "chase_min", 0.5),
            chase_max: f(d, "chase_max", 1.8),
            loser_cmd_death: f(d, "loser_commander_death", 0.04),
            winner_cmd_death: f(d, "winner_commander_death", 0.01),
            front_safe: f(d, "personal_example_safe", 0.03),
            front_wound: f(d, "personal_example_wound", 2.0),
            exposure_melee: pairs(&dict(d, "exposure_melee")),
            exposure_ranged: pairs(&dict(d, "exposure_ranged")),
        }
    }
}

fn exposure(list: &[(GString, f64)], u: &Unit) -> f64 {
    let key = if u.levy { GString::from("levy") } else { u.category.clone() };
    list.iter().find(|(k, _)| *k == key).map(|(_, v)| *v).unwrap_or(1.0)
}

fn read_side(d: &VarDictionary) -> Side {
    let mut units = Vec::new();
    for u in arr(d, "units").iter_shared() {
        let Ok(ud) = u.try_to::<VarDictionary>() else { continue };
        let men = f(&ud, "men", 0.0);
        if men <= 0.0 {
            continue;
        }
        units.push(Unit {
            key: ud.get("key").and_then(|v| gstr(&v)).unwrap_or_default(),
            kind: ud.get("type").and_then(|v| gstr(&v)).unwrap_or_default(),
            category: ud.get("category").and_then(|v| gstr(&v)).unwrap_or_default(),
            men,
            start: men,
            melee: f(&ud, "melee", 1.0),
            ranged: f(&ud, "ranged", 0.0),
            toughness: f(&ud, "toughness", 1.0).max(0.1),
            morale: f(&ud, "morale", 50.0),
            pursuit: f(&ud, "pursuit", 0.5),
            screen: f(&ud, "screen", 0.5),
            charge: f(&ud, "charge", 0.0),
            quality: f(&ud, "quality", 1.0).max(0.0),
            levy: ud.get("levy").map(|v| v.booleanize()).unwrap_or(false),
            counters: pairs(&dict(&ud, "counters")),
            fled: 0.0,
            dealt: 0.0,
        });
    }
    let cmd = d.get("commander").and_then(|v| v.try_to::<VarDictionary>().ok()).map(|c| Commander {
        id: c.get("id").unwrap_or_default(),
        adv: f(&c, "adv", 0.0),
        aggression: f(&c, "aggression", 0.0),
        caution: f(&c, "caution", 0.0),
        craven: c.get("craven").map(|v| v.booleanize()).unwrap_or(false),
        pursuit: f(&c, "pursuit", 0.0),
        orderly: f(&c, "orderly", 0.0),
        death_mult: f(&c, "death_mult", 1.0),
        front: f(&c, "front", 0.0),
        charge: f(&c, "charge", 0.0),
        charge_day: f(&c, "charge_day", 0.0),
        ranged: f(&c, "ranged", 0.0),
        volleys: f(&c, "volleys", 0.0) as i64,
        rearguard: f(&c, "rearguard", 0.0).clamp(0.0, 0.9),
        steady: f(&c, "steady", 0.0).clamp(0.0, 0.8),
        levy_steady: f(&c, "levy_steady", 0.0),
        losses: f(&c, "losses", 0.0).clamp(-0.9, 0.6),
        luck: f(&c, "luck", 0.0).clamp(0.0, 1.0),
    });
    let knights = arr(d, "knights")
        .iter_shared()
        .filter_map(|k| k.try_to::<VarDictionary>().ok())
        .map(|k| Knight { id: k.get("id").unwrap_or_default(), prowess: f(&k, "prowess", 5.0), death_mult: f(&k, "death_mult", 1.0), out: false })
        .collect();
    let start_men: f64 = units.iter().map(|u| u.men).sum();
    // дух стороны — средний дух войск по числу людей плюс прибавка
    let morale = if start_men > 0.0 { units.iter().map(|u| u.morale * u.men).sum::<f64>() / start_men } else { 50.0 };
    Side {
        units,
        cmd,
        knights,
        morale: (morale + f(d, "morale_bonus", 0.0)).clamp(5.0, 100.0),
        mult: f(d, "mult", 1.0).max(0.0),
        defense: f(d, "defense", 0.0),
        start_men,
        host: {
            let h = dict(d, "host");
            Host {
                levy_hold: h.get("levy_hold").map(|v| v.booleanize()).unwrap_or(false),
                terror: f(&h, "terror", 0.0).max(0.0),
                guard: h.get("guard").map(|v| v.booleanize()).unwrap_or(false),
                ambush: f(&h, "ambush", 0.0).max(0.0),
                slip: h.get("slip").map(|v| v.booleanize()).unwrap_or(false),
                spells: f(&h, "spells", 0.0).max(0.0),
            }
        },
    }
}

impl Side {
    fn men(&self) -> f64 {
        self.units.iter().map(|u| u.men).sum()
    }

    fn adv(&self) -> f64 {
        self.cmd.as_ref().map(|c| c.adv).unwrap_or(0.0)
    }

    /// Сила стороны от перевеса полководцев: каждое очко разницы — advantage_effect.
    fn cmd_mult(&self, enemy: &Side, p: &P) -> f64 {
        let d = (self.adv() - enemy.adv()).clamp(-p.advantage_cap, p.advantage_cap);
        (1.0 + d * p.advantage_effect).max(0.2)
    }

    fn cmd_f(&self, f: impl Fn(&Commander) -> f64) -> f64 {
        self.cmd.as_ref().map(f).unwrap_or(0.0)
    }

    fn break_at(&self, p: &P) -> f64 {
        let craven = self.cmd.as_ref().map(|c| c.craven).unwrap_or(false);
        p.break_morale + if craven { p.craven_break } else { 0.0 }
    }

    /// День натиска конницы: горячий раньше, осторожный позже.
    fn charge_day(&self, p: &P) -> i64 {
        let (a, c, s) = self.cmd.as_ref().map(|c| (c.aggression, c.caution, c.charge_day)).unwrap_or((0.0, 0.0, 0.0));
        ((p.charge_day - a + c - s).round() as i64).clamp(1, p.max_days.max(1))
    }
}

struct Ev {
    day: i64,
    kind: &'static str,
    side: usize,
    n: f64,
    a: Variant,
    b: Variant,
}

/// Удача дня; narrow — насколько уже разброс (осторожный стратег).
fn luck(rng: &mut Rng, p: &P, narrow: f64) -> f64 {
    let r = (rng.next_u64() >> 11) as f64 / (1u64 << 53) as f64;
    let l = p.luck_min + (p.luck_max - p.luck_min) * r;
    1.0 + (l - 1.0) * (1.0 - narrow)
}

fn roll(rng: &mut Rng) -> f64 {
    (rng.next_u64() >> 11) as f64 / (1u64 << 53) as f64
}

/// Урон стороны `from` по стороне `to`: потери по отрядам `to` (людей).
/// Удар стороны from по стороне to: потери защищающихся по отрядам и сколько
/// из них сразил каждый отряд нападающих.
fn strike(sides: &[Side; 2], from: usize, to: usize, ranged: bool, day: i64, p: &P, rng: &mut Rng) -> (Vec<f64>, Vec<f64>) {
    let att = &sides[from];
    let def = &sides[to];
    let mut lost = vec![0.0; def.units.len()];
    let mut dealt = vec![0.0; att.units.len()];
    let exp_list = if ranged { &p.exposure_ranged } else { &p.exposure_melee };
    let weights: Vec<f64> = def.units.iter().map(|u| u.men * exposure(exp_list, u)).collect();
    let wsum: f64 = weights.iter().sum();
    if wsum <= 0.0 {
        return (lost, dealt);
    }
    // вклад каждого отряда нападающих в потери каждого отряда защищающихся
    let mut by: Vec<Vec<f64>> = vec![vec![0.0; def.units.len()]; att.units.len()];
    // противовесы: сколько у противника тех, кто контрит отряд (по людям)
    let men_of = |s: &Side, kind: &GString| -> f64 { s.units.iter().filter(|u| u.kind == *kind).map(|u| u.men).sum() };
    let mut cmult = att.cmd_mult(def, p) * att.mult * luck(rng, p, att.cmd_f(|c| c.luck));
    // засада: перестрелка и первый день сечи — из укрытия
    if att.host.ambush > 0.0 && day <= 1 {
        cmult *= 1.0 + att.host.ambush;
    }
    let charge_day = att.charge_day(p);
    let scale = if ranged { p.skirmish_scale } else { p.melee_scale };
    // навыки: залпы сильнее, натиск страшнее; свои потери защищающейся стороны меньше
    let ranged_mult = 1.0 + att.cmd_f(|c| c.ranged);
    let charge_mult = 1.0 + att.cmd_f(|c| c.charge);
    let guard = 1.0 - def.cmd_f(|c| c.losses);
    for (j, u) in att.units.iter().enumerate() {
        if u.men <= 0.0 {
            continue;
        }
        let mut power = if ranged { u.ranged } else { u.melee };
        if power <= 0.0 {
            continue;
        }
        if !ranged && u.charge > 0.0 && day == charge_day {
            power *= 1.0 + u.charge * charge_mult;
        }
        if ranged {
            power *= ranged_mult;
        }
        // ослабление от вражеских противовесов
        let mut pen = 0.0;
        for e in def.units.iter() {
            if let Some((_, c)) = e.counters.iter().find(|(k, _)| *k == u.kind) {
                pen += c * (e.men / men_of(att, &u.kind).max(1.0)).min(1.0);
            }
        }
        let pen = pen.min(p.max_counter);
        let base = u.men * power * u.quality * (1.0 - pen) * cmult * scale;
        for (i, v) in def.units.iter().enumerate() {
            if v.men <= 0.0 {
                continue;
            }
            let bonus = u.counters.iter().find(|(k, _)| *k == v.kind).map(|(_, c)| *c).unwrap_or(0.0);
            let dmg = base * weights[i] / wsum * (1.0 + bonus);
            let k = dmg * guard / (v.toughness * (1.0 + def.defense));
            lost[i] += k;
            by[j][i] += k;
        }
    }
    for (i, v) in def.units.iter().enumerate() {
        let capped = lost[i].min(v.men);
        let f = if lost[i] > 0.0 { capped / lost[i] } else { 0.0 };
        for j in 0..att.units.len() {
            dealt[j] += by[j][i] * f;
        }
        lost[i] = capped;
    }
    (lost, dealt)
}

/// Заклинания боевых магов (умение воинства spells): удар по войскам врага в
/// перестрелке — сила в «воинах-стрелках», по открытости для стрел.
fn magic(sides: &[Side; 2], from: usize, to: usize, p: &P, rng: &mut Rng) -> Vec<f64> {
    let att = &sides[from];
    let def = &sides[to];
    let mut lost = vec![0.0; def.units.len()];
    if att.host.spells <= 0.0 {
        return lost;
    }
    let weights: Vec<f64> = def.units.iter().map(|u| u.men * exposure(&p.exposure_ranged, u)).collect();
    let wsum: f64 = weights.iter().sum();
    if wsum <= 0.0 {
        return lost;
    }
    let dmg = att.host.spells * p.skirmish_scale * att.mult * luck(rng, p, 0.0);
    for (i, v) in def.units.iter().enumerate() {
        lost[i] = (dmg * weights[i] / wsum / (v.toughness * (1.0 + def.defense))).min(v.men);
    }
    lost
}

/// Засчитать отрядам стороны сражённых врагов.
fn credit(side: &mut Side, dealt: &[f64]) {
    for (u, d) in side.units.iter_mut().zip(dealt) {
        u.dealt += d;
    }
}

fn apply(side: &mut Side, lost: &[f64]) -> f64 {
    let mut total = 0.0;
    for (u, l) in side.units.iter_mut().zip(lost) {
        let l = l.min(u.men);
        u.men -= l;
        total += l;
    }
    total
}

/// Поединки рыцарей в гуще (за день): судьбы и сдвиг духа.
fn duels(sides: &mut [Side; 2], day: i64, p: &P, rng: &mut Rng, evs: &mut Vec<Ev>, fates: &mut Vec<(Variant, usize, &'static str, Variant)>) {
    for _ in 0..p.duels_per_day {
        let a: Vec<usize> = (0..sides[0].knights.len()).filter(|i| !sides[0].knights[*i].out).collect();
        let b: Vec<usize> = (0..sides[1].knights.len()).filter(|i| !sides[1].knights[*i].out).collect();
        if a.is_empty() || b.is_empty() {
            return;
        }
        let ia = a[rng.below(a.len())];
        let ib = b[rng.below(b.len())];
        let pa = sides[0].knights[ia].prowess;
        let pb = sides[1].knights[ib].prowess;
        let chance = (0.5 + (pa - pb) * p.duel_per_prowess).clamp(0.1, 0.9);
        let (w, l, wi, li) = if roll(rng) < chance { (0usize, 1usize, ia, ib) } else { (1usize, 0usize, ib, ia) };
        let r = roll(rng);
        let dm = sides[l].knights[li].death_mult;
        let fate: &'static str = if r < p.knight_kill * dm {
            "killed"
        } else if r < p.knight_kill * dm + p.knight_capture {
            "captured"
        } else if r < p.knight_kill * dm + p.knight_capture + p.knight_wound {
            "wounded"
        } else {
            "driven_off"
        };
        sides[l].knights[li].out = true;
        let winner_id = sides[w].knights[wi].id.clone();
        let loser_id = sides[l].knights[li].id.clone();
        let hit = if fate == "killed" { p.knight_slain_morale } else { p.knight_morale };
        sides[w].morale = (sides[w].morale + p.knight_morale).min(100.0);
        sides[l].morale -= hit;
        fates.push((loser_id.clone(), l, fate, winner_id.clone()));
        evs.push(Ev { day, kind: "duel", side: w, n: 0.0, a: winner_id, b: loser_id });
    }
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct CoreBattle {
    base: Base<RefCounted>,
}

#[godot_api]
impl CoreBattle {
    /// Бой двух сторон. Вход: {seed, params, sides: [сторона, сторона]};
    /// сторона: {units: [{key, type, category, men, melee, ranged, toughness,
    /// morale, pursuit, screen, charge, quality, levy, counters}], commander:
    /// {id, martial, adv, aggression, caution, craven, pursuit, orderly,
    /// death_mult, front}, knights: [{id, prowess, death_mult}], morale_bonus,
    /// mult, defense}. Выход: {winner, days, log, units, knights, events,
    /// commander, lost, start}.
    #[func]
    fn fight(&self, input: VarDictionary) -> VarDictionary {
        let p = P::read(&dict(&input, "params"));
        let mut rng = Rng::new(f(&input, "seed", 1.0) as i64 as u64);
        let sides_in = arr(&input, "sides");
        let s0 = sides_in.get(0).and_then(|v| v.try_to::<VarDictionary>().ok()).unwrap_or_default();
        let s1 = sides_in.get(1).and_then(|v| v.try_to::<VarDictionary>().ok()).unwrap_or_default();
        let mut sides = [read_side(&s0), read_side(&s1)];
        let mut evs: Vec<Ev> = Vec::new();
        let mut fates: Vec<(Variant, usize, &'static str, Variant)> = Vec::new();
        let mut log = VarArray::new();
        let mut lost_total = [0.0f64; 2];

        let push_log = |log: &mut VarArray, day: i64, phase: &str, sides: &[Side; 2], lost: [f64; 2]| {
            let mut e = VarDictionary::new();
            e.set("day", day);
            e.set("phase", phase);
            let m: VarArray = [Variant::from(sides[0].morale.max(0.0).round()), Variant::from(sides[1].morale.max(0.0).round())].into_iter().collect();
            e.set("morale", &m);
            let l: VarArray = [Variant::from(lost[0].round()), Variant::from(lost[1].round())].into_iter().collect();
            e.set("lost", &l);
            let men: VarArray = [Variant::from(sides[0].men().round()), Variant::from(sides[1].men().round())].into_iter().collect();
            e.set("men", &men);
            log.push(&e.to_variant());
        };

        // ---------------------------------------------- перестрелка
        // мастер залпов даёт своим лишние залпы
        let volleys = [sides[0].cmd_f(|c| c.volleys as f64) as i64, sides[1].cmd_f(|c| c.volleys as f64) as i64];
        let (mut l0, mut l1) = (0.0, 0.0);
        // страх: воинство, перед которым бежит ополчение, бьёт по духу врага до боя
        for s in 0..2 {
            let t = sides[s].host.terror;
            if t > 0.0 {
                sides[1 - s].morale -= t * 0.5;
                evs.push(Ev { day: 0, kind: "terror", side: s, n: 0.0, a: Variant::nil(), b: Variant::nil() });
            }
            if sides[s].host.ambush > 0.0 {
                evs.push(Ev { day: 0, kind: "ambush", side: s, n: 0.0, a: Variant::nil(), b: Variant::nil() });
            }
        }
        // заклинания боевых магов — до первых залпов
        {
            let m0 = magic(&sides, 0, 1, &p, &mut rng);
            let m1 = magic(&sides, 1, 0, &p, &mut rng);
            let (g1, g0) = (apply(&mut sides[1], &m0), apply(&mut sides[0], &m1));
            l1 += g1;
            l0 += g0;
            for (s, g) in [(0usize, g1), (1usize, g0)] {
                if g >= 1.0 {
                    evs.push(Ev { day: 0, kind: "spells", side: s, n: g.round(), a: Variant::nil(), b: Variant::nil() });
                }
            }
        }
        for round in 0..=volleys[0].max(volleys[1]) {
            let (r0, k0) = if round <= volleys[0] { strike(&sides, 0, 1, true, 0, &p, &mut rng) } else { (vec![0.0; sides[1].units.len()], vec![0.0; sides[0].units.len()]) };
            let (r1, k1) = if round <= volleys[1] { strike(&sides, 1, 0, true, 0, &p, &mut rng) } else { (vec![0.0; sides[0].units.len()], vec![0.0; sides[1].units.len()]) };
            l1 += apply(&mut sides[1], &r0);
            l0 += apply(&mut sides[0], &r1);
            credit(&mut sides[0], &k0);
            credit(&mut sides[1], &k1);
        }
        for s in 0..2 {
            if volleys[s] > 0 {
                evs.push(Ev { day: 0, kind: "volley", side: s, n: volleys[s] as f64, a: Variant::nil(), b: Variant::nil() });
            }
        }
        lost_total[0] += l0;
        lost_total[1] += l1;
        for (i, l) in [l0, l1].iter().enumerate() {
            let s = &mut sides[i];
            let steady = 1.0 - s.cmd_f(|c| c.steady);
            if s.start_men > 0.0 {
                s.morale -= p.morale_per_loss * l / s.start_men * steady;
            }
        }
        if l0 > 0.0 || l1 > 0.0 {
            evs.push(Ev { day: 0, kind: "skirmish", side: if l1 >= l0 { 0 } else { 1 }, n: (l1 - l0).abs().round(), a: Variant::nil(), b: Variant::nil() });
        }
        push_log(&mut log, 0, "skirmish", &sides, [l0, l1]);

        // ---------------------------------------------- отказ от боя
        // войско втрое меньше вражеского не принимает сечи и отходит
        let mut refused: Option<usize> = None;
        if p.refuse_ratio > 0.0 {
            // по силе с перевесом полководцев: малое войско с сильным вождём может принять сечу
            let (m0, m1) = (sides[0].men() * sides[0].cmd_mult(&sides[1], &p), sides[1].men() * sides[1].cmd_mult(&sides[0], &p));
            if m0 * p.refuse_ratio < m1 {
                refused = Some(0);
            } else if m1 * p.refuse_ratio < m0 {
                refused = Some(1);
            }
        }

        // ---------------------------------------------- сеча
        let mut broke: Option<usize> = None;
        let mut day = 0;
        while day < p.max_days && broke.is_none() && refused.is_none() {
            day += 1;
            for s in 0..2 {
                if sides[s].charge_day(&p) == day && sides[s].units.iter().any(|u| u.charge > 0.0 && u.men > 0.0) {
                    evs.push(Ev { day, kind: "charge", side: s, n: 0.0, a: Variant::nil(), b: Variant::nil() });
                }
            }
            let (m0, c0) = strike(&sides, 0, 1, false, day, &p, &mut rng);
            let (m1, c1) = strike(&sides, 1, 0, false, day, &p, &mut rng);
            credit(&mut sides[0], &c0);
            credit(&mut sides[1], &c1);
            // рыцари бьются в гуще и бьют сами
            let k0: f64 = sides[0].knights.iter().filter(|k| !k.out).map(|k| k.prowess).sum::<f64>() * p.knight_melee * p.melee_scale;
            let k1: f64 = sides[1].knights.iter().filter(|k| !k.out).map(|k| k.prowess).sum::<f64>() * p.knight_melee * p.melee_scale;
            let mut d1 = m0.clone();
            let mut d0 = m1.clone();
            spread(&mut d1, &sides[1], k0);
            spread(&mut d0, &sides[0], k1);
            let l1 = apply(&mut sides[1], &d1);
            let l0 = apply(&mut sides[0], &d0);
            lost_total[0] += l0;
            lost_total[1] += l1;
            for (i, l) in [l0, l1].iter().enumerate() {
                let other = if i == 0 { l1 } else { l0 };
                let s = &mut sides[i];
                let steady = 1.0 - s.cmd_f(|c| c.steady);
                if s.start_men > 0.0 {
                    s.morale -= p.morale_per_loss * l / s.start_men * steady;
                    // проигранный размен бьёт по духу сильнее
                    s.morale -= (p.exchange_shock * (l - other).max(0.0) / s.start_men).min(p.exchange_cap) * steady;
                }
            }
            duels(&mut sides, day, &p, &mut rng, &mut evs, &mut fates);
            // слухи, знамения, сумятица: дух колеблется (у осторожного — меньше)
            if p.morale_noise > 0.0 {
                for s in 0..2 {
                    let narrow = 1.0 - sides[s].cmd_f(|c| c.luck);
                    sides[s].morale += (roll(&mut rng) * 2.0 - 1.0) * p.morale_noise * narrow;
                }
            }
            // ополчение бежит, когда дух низок
            for s in 0..2 {
                // страх перед вражеским воинством гонит ополчение раньше; стойкое воинство не бежит
                let terror = sides[1 - s].host.terror;
                if !sides[s].host.levy_hold && sides[s].morale < p.levy_flee_morale - sides[s].cmd_f(|c| c.levy_steady) + terror {
                    let mut fled = 0.0;
                    for u in sides[s].units.iter_mut().filter(|u| u.levy && u.men > 0.0) {
                        let x = u.men * p.levy_flee_rate;
                        u.men -= x;
                        u.fled += x;
                        fled += x;
                    }
                    if fled >= 1.0 {
                        lost_total[s] += fled;
                        let sm = sides[s].start_men.max(1.0);
                        sides[s].morale -= p.morale_per_loss * p.flee_morale * fled / sm;
                        evs.push(Ev { day, kind: "levy_fled", side: s, n: fled.round(), a: Variant::nil(), b: Variant::nil() });
                    }
                }
            }
            push_log(&mut log, day, "melee", &sides, [l0, l1]);
            // слом: дух у края или войско растаяло
            // первые дни держатся, пока дух не иссяк совсем
            let early = day < p.min_days;
            let b0 = (sides[0].morale <= sides[0].break_at(&p) && (!early || sides[0].morale <= 0.0)) || sides[0].men() < sides[0].start_men * p.rout_frac;
            let b1 = (sides[1].morale <= sides[1].break_at(&p) && (!early || sides[1].morale <= 0.0)) || sides[1].men() < sides[1].start_men * p.rout_frac;
            if b0 || b1 {
                broke = Some(if b0 && b1 {
                    // ломается тот, у кого дух ниже
                    if sides[0].morale - sides[0].break_at(&p) <= sides[1].morale - sides[1].break_at(&p) {
                        0
                    } else {
                        1
                    }
                } else if b0 {
                    0
                } else {
                    1
                });
            }
        }
        // не сломился никто — отходит тот, у кого дух ниже
        let loser = broke.or(refused).unwrap_or_else(|| {
            let r0 = sides[0].morale / sides[0].break_at(&p).max(1.0);
            let r1 = sides[1].morale / sides[1].break_at(&p).max(1.0);
            if r0 <= r1 {
                0
            } else {
                1
            }
        });
        let winner = 1 - loser;
        let end_kind = if broke.is_some() {
            "broke"
        } else if refused.is_some() {
            "refused"
        } else {
            "withdrew"
        };
        evs.push(Ev { day, kind: end_kind, side: loser, n: 0.0, a: Variant::nil(), b: Variant::nil() });

        // ---------------------------------------------- погоня
        let chase = (1.0 + sides[winner].cmd.as_ref().map(|c| c.pursuit).unwrap_or(0.0)
            - sides[loser].cmd.as_ref().map(|c| c.orderly).unwrap_or(0.0))
        .clamp(p.chase_min, p.chase_max);
        let pursuers: f64 = sides[winner].units.iter().map(|u| u.men * u.pursuit * u.quality).sum::<f64>() * sides[winner].mult;
        let screen: f64 = sides[loser].units.iter().map(|u| u.men * u.screen).sum::<f64>();
        let lmen = sides[loser].men().max(1.0);
        let routed = if broke.is_some() { 1.0 } else { 0.4 };
        let mut chase_loss = pursuers * p.pursuit_scale * chase * routed * (1.0 - (screen / (screen + pursuers).max(1.0)) * 0.5);
        chase_loss = chase_loss.min(lmen * p.pursuit_cap);
        // хранитель отхода уводит разбитых в порядке
        let rg = sides[loser].cmd_f(|c| c.rearguard);
        // лесное воинство уходит тропами, погоне его не догнать
        if sides[loser].host.slip && chase_loss >= 1.0 {
            evs.push(Ev { day, kind: "slipped", side: loser, n: chase_loss.round(), a: Variant::nil(), b: Variant::nil() });
            chase_loss = 0.0;
        }
        if rg > 0.0 && chase_loss >= 1.0 {
            evs.push(Ev { day, kind: "rearguard", side: loser, n: (chase_loss * rg).round(), a: Variant::nil(), b: Variant::nil() });
            chase_loss *= 1.0 - rg;
        }
        if chase_loss >= 1.0 {
            let ws: Vec<f64> = sides[loser].units.iter().map(|u| u.men * exposure(&p.exposure_melee, u)).collect();
            let wsum: f64 = ws.iter().sum::<f64>().max(1.0);
            let lost: Vec<f64> = ws.iter().map(|w| chase_loss * w / wsum).collect();
            let got = apply(&mut sides[loser], &lost);
            lost_total[loser] += got;
            // сражённых в погоне — гнавшим, по их доле в погоне
            let ps: Vec<f64> = sides[winner].units.iter().map(|u| u.men * u.pursuit * u.quality).collect();
            let psum: f64 = ps.iter().sum::<f64>();
            if psum > 0.0 {
                let d: Vec<f64> = ps.iter().map(|x| got * x / psum).collect();
                credit(&mut sides[winner], &d);
            }
            evs.push(Ev { day, kind: "pursuit", side: winner, n: got.round(), a: Variant::nil(), b: Variant::nil() });
            let mut ll = [0.0; 2];
            ll[loser] = got;
            push_log(&mut log, day, "pursuit", &sides, ll);
        }

        // ---------------------------------------------- полководцы
        let mut cmd_fate = [GString::new(), GString::new()];
        for s in 0..2 {
            let Some(c) = sides[s].cmd.as_ref() else { continue };
            if c.front > p.front_safe && roll(&mut rng) < (c.front - p.front_safe) * p.front_wound {
                cmd_fate[s] = "wounded".into();
            }
        }
        // родовая дружина: пока она стоит (сторона не бежит), вождь не гибнет
        let guarded = |s: usize| sides[s].host.guard && broke != Some(s);
        if let Some(c) = sides[loser].cmd.as_ref() {
            if roll(&mut rng) < p.loser_cmd_death * c.death_mult {
                if guarded(loser) {
                    evs.push(Ev { day, kind: "guarded", side: loser, n: 0.0, a: c.id.clone(), b: Variant::nil() });
                } else {
                    cmd_fate[loser] = "killed".into();
                    evs.push(Ev { day, kind: "commander_fell", side: loser, n: 0.0, a: c.id.clone(), b: Variant::nil() });
                }
            }
        }
        if cmd_fate[loser] != GString::from("killed") {
            if let Some(c) = sides[winner].cmd.as_ref() {
                if roll(&mut rng) < p.winner_cmd_death * c.death_mult {
                    if guarded(winner) {
                        evs.push(Ev { day, kind: "guarded", side: winner, n: 0.0, a: c.id.clone(), b: Variant::nil() });
                    } else {
                        cmd_fate[winner] = "killed".into();
                        evs.push(Ev { day, kind: "commander_fell", side: winner, n: 0.0, a: c.id.clone(), b: Variant::nil() });
                    }
                }
            }
        }

        // ---------------------------------------------- итог
        let mut out = VarDictionary::new();
        out.set("winner", winner as i64);
        out.set("days", day);
        out.set("broke", broke.is_some());
        out.set("log", &log);
        let mut units = VarArray::new();
        for s in sides.iter() {
            let mut list = VarArray::new();
            for u in s.units.iter() {
                let mut e = VarDictionary::new();
                e.set("key", &u.key);
                e.set("type", &u.kind);
                e.set("men", u.start.round());
                e.set("left", u.men.round());
                e.set("fled", u.fled.round());
                e.set("kills", u.dealt.round());
                list.push(&e.to_variant());
            }
            units.push(&list.to_variant());
        }
        out.set("units", &units);
        let mut kn = VarArray::new();
        for (id, side, fate, by) in fates.iter() {
            let mut e = VarDictionary::new();
            e.set("id", id);
            e.set("side", *side as i64);
            e.set("fate", *fate);
            e.set("by", by);
            kn.push(&e.to_variant());
        }
        out.set("knights", &kn);
        let mut ev = VarArray::new();
        for e in evs.iter() {
            let mut d = VarDictionary::new();
            d.set("day", e.day);
            d.set("kind", e.kind);
            d.set("side", e.side as i64);
            if e.n != 0.0 {
                d.set("n", e.n);
            }
            if !e.a.is_nil() {
                d.set("a", &e.a);
            }
            if !e.b.is_nil() {
                d.set("b", &e.b);
            }
            ev.push(&d.to_variant());
        }
        out.set("events", &ev);
        let cf: VarArray = cmd_fate.iter().map(|s| s.to_variant()).collect();
        out.set("commander", &cf);
        let lt: VarArray = lost_total.iter().map(|x| Variant::from(x.round())).collect();
        out.set("lost", &lt);
        let st: VarArray = sides.iter().map(|s| Variant::from(s.start_men.round())).collect();
        out.set("start", &st);
        let mo: VarArray = sides.iter().map(|s| Variant::from(s.morale.max(0.0).round())).collect();
        out.set("morale", &mo);
        out
    }
}

/// Урон рыцарей по отрядам стороны — пропорционально людям.
fn spread(lost: &mut [f64], side: &Side, dmg: f64) {
    if dmg <= 0.0 {
        return;
    }
    let total: f64 = side.units.iter().map(|u| u.men).sum();
    if total <= 0.0 {
        return;
    }
    for (i, u) in side.units.iter().enumerate() {
        lost[i] = (lost[i] + dmg * u.men / total / u.toughness).min(u.men);
    }
}
