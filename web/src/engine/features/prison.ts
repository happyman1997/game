/**
 * Темница. Персонажа можно заключить (взаимодействием из данных или эффектом
 * imprison), держать, выкупать, отпускать и казнить. Правителей берут в плен
 * при взятии столицы и после проигранных сражений; плен вражеского лидера
 * приносит счёт войны.
 *
 * Заключённый не правит (ИИ не думает), не командует войсками, его интриги
 * стоят. Все действия с пленниками — обычные взаимодействия в данных
 * (imprison, release_prisoner, execute_prisoner, demand_ransom), ИИ выбирает
 * их по ai_will_do, как и любые другие.
 *
 *   defines.prison: { escape_chance, escape_per_intrigue, siege_capture_chance,
 *                     battle_capture_chance, leader_captured_warscore,
 *                     ransom_base, ransom_per_tier, ransom_income_months,
 *                     crime_opinion_modifiers, monthly_stress, dungeon_health }
 */
import type { Engine } from '../engine';
import type { Game } from '../game';
import type { ScriptContext } from '../script/context';
import { resolveScope } from '../script/interpreter';
import type { Character, ScopeRef, War } from '../types';
import { isAdult, isAlive } from '../world/characters';
import { monthlyIncome } from '../world/economy';
import { participantSide } from '../world/war';
import { primaryTier } from '../world/titles';
import type { EngineFeature } from './feature';

function defs(game: Game) {
  return game.defines.prison ?? {};
}

export function isImprisoned(c: Character | undefined): boolean {
  return !!c?.prison;
}

export function prisonersOf(game: Game, id: string): Character[] {
  return game.living().filter((c) => c.prison?.by === id);
}

export function imprison(game: Game, jailer: Character, prisoner: Character, opts: { reason?: string; war?: string } = {}): boolean {
  if (!isAlive(jailer) || !isAlive(prisoner) || prisoner.id === jailer.id || prisoner.prison) return false;
  if (!game.engine.hooks.veto('prison.before_imprison', { game, jailer, prisoner, reason: opts.reason })) return false;
  prisoner.prison = { by: jailer.id, since: game.date, home: prisoner.liege, war: opts.war };
  // Заключённый бросает свои интриги и армии остаются без него.
  for (const a of Object.values(game.state.armies)) if (a.commander === prisoner.id) a.commander = undefined;
  game.statCache.delete(prisoner.id);
  game.markDirty();
  game.message(
    game.loc.t('msg.imprisoned', { who: game.scopeName({ type: 'character', id: prisoner.id }), jailer: game.scopeName({ type: 'character', id: jailer.id }) }),
    'bad',
    { type: 'character', id: prisoner.id },
    [prisoner.id, jailer.id, prisoner.liege],
  );
  game.emit('prison.imprisoned', { jailer, prisoner, reason: opts.reason });
  game.onAction('on_imprisoned', { type: 'character', id: prisoner.id }, { jailer: { type: 'character', id: jailer.id } });
  return true;
}

export function releasePrisoner(game: Game, prisoner: Character, reason = 'released'): void {
  if (!prisoner.prison) return;
  const jailer = prisoner.prison.by;
  prisoner.prison = undefined;
  game.statCache.delete(prisoner.id);
  game.markDirty();
  if (isAlive(prisoner)) {
    game.message(
      game.loc.t(`msg.prison_${reason}`, { who: game.scopeName({ type: 'character', id: prisoner.id }) }),
      'info',
      { type: 'character', id: prisoner.id },
      [prisoner.id, jailer, prisoner.liege],
    );
  }
  game.emit('prison.released', { prisoner, jailer, reason });
  game.onAction('on_released_from_prison', { type: 'character', id: prisoner.id }, { jailer: { type: 'character', id: jailer } });
}

/** Кто платит выкуп: сам правитель-пленник или двор, к которому он принадлежал, или родня-правитель. */
export function ransomPayer(game: Game, prisoner: Character): Character {
  if (prisoner.titles.length) return prisoner;
  const home = game.char(prisoner.prison?.home ?? prisoner.liege);
  if (home && isAlive(home) && home.titles.length && home.id !== prisoner.prison?.by) return home;
  for (const id of [prisoner.father, prisoner.mother, ...prisoner.spouses]) {
    const r = game.char(id);
    if (r && isAlive(r) && r.titles.length && r.id !== prisoner.prison?.by) return r;
  }
  return prisoner;
}

export function ransomCost(game: Game, prisoner: Character): number {
  const d = defs(game);
  const payer = ransomPayer(game, prisoner);
  const income = payer.titles.length ? Math.max(0, monthlyIncome(game, payer)) : 0;
  return Math.round((d.ransom_base ?? 40) + (d.ransom_per_tier ?? 60) * primaryTier(game, prisoner) + income * (d.ransom_income_months ?? 6));
}

