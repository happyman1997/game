/**
 * Профессиональные войска (men-at-arms). Правитель нанимает отряды разных
 * типов за золото и платит за них жалованье; поднятая армия берёт отряды с
 * собой. Каждый воин отряда стоит power ополченцев, типы контрят друг друга
 * (пикинёры — конницу, конница — лучников…), местность усиливает или
 * ослабляет отряды.
 *
 * Данные:
 *   regiment_types: { icon, size, power, cost, upkeep, counters, terrain, can_recruit, ai_will_do, order }
 *   defines.regiments: { cap_by_tier, raised_upkeep_mult, reinforce_rate, max_counter,
 *                        start_regiments_by_tier, ai_gold_reserve }
 */
import type { TextValue } from '../core/localization';
import type { Engine } from '../engine';
import type { Game } from '../game';
import { makeContext } from '../script/context';
import { evalTrigger, evalValue, failedTriggers } from '../script/interpreter';
import type { Army, Character, Regiment } from '../types';
import { costBlockers, monthlyIncome } from '../world/economy';
import { stat } from '../world/stats';
import { primaryTier } from '../world/titles';
import type { EngineFeature } from './feature';

export interface RegimentTypeDef {
  id: string;
  name?: TextValue;
  icon?: string;
  order?: number;
  size: number;
  power: number;
  cost?: { gold?: unknown; prestige?: unknown };
  upkeep: number;
  counters?: Record<string, number>;
  terrain?: Record<string, number>;
  can_recruit?: unknown;
  ai_will_do?: unknown;
}

function defs(game: Game) {
  return game.defines.regiments ?? {};
}

export function regimentTypes(game: Game): RegimentTypeDef[] {
  return game.content.all<RegimentTypeDef>('regiment_types').sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
}

export function regimentCap(game: Game, c: Character): number {
  const byTier: number[] = defs(game).cap_by_tier ?? [0, 2, 3, 4, 6];
  return Math.max(0, Math.floor((byTier[primaryTier(game, c)] ?? 0) + stat(game, c, 'regiment_cap')));
}

export function regimentCost(game: Game, c: Character, def: RegimentTypeDef): { gold: number; prestige: number } {
  const ctx = makeContext(game, { type: 'character', id: c.id });
  return {
    gold: Math.round(evalValue(ctx, ctx.root, def.cost?.gold ?? 0)),
    prestige: Math.round(evalValue(ctx, ctx.root, def.cost?.prestige ?? 0)),
  };
}

export function regimentUpkeep(game: Game, c: Character): number {
  const mult = defs(game).raised_upkeep_mult ?? 2;
  let sum = 0;
  for (const r of c.regiments ?? []) {
    const def = game.content.get<RegimentTypeDef>('regiment_types', r.type);
    if (!def) continue;
    const raised = Object.values(game.state.armies).some((a) => a.owner === c.id && a.regiments?.some((x) => x.id === r.id));
    sum += def.upkeep * (raised ? mult : 1);
  }
  return sum * Math.max(0, 1 + stat(game, c, 'army_upkeep_mult'));
}

export function isTypeShown(game: Game, c: Character, def: RegimentTypeDef): boolean {
  const ctx = makeContext(game, { type: 'character', id: c.id });
  return evalTrigger(ctx, ctx.root, def.can_recruit);
}

export function recruitBlockers(game: Game, c: Character, def: RegimentTypeDef): string[] {
  const out: string[] = [];
  if (!c.titles.length) out.push(game.loc.t('tr.is_ruler'));
  const ctx = makeContext(game, { type: 'character', id: c.id });
  out.push(...failedTriggers(ctx, ctx.root, def.can_recruit));
  if ((c.regiments?.length ?? 0) >= regimentCap(game, c)) out.push(game.loc.t('ui.regiment_cap_reached', { n: regimentCap(game, c) }));
  out.push(...costBlockers(game, c, regimentCost(game, c, def)));
  return out;
}

