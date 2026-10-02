/**
 * Совет правителя: должности (канцлер, казначей, маршал, тайный советник,
 * духовник), у каждой — набор задач. Задача даёт сюзерену модификаторы,
 * зависящие от навыка советника, и может каждый месяц с некоторым шансом
 * запускать эффект (например, развить провинцию или раскрыть заговор).
 *
 * Данные:
 *   council_positions: { skill, icon, order, is_shown, candidate }
 *   council_tasks:     { position, icon, default, liege_modifiers, monthly_chance, monthly_effect, ai_will_do }
 *   defines.council:   { councillor_opinion, ai_replace_skill_gap, dismiss_opinion_modifier }
 * Скоупы задач: root = scope:councillor, scope:liege.
 */
import type { TextValue } from '../core/localization';
import type { Engine } from '../engine';
import type { Game } from '../game';
import { makeContext } from '../script/context';
import { evalTrigger, evalValue, resolveScope, runEffect } from '../script/interpreter';
import { dateParts } from '../core/date';
import type { Character, CouncilSeat, ScopeRef } from '../types';
import { isAdult, isAlive } from '../world/characters';
import { addOpinion } from '../world/opinion';
import { skill } from '../world/stats';
import { realmCounties } from '../world/titles';
import { type EngineFeature, evalModifiers } from './feature';

export interface CouncilPositionDef {
  id: string;
  name?: TextValue;
  skill: string;
  icon?: string;
  order?: number;
  is_shown?: unknown;
  candidate?: unknown;
}

export interface CouncilTaskDef {
  id: string;
  name?: TextValue;
  position: string;
  icon?: string;
  default?: boolean;
  liege_modifiers?: Record<string, unknown>;
  monthly_chance?: unknown;
  monthly_effect?: unknown;
  ai_will_do?: unknown;
}

function defs(game: Game) {
  return game.defines.council ?? {};
}

export function councilPositions(game: Game): CouncilPositionDef[] {
  return game.content.all<CouncilPositionDef>('council_positions').sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
}

export function tasksOf(game: Game, position: string): CouncilTaskDef[] {
  return game.content.all<CouncilTaskDef>('council_tasks').filter((t) => t.position === position);
}

export function defaultTask(game: Game, position: string): string | undefined {
  const tasks = tasksOf(game, position);
  return (tasks.find((t) => t.default) ?? tasks[0])?.id;
}

export function isPositionShown(game: Game, liege: Character, pos: CouncilPositionDef): boolean {
  if (!liege.titles.length) return false;
  const ctx = makeContext(game, { type: 'character', id: liege.id }, { liege: { type: 'character', id: liege.id } });
  return evalTrigger(ctx, ctx.root, pos.is_shown);
}

export function seatOf(liege: Character, pos: string): CouncilSeat | undefined {
  return liege.council?.[pos];
}

/** Должность персонажа в совете сюзерена (если есть). */
export function councilPositionOf(game: Game, c: Character): { liege: Character; position: string } | null {
  const l = game.char(c.liege);
  if (!l?.council) return null;
  for (const [pos, seat] of Object.entries(l.council)) if (seat.holder === c.id) return { liege: l, position: pos };
  // супруг правителя может заседать и не будучи его придворным
  for (const s of c.spouses) {
    const sp = game.char(s);
    for (const [pos, seat] of Object.entries(sp?.council ?? {})) if (seat.holder === c.id) return { liege: sp!, position: pos };
  }
  return null;
}

/** Может ли персонаж занять должность в совете сюзерена. */
export function canHoldSeat(game: Game, liege: Character, cand: Character, posId: string): boolean {
  const pos = game.content.get<CouncilPositionDef>('council_positions', posId);
  if (!pos || !isAlive(cand) || cand.id === liege.id || cand.prison || !isAdult(game, cand)) return false;
  const belongs = cand.liege === liege.id || liege.spouses.includes(cand.id);
  if (!belongs) return false;
  for (const [p, seat] of Object.entries(liege.council ?? {})) if (p !== posId && seat.holder === cand.id) return false;
  const ctx = makeContext(game, { type: 'character', id: cand.id }, { liege: { type: 'character', id: liege.id }, councillor: { type: 'character', id: cand.id } });
  return evalTrigger(ctx, ctx.root, pos.candidate);
}