/** Есть ли у jailer законный повод заключить target (без тирании). */
export function hasImprisonmentReason(game: Game, jailer: Character, target: Character): boolean {
  const crimes: string[] = defs(game).crime_opinion_modifiers ?? ['attempted_murder', 'murdered_relative', 'rebel'];
  if ((jailer.opinions[target.id] ?? []).some((e) => crimes.includes(e.mod))) return true;
  const flag = target.flags[`criminal:${jailer.id}`];
  if (flag !== undefined && (flag === 0 || flag > game.date)) return true;
  // раскрытая враждебная интрига против jailer или его близких
  const protectedIds = new Set([jailer.id, ...jailer.spouses, ...jailer.children]);
  return Object.values(game.state.schemes).some(
    (s) => s.owner === target.id && s.discovered && protectedIds.has(s.target) && game.content.get('schemes', s.type)?.category === 'hostile',
  );
}

function leaderCaptured(game: Game, w: War, leader: string, captorSide: 'att' | 'def'): boolean {
  const c = game.char(leader);
  if (!c?.prison) return false;
  const captor = c.prison.by;
  return participantSide(w, captor) === captorSide;
}

export function monthlyPrison(game: Game): void {
  const d = defs(game);
  for (const c of game.living()) {
    if (!c.prison) continue;
    const jailer = game.char(c.prison.by);
    if (!isAlive(jailer)) {
      releasePrisoner(game, c, 'jailer_died');
      continue;
    }
    c.stress += d.monthly_stress ?? 2;
    const escape = (d.escape_chance ?? 0.004) + (c.skills.intrigue ?? 0) * (d.escape_per_intrigue ?? 0.0005);
    if (game.rng.chance(escape)) releasePrisoner(game, c, 'escaped');
  }
}

/** Пленение правителей при взятии их столицы. */
function onSiegeWon(game: Game, war: War, army: { owner: string }, province: string) {
  const d = defs(game);
  const captor = game.char(army.owner);
  if (!captor) return;
  const side = participantSide(war, captor.id);
  if (!side) return;
  for (const r of game.rulers()) {
    if (r.capital !== province || r.prison || !isAlive(r)) continue;
    const rs = participantSide(war, r.id);
    if (!rs || rs === side) continue;
    // правитель с поднятой армией находится при войске, а не в замке
    if (Object.values(game.state.armies).some((a) => a.owner === r.id)) continue;
    if (game.rng.chance(d.siege_capture_chance ?? 0.5)) imprison(game, captor, r, { reason: 'siege', war: war.id });
    for (const id of [...r.spouses, ...r.children]) {
      const f = game.char(id);
      if (f && isAlive(f) && !f.prison && !f.titles.length && f.liege === r.id && isAdult(game, f) && game.rng.chance(d.family_capture_chance ?? 0.3)) {
        imprison(game, captor, f, { reason: 'siege', war: war.id });
      }
    }
  }
}