export function recruitRegiment(game: Game, c: Character, type: string, free = false): Regiment | null {
  const def = game.content.get<RegimentTypeDef>('regiment_types', type);
  if (!def) return null;
  if (!free && recruitBlockers(game, c, def).length) return null;
  if (!free) {
    const cost = regimentCost(game, c, def);
    c.gold -= cost.gold;
    c.prestige -= cost.prestige;
  }
  const r: Regiment = { id: game.newId('reg'), type, size: def.size };
  (c.regiments ??= []).push(r);
  game.emit('regiment.recruited', { character: c, regiment: r });
  game.notify('army');
  return r;
}

export function disbandRegiment(game: Game, c: Character, id: string): void {
  if (!c.regiments) return;
  c.regiments = c.regiments.filter((r) => r.id !== id);
  for (const a of Object.values(game.state.armies)) {
    if (a.owner !== c.id || !a.regiments) continue;
    const r = a.regiments.find((x) => x.id === id);
    if (!r) continue;
    a.size = Math.max(0, a.size - r.size);
    a.maxSize = Math.max(a.size, a.maxSize - r.size);
    a.regiments = a.regiments.filter((x) => x.id !== id);
  }
  game.notify('army');
}

/** Сила полка с учётом контр противника и местности (в «ополченцах»). */
export function regimentEffective(game: Game, r: Regiment, enemyMen: Map<string, number>, myMenOfType: number, terrain?: string): number {
  const def = game.content.get<RegimentTypeDef>('regiment_types', r.type);
  if (!def) return r.size;
  let penalty = 0;
  for (const [type, men] of enemyMen) {
    const edef = game.content.get<RegimentTypeDef>('regiment_types', type);
    const c = edef?.counters?.[r.type] ?? 0;
    if (c) penalty += c * Math.min(1, men / Math.max(1, myMenOfType));
  }
  penalty = Math.min(defs(game).max_counter ?? 0.75, penalty);
  const t = 1 + (terrain ? (def.terrain?.[terrain] ?? 0) : 0);
  return r.size * def.power * (1 - penalty) * Math.max(0.1, t);
}

/** Прибавка к силе армии от отрядов (сверх их численности). */
export function armyRegimentBonus(game: Game, a: Army, enemies: Army[] = [], location?: string): number {
  if (!a.regiments?.length) return 0;
  const enemyMen = new Map<string, number>();
  for (const e of enemies) for (const r of e.regiments ?? []) enemyMen.set(r.type, (enemyMen.get(r.type) ?? 0) + r.size);
  const mine = new Map<string, number>();
  for (const r of a.regiments) mine.set(r.type, (mine.get(r.type) ?? 0) + r.size);
  const terrain = game.content.get('provinces', location ?? a.location)?.terrain;
  let bonus = 0;
  for (const r of a.regiments) bonus += regimentEffective(game, r, enemyMen, mine.get(r.type) ?? r.size, terrain) - r.size;
  return bonus;
}

/** Сила отрядов, не поднятых в армию (для оценок ИИ). */
export function idleRegimentPower(game: Game, c: Character): number {
  const raised = new Set<string>();
  for (const a of Object.values(game.state.armies)) if (a.owner === c.id) for (const r of a.regiments ?? []) raised.add(r.id);
  let sum = 0;
  for (const r of c.regiments ?? []) {
    if (raised.has(r.id)) continue;
    sum += r.size * (game.content.get<RegimentTypeDef>('regiment_types', r.type)?.power ?? 1);
  }
  return sum;
}

function aiPickType(game: Game, c: Character): RegimentTypeDef | undefined {
  const ctx = makeContext(game, { type: 'character', id: c.id });
  const opts = regimentTypes(game)
    .filter((d) => !recruitBlockers(game, c, d).length)
    .map((d) => ({ d, w: Math.max(0, d.ai_will_do != null ? evalValue(ctx, ctx.root, d.ai_will_do) : 10) }))
    .filter((o) => o.w > 0);
  return game.rng.weighted(opts, (o) => o.w)?.d;
}