export function councilCandidates(game: Game, liege: Character, posId: string): Character[] {
  const pos = game.content.get<CouncilPositionDef>('council_positions', posId);
  if (!pos) return [];
  const pool = new Map<string, Character>();
  for (const c of [...game.courtiersOf(liege.id), ...game.vassalsOf(liege.id)]) pool.set(c.id, c);
  for (const s of liege.spouses) {
    const sp = game.char(s);
    if (sp) pool.set(sp.id, sp);
  }
  return [...pool.values()].filter((c) => canHoldSeat(game, liege, c, posId)).sort((a, b) => skill(game, b, pos.skill) - skill(game, a, pos.skill));
}

export function appointCouncillor(game: Game, liege: Character, posId: string, candId: string): boolean {
  const cand = game.char(candId);
  if (!cand || !canHoldSeat(game, liege, cand, posId)) return false;
  liege.council ??= {};
  const prev = liege.council[posId];
  if (prev?.holder === candId) return false;
  if (prev?.holder) dismissCouncillor(game, liege, posId, true);
  liege.council[posId] = { holder: candId, task: prev?.task ?? defaultTask(game, posId), since: game.date };
  invalidate(game, liege);
  game.emit('council.appointed', { liege, position: posId, councillor: cand });
  return true;
}

/** Снять советника. quiet — без обиды (замена при назначении другого — обида всё равно есть). */
export function dismissCouncillor(game: Game, liege: Character, posId: string, replaced = false): void {
  const seat = liege.council?.[posId];
  if (!seat?.holder) return;
  const c = game.char(seat.holder);
  seat.holder = undefined;
  seat.since = undefined;
  const mod = defs(game).dismiss_opinion_modifier ?? 'dismissed_from_council';
  if (c && isAlive(c) && game.content.get('opinion_modifiers', mod)) addOpinion(game, c, liege, mod);
  invalidate(game, liege);
  game.emit('council.dismissed', { liege, position: posId, councillor: c, replaced });
}

export function setCouncilTask(game: Game, liege: Character, posId: string, task: string): boolean {
  const t = game.content.get<CouncilTaskDef>('council_tasks', task);
  if (!t || t.position !== posId) return false;
  liege.council ??= {};
  liege.council[posId] ??= {};
  liege.council[posId].task = task;
  invalidate(game, liege);
  return true;
}

function invalidate(game: Game, liege: Character) {
  game.monthCache.delete(`council:${liege.id}`);
  game.statCache.delete(liege.id);
  for (const k of game.statCache.keys()) if (k.startsWith('op:')) game.statCache.delete(k);
}

function seatContext(game: Game, liege: Character, holder: string) {
  return makeContext(game, { type: 'character', id: holder }, { liege: { type: 'character', id: liege.id }, councillor: { type: 'character', id: holder } });
}

/** Модификаторы, которые совет даёт сюзерену (по должностям). */
export function councilModifiers(game: Game, liege: Character): { label: string; modifiers: Record<string, number> }[] {
  const out: { label: string; modifiers: Record<string, number> }[] = [];
  for (const [posId, seat] of Object.entries(liege.council ?? {})) {
    if (!seat.holder || !seat.task || !game.isAlive(seat.holder)) continue;
    const t = game.content.get<CouncilTaskDef>('council_tasks', seat.task);
    if (!t?.liege_modifiers) continue;
    const ctx = seatContext(game, liege, seat.holder);
    const modifiers = evalModifiers(ctx, ctx.root, t.liege_modifiers);
    out.push({ label: `${game.nameOf('council_positions', posId)}: ${game.nameOf('council_tasks', t.id)}`, modifiers });
  }
  return out;
}

/** Шанс (в %) ежемесячного эффекта задачи. */
export function taskMonthlyChance(game: Game, liege: Character, posId: string): number {
  const seat = liege.council?.[posId];
  if (!seat?.holder || !seat.task) return 0;
  const t = game.content.get<CouncilTaskDef>('council_tasks', seat.task);
  if (!t?.monthly_effect) return 0;
  const ctx = seatContext(game, liege, seat.holder);
  return Math.max(0, Math.min(100, evalValue(ctx, ctx.root, t.monthly_chance ?? 100)));
}

function aiPickTask(game: Game, liege: Character, posId: string): string | undefined {
  let best: { id: string; v: number } | undefined;
  const ctx = makeContext(game, { type: 'character', id: liege.id }, { liege: { type: 'character', id: liege.id } });
  for (const t of tasksOf(game, posId)) {
    const v = t.ai_will_do != null ? evalValue(ctx, ctx.root, t.ai_will_do) : t.default ? 10 : 5;
    if (!best || v > best.v) best = { id: t.id, v };
  }
  return best?.id;
}

