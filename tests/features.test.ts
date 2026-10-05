import { beforeAll, describe, expect, it } from 'vitest';
import type { Engine } from '../src/engine/engine';
import { appointCouncillor, councilCandidates, dismissCouncillor, setCouncilTask } from '../src/engine/features/council';
import { createFaction, factionOf, factionPower, factionRevolt, joinFaction } from '../src/engine/features/factions';
import { canUnlockPerk, perkCost, setFocus, unlockPerk } from '../src/engine/features/lifestyles';
import { imprison, prisonersOf, ransomCost, releasePrisoner } from '../src/engine/features/prison';
import { armyRegimentBonus, recruitRegiment, regimentCap } from '../src/engine/features/regiments';
import { makeContext } from '../src/engine/script/context';
import { evalTrigger, evalValue, runEffect } from '../src/engine/script/interpreter';
import { militaryStrength } from '../src/engine/world/economy';
import { disbandArmy, raiseArmy } from '../src/engine/world/military';
import { opinion } from '../src/engine/world/opinion';
import { skill, stat } from '../src/engine/world/stats';
import { declareWar, warscore } from '../src/engine/world/war';
import { memoryMod, realEngine } from './helpers';
import { loadNodeModPackages } from '../src/engine/mods/nodeSource';
import { Engine as EngineClass } from '../src/engine/engine';

let engine: Engine;
beforeAll(async () => {
  engine = await realEngine(['core']);
});

const newGame = () => engine.newGame('b1066', 11);

describe('образ жизни', () => {
  it('фокус даёт модификаторы, опыт открывает перк, конец дерева даёт черту', () => {
    const g = newGame();
    const w = g.char('william')!;
    expect(setFocus(g, w, 'focus_wealth', true)).toBe(true);
    expect(stat(g, w, 'tax_mult')).toBeGreaterThanOrEqual(0.1);
    const before = stat(g, w, 'build_cost_mult');
    const ctx = makeContext(g, { type: 'character', id: w.id });
    runEffect(ctx, ctx.root, { add_lifestyle_xp: 10000 });
    expect(canUnlockPerk(g, w, 'master_builder')).toBe(true);
    expect(canUnlockPerk(g, w, 'thriving_lands')).toBe(false); // сначала предыдущий
    const cost = perkCost(g, w, 'stewardship_lifestyle');
    expect(unlockPerk(g, w, 'master_builder')).toBe(true);
    expect(stat(g, w, 'build_cost_mult')).toBeCloseTo(before - 0.15);
    expect(perkCost(g, w, 'stewardship_lifestyle')).toBeGreaterThan(cost);
    for (const p of ['thriving_lands', 'bountiful_harvests', 'royal_architect']) runEffect(ctx, ctx.root, { add_perk: p });
    expect(w.traits).toContain('architect');
    expect(evalTrigger(ctx, ctx.root, { has_perk: 'royal_architect', has_lifestyle: 'stewardship_lifestyle' })).toBe(true);
  });

  it('ИИ сам выбирает фокус и копит опыт', () => {
    const g = newGame();
    for (let i = 0; i < 400; i++) g.tick();
    const adults = g.living().filter((c) => c.lifestyle?.focus);
    expect(adults.length).toBeGreaterThan(100);
    expect(adults.some((c) => (c.lifestyle?.perks.length ?? 0) > 0)).toBe(true);
  });
});

describe('совет', () => {
  it('советник усиливает правителя по своему навыку и задаче', () => {
    const g = newGame();
    for (let i = 0; i < 40; i++) g.tick(); // первичное заполнение совета
    const h = g.char('harold')!;
    expect(Object.values(h.council ?? {}).filter((s) => s.holder).length).toBeGreaterThanOrEqual(3);
    const marshal = h.council!.marshal?.holder;
    expect(marshal).toBeTruthy();
    setCouncilTask(g, h, 'marshal', 'organize_levies');
    g.statCache.clear();
    const m = g.char(marshal)!;
    expect(stat(g, h, 'levy_mult')).toBeGreaterThanOrEqual(skill(g, m, 'martial') * 0.012 - 1e-9);
    expect(opinion(g, m, h)).toBeGreaterThan(-100);
    dismissCouncillor(g, h, 'marshal');
    expect(h.council!.marshal.holder).toBeUndefined();
    expect(m.opinions[h.id]?.some((e) => e.mod === 'dismissed_from_council')).toBe(true);
    const cand = councilCandidates(g, h, 'marshal')[0];
    expect(appointCouncillor(g, h, 'marshal', cand.id)).toBe(true);
    const ctx = makeContext(g, { type: 'character', id: cand.id });
    expect(evalTrigger(ctx, ctx.root, { is_councillor: 'marshal' })).toBe(true);
  });
});