export function monthlyRegiments(game: Game): void {
  const d = defs(game);
  const rate = d.reinforce_rate ?? 0.1;
  const inArmy = new Set<string>();
  for (const a of Object.values(game.state.armies)) for (const r of a.regiments ?? []) inArmy.add(r.id);
  for (const c of game.rulers()) {
    if (c.death !== undefined) continue;
    // пополнение
    for (const r of c.regiments ?? []) {
      if (inArmy.has(r.id)) continue;
      const max = game.content.get<RegimentTypeDef>('regiment_types', r.type)?.size ?? r.size;
      if (r.size < max) r.size = Math.min(max, Math.round(r.size + max * rate));
    }
    // лишние отряды (например, после потери титулов) распускаются
    const cap = regimentCap(game, c);
    while ((c.regiments?.length ?? 0) > cap) {
      const r = c.regiments!.find((x) => !inArmy.has(x.id)) ?? c.regiments![c.regiments!.length - 1];
      disbandRegiment(game, c, r.id);
    }
    if (game.isPlayer(c.id) || c.prison) continue;
    // ИИ: нанять или распустить
    if (c.gold < (d.ai_disband_below_gold ?? -30) && c.regiments?.length) {
      const r = c.regiments.find((x) => !inArmy.has(x.id));
      if (r) disbandRegiment(game, c, r.id);
      continue;
    }
    if ((c.regiments?.length ?? 0) >= cap || !game.rng.chance(d.ai_recruit_chance ?? 0.15)) continue;
    const pick = aiPickType(game, c);
    if (!pick) continue;
    const cost = regimentCost(game, c, pick).gold;
    if (c.gold < cost + (d.ai_gold_reserve ?? 60)) continue;
    if (monthlyIncome(game, c) < pick.upkeep * 1.5) continue;
    recruitRegiment(game, c, pick.id);
  }
}

function syncFromArmy(game: Game, a: Army) {
  const owner = game.char(a.owner);
  if (!owner?.regiments || !a.regiments) return;
  for (const r of a.regiments) {
    const own = owner.regiments.find((x) => x.id === r.id);
    if (own) own.size = Math.max(0, Math.round(r.size));
  }
}