/** ИИ (и первичное заполнение для всех) — занять пустые места лучшими кандидатами. */
export function fillCouncil(game: Game, liege: Character, replace = false): void {
  const gap = defs(game).ai_replace_skill_gap ?? 4;
  for (const pos of councilPositions(game)) {
    if (!isPositionShown(game, liege, pos)) continue;
    const seat = liege.council?.[pos.id];
    const cur = game.char(seat?.holder);
    if (cur && !replace) continue;
    const best = councilCandidates(game, liege, pos.id).find((c) => c.id !== cur?.id);
    if (!best) continue;
    if (cur && skill(game, best, pos.skill) < skill(game, cur, pos.skill) + gap) continue;
    appointCouncillor(game, liege, pos.id, best.id);
  }
}

export function monthlyCouncil(game: Game): void {
  for (const liege of game.rulers()) {
    if (liege.death !== undefined) continue;
    // проверка мест
    for (const [posId, seat] of Object.entries(liege.council ?? {})) {
      if (!seat.holder) continue;
      const c = game.char(seat.holder);
      if (!c || !canHoldSeat(game, liege, c, posId)) {
        seat.holder = undefined;
        seat.since = undefined;
        invalidate(game, liege);
      }
    }
    const isPlayer = game.isPlayer(liege.id);
    if (liege.flags.council_init === undefined) {
      liege.flags.council_init = 0;
      fillCouncil(game, liege);
    } else if (!isPlayer && !liege.prison) {
      fillCouncil(game, liege, dateParts(game.date).m === 1);
      for (const pos of councilPositions(game)) {
        const seat = liege.council?.[pos.id];
        if (seat?.holder && game.rng.chance(0.1)) {
          const t = aiPickTask(game, liege, pos.id);
          if (t && t !== seat.task) setCouncilTask(game, liege, pos.id, t);
        }
      }
    }
    // ежемесячные эффекты задач
    for (const [posId, seat] of Object.entries(liege.council ?? {})) {
      if (!seat.holder || !seat.task) continue;
      const t = game.content.get<CouncilTaskDef>('council_tasks', seat.task);
      if (!t?.monthly_effect) continue;
      if (game.rng.next() * 100 >= taskMonthlyChance(game, liege, posId)) continue;
      const ctx = seatContext(game, liege, seat.holder);
      runEffect(ctx, ctx.root, t.monthly_effect);
      game.emit('council.task_fired', { liege, position: posId, task: t.id });
    }
  }
}

/** Раскрыть случайную нераскрытую враждебную интригу против персонажа или его близких. */
export function discoverSchemeAgainst(game: Game, c: Character): boolean {
  const protectedIds = new Set([c.id, ...c.spouses, ...c.children]);
  const hidden = Object.values(game.state.schemes).filter(
    (s) => !s.discovered && protectedIds.has(s.target) && game.content.get('schemes', s.type)?.category === 'hostile',
  );
  const s = game.rng.pick(hidden);
  if (!s) return false;
  s.discovered = true;
  const def = game.content.get('schemes', s.type);
  const ctx = makeContext(game, { type: 'character', id: s.owner }, {
    owner: { type: 'character', id: s.owner },
    actor: { type: 'character', id: s.owner },
    target: { type: 'character', id: s.target },
    recipient: { type: 'character', id: s.target },
    scheme: { type: 'scheme', id: s.id },
  });
  runEffect(ctx, ctx.root, def?.on_discovered);
  game.emit('scheme.discovered', { scheme: s });
  return true;
}