describe('темница', () => {
  it('заключение, выкуп, освобождение; пленник не правит', () => {
    const g = newGame();
    const w = g.char('william')!;
    const h = g.char('harold')!;
    expect(imprison(g, w, h)).toBe(true);
    expect(prisonersOf(g, w.id).map((c) => c.id)).toContain('harold');
    expect(ransomCost(g, h)).toBeGreaterThan(0);
    const ctx = makeContext(g, { type: 'character', id: h.id }, { jailer: { type: 'character', id: w.id } });
    expect(evalTrigger(ctx, ctx.root, { is_imprisoned: 'yes', is_imprisoned_by: 'scope:jailer' })).toBe(true);
    expect(evalValue(ctx, ctx.root, 'ransom_cost')).toBe(ransomCost(g, h));
    // взаимодействия с пленником: только помеченные prisoner: only
    const shown = g.content.all('interactions').filter((d: any) => d.prisoner === 'only').map((d: any) => d.id);
    expect(shown).toEqual(expect.arrayContaining(['release_prisoner', 'execute_prisoner', 'demand_ransom']));
    releasePrisoner(g, h);
    expect(h.prison).toBeUndefined();
  });

  it('плен вражеского лидера даёт счёт войны', () => {
    const g = newGame();
    const w = g.char('william')!;
    const h = g.char('harold')!;
    const t = { cb: 'claim', defender: h.id, title: 'k_england', counties: [] as string[] };
    const wr = declareWar(g, w, t, { free: true })!;
    const before = warscore(g, wr).total;
    imprison(g, w, h, { war: wr.id });
    expect(warscore(g, wr).total).toBeGreaterThan(before);
  });
});

describe('фракции', () => {
  it('вассалы создают фракцию, её сила считается, мятеж — война со всеми членами', () => {
    const g = newGame();
    const h = g.char('harold')!;
    const vassals = g.vassalsOf(h.id).filter((v) => !v.prison);
    expect(vassals.length).toBeGreaterThan(2);
    const [a, b, c] = vassals;
    const f = createFaction(g, 'independence_faction', a)!;
    expect(f).toBeTruthy();
    joinFaction(g, b, f);
    joinFaction(g, c, f);
    expect(factionOf(g, b)?.id).toBe(f.id);
    expect(factionPower(g, f)).toBeGreaterThan(0);
    expect(factionRevolt(g, f)).toBe(true);
    const war = Object.values(g.state.wars).find((x) => x.faction === f.id)!;
    expect(war.defender).toBe(h.id);
    expect(war.attackers).toEqual(expect.arrayContaining([a.id, b.id, c.id]));
    // мятежники не дают сюзерену войск
    expect(militaryStrength(g, h)).toBeGreaterThan(0);
  });
});

describe('профессиональные войска', () => {
  it('найм, предел, армия берёт отряды, контры в бою', () => {
    const g = newGame();
    const w = g.char('william')!;
    w.gold = 5000;
    const cap = regimentCap(g, w);
    while ((w.regiments?.length ?? 0) < cap) expect(recruitRegiment(g, w, 'pikemen')).toBeTruthy();
    expect(recruitRegiment(g, w, 'pikemen')).toBeNull();
    const a = raiseArmy(g, w)!;
    expect(a.regiments?.length).toBe(cap);
    const men = a.regiments!.reduce((s, r) => s + r.size, 0);
    expect(a.size).toBeGreaterThanOrEqual(men);
    expect(armyRegimentBonus(g, a)).toBeGreaterThan(0);
    // против рыцарей пикинёры не теряют силу, а рыцари против пикинёров — теряют
    const knights = { id: 'x', owner: 'harold', size: 500, maxSize: 500, location: a.location, path: [], progress: 0, regiments: [{ id: 'r', type: 'heavy_cavalry', size: 500 }] };
    const plain = armyRegimentBonus(g, knights as any, []);
    const vsPikes = armyRegimentBonus(g, knights as any, [a]);
    expect(vsPikes).toBeLessThan(plain);
    a.regiments![0].size = 10;
    disbandArmy(g, a.id);
    expect(w.regiments![0].size).toBe(10);
  });
});

describe('отключение механик', () => {
  it('defines.disabled_features отключает механику целиком', async () => {
    const mod = memoryMod({ id: 'no_council', dependencies: ['core'] }, { 'data/defines.yaml': 'defines:\n  disabled_features: [council, factions]\n' });
    const e = await EngineClass.create([...(await loadNodeModPackages('mods')).filter((p) => p.manifest.id === 'core'), mod], {});
    expect(e.systems.has('council')).toBe(false);
    expect(e.systems.has('factions')).toBe(false);
    expect(e.systems.has('lifestyles')).toBe(true);
    const g = e.newGame('b1066', 3);
    for (let i = 0; i < 40; i++) g.tick();
    expect(g.char('harold')!.council).toBeUndefined();
  });
});