export const prisonFeature: EngineFeature = {
  id: 'prison',
  doc: 'Темница: заключение, выкуп, казнь, плен на войне',
  install(engine: Engine) {
    engine.systems.register('prison', { id: 'prison', order: 22, onMonth: monthlyPrison }, 'core/prison');

    engine.registries.modifierProviders.register('prison', {
      fn: (game, c) => (c.prison ? { health: defs(game).dungeon_health ?? -1, fertility: -0.5 } : null),
    }, 'core/prison');

    engine.hooks.on('siege.won', ({ game, war, army, province }) => onSiegeWon(game, war, army, province), { owner: 'core/prison' });
    engine.hooks.on('battle.commander_survived', ({ game, war, commander, captor }) => {
      const c = game.char(commander);
      const cap = game.char(captor);
      if (c && cap && !c.prison && game.rng.chance(defs(game).battle_capture_chance ?? 0.08)) imprison(game, cap, c, { reason: 'battle', war: war.id });
    }, { owner: 'core/prison' });
    // Пленники умершего тюремщика переходят к его основному наследнику.
    engine.hooks.on('succession', ({ game, deceased, primary }) => {
      for (const c of game.living()) if (c.prison?.by === deceased.id) c.prison.by = primary;
    }, { owner: 'core/prison' });
    engine.hooks.on('character.death', ({ character }) => {
      if (character.prison) character.prison = undefined;
    }, { owner: 'core/prison' });
    // Плен лидера вражеской стороны даёт счёт войны.
    engine.hooks.on('war.score', ({ game, war }) => {
      const v = defs(game).leader_captured_warscore ?? 75;
      const out: { label: string; value: number }[] = [];
      if (leaderCaptured(game, war, war.defender, 'att')) out.push({ label: game.loc.t('ui.ws_captured_leader'), value: v });
      if (leaderCaptured(game, war, war.attacker, 'def')) out.push({ label: game.loc.t('ui.ws_captured_leader'), value: -v });
      return out;
    }, { owner: 'core/prison' });
    // Пленники не правят: ИИ не думает за них.
    engine.hooks.on('ai.think', ({ character }) => (character.prison ? false : undefined), { owner: 'core/prison', priority: 100 });

  },
  script(engine: Engine) {
    const { triggers, effects, values, lists } = engine.script;
    const ch = (ctx: ScriptContext, s: ScopeRef | null | undefined) => (s?.type === 'character' ? ctx.game.char(s.id) : undefined);
    const target = (ctx: ScriptContext, s: ScopeRef, arg: unknown) => ch(ctx, resolveScope(ctx, s, arg));
    triggers.register('is_imprisoned', {
      scopes: ['character'],
      doc: 'В темнице',
      eval: (ctx, s, arg) => !!ch(ctx, s)?.prison === (arg == null || arg === 'yes' || arg === true),
      describe: (ctx, _s, arg) => ctx.game.loc.t(arg == null || arg === 'yes' || arg === true ? 'tr.is_imprisoned' : 'tr.is_imprisoned.not'),
    }, 'core/prison');
    triggers.register('is_imprisoned_by', {
      scopes: ['character'],
      doc: 'В темнице у персонажа',
      eval: (ctx, s, arg) => {
        const c = ch(ctx, s);
        const j = target(ctx, s, arg);
        return !!c?.prison && !!j && c.prison.by === j.id;
      },
      describe: (ctx) => ctx.game.loc.t('tr.is_imprisoned_by'),
    }, 'core/prison');
    triggers.register('has_imprisonment_reason', {
      scopes: ['character'],
      doc: 'Есть законный повод заключить персонажа (преступление против этого персонажа)',
      eval: (ctx, s, arg) => {
        const j = ch(ctx, s);
        const t = target(ctx, s, arg);
        return !!j && !!t && hasImprisonmentReason(ctx.game, j, t);
      },
      describe: (ctx) => ctx.game.loc.t('tr.has_imprisonment_reason'),
    }, 'core/prison');
    values.register('prison_months', {
      scopes: ['character'],
      doc: 'Сколько месяцев персонаж в темнице',
      get: (ctx, s) => {
        const c = ch(ctx, s);
        return c?.prison ? Math.floor((ctx.game.date - c.prison.since) / 30) : 0;
      },
    }, 'core/prison');
    values.register('ransom_cost', {
      scopes: ['character'],
      doc: 'Размер выкупа за пленника',
      get: (ctx, s) => {
        const c = ch(ctx, s);
        return c ? ransomCost(ctx.game, c) : 0;
      },
    }, 'core/prison');
    values.register('num_prisoners', { scopes: ['character'], doc: 'Число пленников', get: (ctx, s) => prisonersOf(ctx.game, s.id).length }, 'core/prison');
    lists.register('prisoner', {
      from: ['character'],
      doc: 'Пленники персонажа',
      list: (ctx, s) => prisonersOf(ctx.game, s.id).map((c) => ({ type: 'character' as const, id: c.id })),
    }, 'core/prison');
    effects.register('imprison', {
      scopes: ['character'],
      doc: 'Заключить персонажа в свою темницу: imprison: scope:x или { target, reason }',
      apply: (ctx, s, arg) => {
        const j = ch(ctx, s);
        const t = target(ctx, s, arg?.target ?? arg);
        if (j && t) imprison(ctx.game, j, t, { reason: arg?.reason });
      },
      describe: (ctx, s, arg) => {
        const t = target(ctx, s, arg?.target ?? arg);
        return t ? ctx.game.loc.t('fx.imprison', { who: ctx.game.scopeName({ type: 'character', id: t.id }) }) : null;
      },
    }, 'core/prison');
    effects.register('release_from_prison', {
      scopes: ['character'],
      doc: 'Освободить этого персонажа из темницы',
      apply: (ctx, s, arg) => {
        const c = ch(ctx, s);
        if (c) releasePrisoner(ctx.game, c, typeof arg === 'string' && arg !== 'yes' ? arg : 'released');
      },
      describe: (ctx, s) => ctx.game.loc.t('fx.release_from_prison', { who: ctx.game.scopeName(s) }),
    }, 'core/prison');
    effects.register('mark_criminal', {
      scopes: ['character'],
      doc: 'Даёт target законный повод заключить этого персонажа: { target, years }',
      apply: (ctx, s, arg) => {
        const c = ch(ctx, s);
        const t = target(ctx, s, arg?.target ?? arg);
        if (!c || !t) return;
        const years = Number(arg?.years ?? 0);
        c.flags[`criminal:${t.id}`] = years ? ctx.game.date + Math.round(years * 365) : 0;
      },
      describe: () => null,
    }, 'core/prison');

    engine.registries.interactionDeciders.register('payer', {
      decider: (game, recipient) => ransomPayer(game, recipient),
    }, 'core/prison');
  },
};