export const councilFeature: EngineFeature = {
  id: 'council',
  doc: 'Совет: должности, задачи и их эффекты',
  install(engine: Engine) {
    engine.systems.register('council', { id: 'council', order: 15, onMonth: monthlyCouncil }, 'core/council');
    engine.registries.modifierProviders.register('council', {
      fn: (game, c) => (c.council ? game.cachedMonthly(`council:${c.id}`, () => councilModifiers(game, c)) : null),
    }, 'core/council');
    engine.registries.opinionProviders.register('council', {
      fn: (game, a, b) => {
        const seat = Object.values(b.council ?? {}).some((s) => s.holder === a.id);
        const v = seat ? (defs(game).councillor_opinion ?? 10) : 0;
        return v ? { label: game.loc.t('opinion.on_council'), value: v } : null;
      },
    }, 'core/council');

  },
  script(engine: Engine) {
    const { triggers, effects, values, links, lists } = engine.script;
    const ch = (ctx: any, s: ScopeRef | null | undefined) => (s?.type === 'character' ? (ctx.game as Game).char(s.id) : undefined);
    triggers.register('is_councillor', {
      scopes: ['character'],
      doc: 'Заседает в совете (yes) или на должности: is_councillor: marshal',
      eval: (ctx, s, arg) => {
        const c = ch(ctx, s);
        const pos = c ? councilPositionOf(ctx.game, c) : null;
        if (arg === 'no' || arg === false) return !pos;
        return !!pos && (arg === 'yes' || arg === true || arg == null || pos.position === arg);
      },
      describe: (ctx, _s, arg) => ctx.game.loc.t(arg === 'no' || arg === false ? 'tr.is_councillor.not' : 'tr.is_councillor'),
    }, 'core/council');
    triggers.register('has_council_task', {
      scopes: ['character'],
      doc: 'Сюзерен: на какой-то должности выбрана задача',
      eval: (ctx, s, arg) => Object.values(ch(ctx, s)?.council ?? {}).some((seat) => !!seat.holder && seat.task === arg),
    }, 'core/council');
    values.register('council_size', {
      scopes: ['character'],
      doc: 'Число занятых мест в совете',
      get: (ctx, s) => Object.values(ch(ctx, s)?.council ?? {}).filter((x) => x.holder && ctx.game.isAlive(x.holder)).length,
    }, 'core/council');
    for (const pos of engine.content.all<CouncilPositionDef>('council_positions')) {
      links.register(pos.id, {
        from: ['character'],
        doc: `Советник на должности ${pos.id}`,
        resolve: (ctx, s) => {
          const h = ch(ctx, s)?.council?.[pos.id]?.holder;
          return h && ctx.game.isAlive(h) ? { type: 'character', id: h } : null;
        },
      }, 'core/council');
    }
    lists.register('councillor', {
      from: ['character'],
      doc: 'Члены совета',
      list: (ctx, s) =>
        Object.values(ch(ctx, s)?.council ?? {})
          .map((x) => x.holder)
          .filter((id): id is string => !!id && ctx.game.isAlive(id))
          .map((id) => ({ type: 'character' as const, id })),
    }, 'core/council');
    lists.register('neighboring_county', {
      from: ['character'],
      doc: 'Чужие графства, граничащие с державой',
      list: (ctx, s) => {
        const c = ch(ctx, s);
        if (!c) return [];
        const g = ctx.game;
        const mine = new Set(realmCounties(g, c));
        const out = new Set<string>();
        for (const p of mine) for (const n of g.engine.neighbors(p)) if (!mine.has(n) && g.state.titles[n]?.holder) out.add(n);
        return [...out].map((id) => ({ type: 'title' as const, id }));
      },
    }, 'core/council');
    effects.register('discover_scheme_against', {
      scopes: ['character'],
      doc: 'Раскрыть случайную враждебную интригу против персонажа или его семьи',
      apply: (ctx, s) => {
        const c = ch(ctx, s);
        if (c) discoverSchemeAgainst(ctx.game, c);
      },
      describe: (ctx) => ctx.game.loc.t('fx.discover_scheme_against'),
    }, 'core/council');
    effects.register('appoint_councillor', {
      scopes: ['character'],
      doc: 'Назначить в совет: { position, who }',
      apply: (ctx, s, arg) => {
        const c = ch(ctx, s);
        const who = ctx.game.char(resolveId(ctx, s, arg?.who));
        if (c && who) appointCouncillor(ctx.game, c, String(arg.position), who.id);
      },
    }, 'core/council');

    engine.registries.contentValidators.register('council', (e, v) => {
      for (const p of e.content.all<CouncilPositionDef>('council_positions')) {
        if (!e.content.has('skills', p.skill)) v.issue(`council_positions/${p.id}: нет навыка "${p.skill}"`);
        v.trigger(p.is_shown, `council_positions/${p.id} is_shown`);
        v.trigger(p.candidate, `council_positions/${p.id} candidate`);
      }
      for (const t of e.content.all<CouncilTaskDef>('council_tasks')) {
        v.ref('council_positions', t.position, `council_tasks/${t.id}`);
        v.effect(t.monthly_effect, `council_tasks/${t.id} monthly_effect`);
      }
    }, 'core/council');
  },
};

function resolveId(ctx: any, s: ScopeRef, path: unknown): string | undefined {
  const r = resolveScope(ctx, s, path);
  return r?.type === 'character' ? r.id : undefined;
}