describe('все механики выключены', () => {
  it('игра идёт без ошибок скриптов, данные механик убраны', async () => {
    const mod = memoryMod({ id: 'vanilla_plus', dependencies: ['core'] }, { 'data/defines.yaml': 'defines:\n  disabled_features: [lifestyles, council, prison, factions, regiments]\n' });
    const e = await EngineClass.create([...(await loadNodeModPackages('mods')).filter((p) => p.manifest.id === 'core'), mod], {});
    expect(e.issues.filter((i) => i.level === 'error' || /нет поставщика|неизвестный/.test(i.message))).toEqual([]);
    expect(e.content.get('interactions', 'imprison')).toBeUndefined();
    expect(e.content.get('casus_belli', 'independence_revolt')).toBeUndefined();
    // словарь скриптов механик остаётся: триггеры работают на пустом состоянии
    expect(e.script.triggers.has('is_imprisoned')).toBe(true);
    const g = e.newGame('b1066', 5);
    for (let i = 0; i < 365 * 2; i++) g.tick();
    expect(e.issues.filter((i) => i.message.startsWith('Скрипт'))).toEqual([]);
    expect(Object.keys(g.state.factions)).toEqual([]);
    expect(g.living().some((c) => c.regiments?.length || c.lifestyle?.focus || c.council)).toBe(false);
  });
});

describe('секреты и крюки', () => {
  it('секрет узнают, шантажом получают крюк, крюк заставляет согласиться', async () => {
    const { addSecret, learnSecret, knownSecretsOf, exposeSecret } = await import('../src/engine/features/secrets');
    const { executeInteraction, acceptance } = await import('../src/engine/world/interactions');
    const { hookOn } = await import('../src/engine/world/hooks');
    const g = newGame();
    const w = g.char('william')!;
    const h = g.char('harold')!;
    const s = addSecret(g, h, 'secret_murder', 'tostig')!;
    expect(s).toBeTruthy();
    learnSecret(g, w, h, s);
    expect(knownSecretsOf(g, h, w.id)).toHaveLength(1);
    const bm = g.content.get('interactions', 'blackmail')!;
    expect(executeInteraction(g, bm as any, w, h)).toBe('accepted');
    expect(hookOn(g, w, h.id)?.strong).toBe(true);
    // крюк делает несогласного согласным
    const vas = g.content.get('interactions', 'offer_vassalization')! as any;
    const plain = acceptance(g, vas, w, h);
    const forced = acceptance(g, vas, w, h, { useHook: true });
    expect(forced.auto).toBe(true);
    expect(plain.auto).toBe(false);
    // разоблачение убирает секрет и даёт сюзерену повод (у Гарольда сюзерена нет — просто престиж)
    const before = h.prestige;
    expect(exposeSecret(g, w, h)).toBe(true);
    expect(h.secrets).toHaveLength(0);
    expect(h.prestige).toBeLessThan(before);
  });

  it('сильный крюк сюзерена не даёт вассалу вступить во фракцию', async () => {
    const { addHook } = await import('../src/engine/world/hooks');
    const { canJoinFaction } = await import('../src/engine/features/factions');
    const g = newGame();
    const h = g.char('harold')!;
    const v = g.vassalsOf(h.id)[0];
    const def = g.content.get('factions', 'independence_faction') as any;
    expect(canJoinFaction(g, v, def, h)).toBe(true);
    addHook(g, h, v, { strong: true });
    expect(canJoinFaction(g, v, def, h)).toBe(false);
  });
});

describe('законы державы', () => {
  it('власть короны меняет налоги вассалов и право отзыва титулов', async () => {
    const { changeLaw, currentLaw, lawChangeBlockers } = await import('../src/engine/features/laws');
    const { incomeBreakdown } = await import('../src/engine/world/economy');
    const { interactionBlockers } = await import('../src/engine/world/interactions');
    const g = newGame();
    const h = g.char('harold')!;
    expect(currentLaw(g, h, 'crown_authority')?.id).toBe('crown_authority_1');
    const vassalTax = () => incomeBreakdown(g, h).find((p) => p.label === g.loc.t('ui.vassal_tax'))?.value ?? 0;
    const before = vassalTax();
    h.prestige = 5000;
    // через ступень нельзя
    expect(lawChangeBlockers(g, h, g.content.get('realm_laws', 'crown_authority_3') as any).length).toBeGreaterThan(0);
    expect(changeLaw(g, h, 'crown_authority_0')).toBe(true);
    g.statCache.clear();
    expect(vassalTax()).toBeLessThan(before);
    // на автономии вассалов отзывать титулы без повода нельзя
    const v = g.vassalsOf(h.id)[0];
    const revoke = g.content.get('interactions', 'revoke_title') as any;
    expect(interactionBlockers(g, revoke, h, v).length).toBeGreaterThan(0);
    // перерыв между сменами
    expect(changeLaw(g, h, 'crown_authority_1')).toBe(false);
  });
});

describe('рыцари', () => {
  it('доблестные придворные усиливают главную армию', async () => {
    const { knightsOf, knightsPower } = await import('../src/engine/features/knights');
    const { armyStrength } = await import('../src/engine/world/military');
    const g = newGame();
    const h = g.char('harold')!;
    const ks = knightsOf(g, h);
    expect(ks.length).toBeGreaterThan(0);
    expect(knightsPower(g, h)).toBeGreaterThan(0);
    const a = raiseArmy(g, h)!;
    const regs = (a.regiments ?? []).reduce((s, r) => s + r.size, 0);
    expect(armyStrength(g, a)).toBeGreaterThan(a.size - regs + knightsPower(g, h) - 1);
  });
});
