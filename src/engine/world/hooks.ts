/**
 * Крюки (hooks): рычаг давления одного персонажа на другого. Слабый крюк
 * можно использовать один раз, сильный — многократно, с перерывом.
 * Использованный крюк заставляет принять взаимодействие (поле use_hook).
 */
import type { Game } from '../game';
import type { Character, Hook } from '../types';

export function hookOn(game: Game, c: Character, targetId: string): Hook | undefined {
  return c.hooks.find((h) => h.target === targetId && (h.expires === undefined || h.expires > game.date));
}

export function addHook(game: Game, owner: Character, target: Character, opts: { strong?: boolean; days?: number } = {}): void {
  if (owner.id === target.id) return;
  const prev = hookOn(game, owner, target.id);
  // Сильный крюк не заменяется слабым.
  if (prev?.strong && !opts.strong) return;
  owner.hooks = owner.hooks.filter((h) => h.target !== target.id);
  owner.hooks.push({ target: target.id, strong: !!opts.strong, expires: opts.days ? game.date + opts.days : undefined });
  game.emit('hook.added', { owner, target, strong: !!opts.strong });
}

export function removeHook(owner: Character, targetId: string): void {
  owner.hooks = owner.hooks.filter((h) => h.target !== targetId);
}

/** Можно ли сейчас использовать крюк (сильный — не чаще раза в strong_hook_cooldown_years). */
export function canUseHook(game: Game, owner: Character, targetId: string): boolean {
  const h = hookOn(game, owner, targetId);
  if (!h) return false;
  if (!h.strong) return true;
  const cd = owner.flags[`hook_cd:${targetId}`];
  return cd === undefined || cd <= game.date;
}

export function useHook(game: Game, owner: Character, targetId: string): boolean {
  const h = hookOn(game, owner, targetId);
  if (!h || !canUseHook(game, owner, targetId)) return false;
  if (h.strong) owner.flags[`hook_cd:${targetId}`] = game.date + Math.round((game.defines.hooks?.strong_hook_cooldown_years ?? 5) * 365);
  else removeHook(owner, targetId);
  game.emit('hook.used', { owner, target: targetId, strong: !!h.strong });
  return true;
}
