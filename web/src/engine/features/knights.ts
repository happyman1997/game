/**
 * Рыцари. Самые доблестные придворные и вассалы правителя (проходящие
 * scripted_trigger knight_candidate) сопровождают его главную армию: каждый
 * очко доблести стоит power_per_prowess ополченцев. В сражениях рыцари
 * получают раны и гибнут.
 *
 *   defines.knights: { cap_by_tier, power_per_prowess, loser_death_chance,
 *                      loser_wound_chance, winner_death_chance, winner_wound_chance,
 *                      wound_trait, prestige_per_battle }
 */
import type { Engine } from '../engine';
import type { Game } from '../game';
import { type ScriptContext, makeContext } from '../script/context';
import { evalTrigger } from '../script/interpreter';
import type { Army, Character, ScopeRef } from '../types';
import { addTrait, isAlive } from '../world/characters';
import { skill, stat } from '../world/stats';
import { primaryTier } from '../world/titles';
import { killCharacter } from '../world/succession';
import type { EngineFeature } from './feature';

function defs(game: Game) {
  return game.defines.knights ?? {};
}

export function knightCap(game: Game, c: Character): number {
  const byTier: number[] = defs(game).cap_by_tier ?? [0, 3, 5, 8, 12];
  return Math.max(0, Math.floor((byTier[primaryTier(game, c)] ?? 0) + stat(game, c, 'knight_cap')));
}

export function isKnightCandidate(game: Game, liege: Character, c: Character): boolean {
  if (!isAlive(c) || c.prison || c.id === liege.id) return false;
  const st = game.content.get('scripted_triggers', 'knight_candidate');
  const ctx = makeContext(game, { type: 'character', id: c.id }, { liege: { type: 'character', id: liege.id } });
  return st ? evalTrigger(ctx, ctx.root, 'knight_candidate') : skill(game, c, 'prowess') >= 6;
}

/** Рыцари правителя: лучшие по доблести кандидаты из двора и вассалов (кэш на день). */
export function knightsOf(game: Game, c: Character): Character[] {
  // Состав рыцарей меняется медленно — пересчитываем раз в месяц (и после сражений).
  return game.cachedMonthly(`knights:${c.id}`, () => {
    const pool = [...game.courtiersOf(c.id), ...game.vassalsOf(c.id)].filter((x) => isKnightCandidate(game, c, x));
    pool.sort((a, b) => skill(game, b, 'prowess') - skill(game, a, 'prowess'));
    return pool.slice(0, knightCap(game, c));
  });
}

export function knightsPower(game: Game, c: Character): number {
  return game.cachedMonthly(`kpow:${c.id}`, () => {
    const k = defs(game).power_per_prowess ?? 8;
    return knightsOf(game, c).reduce((s, x) => s + skill(game, x, 'prowess') * k, 0) * Math.max(0, 1 + stat(game, c, 'knight_effectiveness'));
  });
}

/** Главная (самая большая) армия правителя — с ней идут рыцари. */
export function mainArmyOf(game: Game, ownerId: string): Army | undefined {
  let best: Army | undefined;
  for (const a of Object.values(game.state.armies)) if (a.owner === ownerId && (!best || a.size > best.size)) best = a;
  return best;
}

function battleCasualties(game: Game, ownerId: string, won: boolean) {
  const d = defs(game);
  const owner = game.char(ownerId);
  if (!owner) return;
  const death = won ? (d.winner_death_chance ?? 0.01) : (d.loser_death_chance ?? 0.04);
  const wound = won ? (d.winner_wound_chance ?? 0.05) : (d.loser_wound_chance ?? 0.12);
  for (const k of knightsOf(game, owner)) {
    if (k.death !== undefined) continue;
    if (game.rng.chance(death)) {
      killCharacter(game, k, 'battle');
      continue;
    }
    if (game.rng.chance(wound)) addTrait(game, k, d.wound_trait ?? 'wounded');
    else if (won) k.prestige += d.prestige_per_battle ?? 10;
  }
  game.monthCache.delete(`knights:${owner.id}`);
  game.monthCache.delete(`kpow:${owner.id}`);
}

export const knightsFeature: EngineFeature = {
  id: 'knights',
  doc: 'Рыцари: доблестные придворные и вассалы усиливают армию правителя',
  install(engine: Engine) {
    engine.hooks.on('army.power_bonus', ({ game, army }: { game: Game; army: Army }) => {
      if (mainArmyOf(game, army.owner)?.id !== army.id) return undefined;
      const owner = game.char(army.owner);
      return owner ? knightsPower(game, owner) : undefined;
    }, { owner: 'core/knights' });
    engine.hooks.on('military.strength_bonus', ({ game, character }: { game: Game; character: Character }) =>
      mainArmyOf(game, character.id) ? undefined : knightsPower(game, character), { owner: 'core/knights' });
    engine.hooks.on('battle', ({ game, winner, loser }: { game: Game; winner: string; loser: string }) => {
      battleCasualties(game, winner, true);
      battleCasualties(game, loser, false);
    }, { owner: 'core/knights', priority: -20 });
  },
  script(engine: Engine) {
    const { triggers, values, lists } = engine.script;
    const ch = (ctx: ScriptContext, s: ScopeRef | null | undefined) => (s?.type === 'character' ? ctx.game.char(s.id) : undefined);
    triggers.register('is_knight', {
      scopes: ['character'],
      doc: 'Служит рыцарем у своего сюзерена',
      eval: (ctx, s, arg) => {
        const c = ch(ctx, s);
        const l = ctx.game.char(c?.liege);
        const yes = !!c && !!l && ctx.game.engine.hasFeature('knights') && knightsOf(ctx.game, l).some((k) => k.id === c.id);
        return yes === (arg == null || arg === 'yes' || arg === true);
      },
    }, 'core/knights');
    values.register('num_knights', { scopes: ['character'], doc: 'Число рыцарей', get: (ctx, s) => { const c = ch(ctx, s); return c && ctx.game.engine.hasFeature('knights') ? knightsOf(ctx.game, c).length : 0; } }, 'core/knights');
    values.register('knights_power', { scopes: ['character'], doc: 'Сила рыцарей (в ополченцах)', get: (ctx, s) => { const c = ch(ctx, s); return c && ctx.game.engine.hasFeature('knights') ? knightsPower(ctx.game, c) : 0; } }, 'core/knights');
    lists.register('knight', {
      from: ['character'],
      doc: 'Рыцари правителя',
      list: (ctx, s) => {
        const c = ch(ctx, s);
        return c && ctx.game.engine.hasFeature('knights') ? knightsOf(ctx.game, c).map((k) => ({ type: 'character' as const, id: k.id })) : [];
      },
    }, 'core/knights');
  },
};
