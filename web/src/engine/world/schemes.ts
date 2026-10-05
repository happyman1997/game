import type { SchemeDef } from '../content/defs';
import type { Game } from '../game';
import { type ScriptContext, makeContext } from '../script/context';
import { evalTrigger, evalValue, runEffect } from '../script/interpreter';
import type { Character, Scheme } from '../types';
import { isAlive } from './characters';

/**
 * Интриги (схемы): длительные действия против цели — убийство,
 * соблазнение, дружба. Прогресс, шанс успеха и раскрытия задаются
 * значениями в данных.
 */
export function schemeContext(game: Game, s: Scheme): ScriptContext {
  return makeContext(
    game,
    { type: 'character', id: s.owner },
    {
      owner: { type: 'character', id: s.owner },
      actor: { type: 'character', id: s.owner },
      target: { type: 'character', id: s.target },
      recipient: { type: 'character', id: s.target },
      scheme: { type: 'scheme', id: s.id },
    },
  );
}

export function startScheme(game: Game, type: string, owner: Character, target: Character): Scheme | null {
  const def = game.content.get<SchemeDef>('schemes', type);
  if (!def) {
    game.scriptError(`Нет интриги "${type}"`);
    return null;
  }
  if (Object.values(game.state.schemes).some((s) => s.owner === owner.id && s.type === type && s.target === target.id)) return null;
  const s: Scheme = { id: game.newId('sch'), type, owner: owner.id, target: target.id, progress: 0, start: game.date, discovered: false };
  const ctx = schemeContext(game, s);
  if (!evalTrigger(ctx, ctx.root, def.is_valid)) return null;
  game.state.schemes[s.id] = s;
  game.emit('scheme.started', { scheme: s });
  return s;
}

export function schemeSuccessChance(game: Game, s: Scheme): number {
  const def = game.content.get<SchemeDef>('schemes', s.type);
  if (!def) return 0;
  const ctx = schemeContext(game, s);
  const cap = game.defines.schemes?.max_success ?? 95;
  return Math.max(0, Math.min(cap, Math.round(evalValue(ctx, ctx.root, def.success_chance))));
}

export function schemeMonthlyProgress(game: Game, s: Scheme): number {
  const def = game.content.get<SchemeDef>('schemes', s.type);
  if (!def) return 0;
  const ctx = schemeContext(game, s);
  return Math.max(1, evalValue(ctx, ctx.root, def.progress));
}

export function endScheme(game: Game, id: string): void {
  delete game.state.schemes[id];
}

export function monthlySchemes(game: Game): void {
  for (const s of Object.values(game.state.schemes)) {
    const def = game.content.get<SchemeDef>('schemes', s.type);
    const owner = game.char(s.owner);
    const target = game.char(s.target);
    if (!def || !isAlive(owner) || !isAlive(target)) {
      endScheme(game, s.id);
      continue;
    }
    const ctx = schemeContext(game, s);
    if (!evalTrigger(ctx, ctx.root, def.is_valid)) {
      endScheme(game, s.id);
      continue;
    }
    if (owner.prison) continue; // в темнице интриги стоят
    s.progress += schemeMonthlyProgress(game, s);
    if (!s.discovered && def.discovery_chance != null && game.rng.next() * 100 < evalValue(ctx, ctx.root, def.discovery_chance)) {
      s.discovered = true;
      runEffect(ctx, ctx.root, def.on_discovered);
      game.emit('scheme.discovered', { scheme: s });
    }
    if (s.progress >= 100) {
      const chance = schemeSuccessChance(game, s);
      const success = game.rng.next() * 100 < chance;
      endScheme(game, s.id);
      runEffect(ctx, ctx.root, success ? def.on_success : def.on_failure);
      game.emit('scheme.ended', { scheme: s, success });
    }
  }
}