export const regimentsFeature: EngineFeature = {
  id: 'regiments',
  doc: 'Профессиональные войска: найм, жалованье, контры и местность в бою',
  install(engine: Engine) {
    engine.systems.register('regiments', { id: 'regiments', order: 52, onMonth: monthlyRegiments }, 'core/regiments');

    // Жалованье — строка в доходах.
    engine.hooks.on('economy.income', ({ game, character }) => {
      const v = regimentUpkeep(game, character);
      return v ? { label: game.loc.t('ui.regiment_upkeep'), value: -v } : undefined;
    }, { owner: 'core/regiments' });
    // Поднятая армия забирает отряды.
    engine.hooks.on('army.raised', ({ game, army }: { game: Game; army: Army }) => {
      const owner = game.char(army.owner);
      const regs = (owner?.regiments ?? []).filter((r) => r.size > 0 && !Object.values(game.state.armies).some((a) => a.id !== army.id && a.regiments?.some((x) => x.id === r.id)));
      if (!regs.length) return;
      army.regiments = regs.map((r) => ({ ...r }));
      const men = regs.reduce((s, r) => s + r.size, 0);
      army.size += men;
      army.maxSize += men;
    }, { owner: 'core/regiments' });
    // Распущенная армия возвращает отряды (с потерями).
    engine.hooks.on('army.disbanded', ({ game, army }) => syncFromArmy(game, army), { owner: 'core/regiments' });
    // После сражения (до отступления и гибели армий) переносим потери в отряды правителей.
    engine.hooks.on('battle', ({ game }) => {
      for (const a of Object.values(game.state.armies) as Army[]) syncFromArmy(game, a);
    }, { owner: 'core/regiments', priority: -10 });
    // Сила в бою и в оценках ИИ.
    engine.hooks.on('army.power_bonus', ({ game, army, enemies, location }) => armyRegimentBonus(game, army, enemies ?? [], location), { owner: 'core/regiments' });
    engine.hooks.on('military.strength_bonus', ({ game, character }) => idleRegimentPower(game, character), { owner: 'core/regiments' });
    // Отряды переходят к основному наследнику.
    engine.hooks.on('succession', ({ game, deceased, primary }) => {
      const h = game.char(primary);
      if (!h || !deceased.regiments?.length || h.id === deceased.id) return;
      h.regiments = [...(h.regiments ?? []), ...deceased.regiments];
      deceased.regiments = [];
    }, { owner: 'core/regiments' });
    // Стартовые отряды правителей.
    engine.hooks.on('game.setup', ({ game }) => {
      const byTier: number[] = defs(game).start_regiments_by_tier ?? [0, 0, 1, 2, 3];
      for (const c of game.rulers()) {
        const n = byTier[primaryTier(game, c)] ?? 0;
        for (let i = 0; i < n; i++) {
          const pick = aiPickType(game, { ...c, gold: 1e9 } as Character);
          if (pick) recruitRegiment(game, c, pick.id, true);
        }
      }
    }, { owner: 'core/regiments' });

  },
  script(engine: Engine) {
    const { triggers, effects, values } = engine.script;
    const ch = (ctx: any, s: any) => (s?.type === 'character' ? (ctx.game as Game).char(s.id) : undefined);
    triggers.register('has_regiment', {
      scopes: ['character'],
      doc: 'Есть отряд этого типа (или любой: yes)',
      eval: (ctx, s, arg) => {
        const regs = ch(ctx, s)?.regiments ?? [];
        return arg === 'yes' || arg === true ? regs.length > 0 : regs.some((r) => r.type === arg);
      },
    }, 'core/regiments');
    values.register('num_regiments', { scopes: ['character'], doc: 'Число отрядов', get: (ctx, s) => ch(ctx, s)?.regiments?.length ?? 0 }, 'core/regiments');
    values.register('regiment_cap', { scopes: ['character'], doc: 'Предел отрядов', get: (ctx, s) => { const c = ch(ctx, s); return c ? regimentCap(ctx.game, c) : 0; } }, 'core/regiments');
    values.register('regiment_power', { scopes: ['character'], doc: 'Сила отрядов, не поднятых в армию (в ополченцах)', get: (ctx, s) => { const c = ch(ctx, s); return c ? idleRegimentPower(ctx.game, c) : 0; } }, 'core/regiments');
    effects.register('add_regiment', {
      scopes: ['character'],
      doc: 'Получить отряд бесплатно (сверх предела)',
      apply: (ctx, s, arg) => { const c = ch(ctx, s); if (c) recruitRegiment(ctx.game, c, String(arg), true); },
      describe: (ctx, _s, arg) => ctx.game.loc.t('fx.add_regiment', { value: ctx.game.nameOf('regiment_types', String(arg)) }),
    }, 'core/regiments');

    engine.registries.contentValidators.register('regiments', (e, v) => {
      for (const d of e.content.all<RegimentTypeDef>('regiment_types')) {
        const w = `regiment_types/${d.id}`;
        if (!(d.size > 0) || !(d.power > 0)) v.issue(`${w}: нужны size > 0 и power > 0`);
        for (const t of Object.keys(d.counters ?? {})) v.ref('regiment_types', t, `${w} counters`);
        for (const t of Object.keys(d.terrain ?? {})) v.ref('terrain', t, `${w} terrain`);
        v.trigger(d.can_recruit, `${w} can_recruit`);
      }
    }, 'core/regiments');
  },
};
