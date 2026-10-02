import type { Game } from '../game';
import type { ScopeRef } from '../types';

/**
 * Контекст выполнения скрипта: корневой скоуп (root), сохранённые
 * скоупы (scope:имя), сохранённые значения и предыдущий скоуп (prev).
 */
export interface ScriptContext {
  game: Game;
  root: ScopeRef;
  scopes: Record<string, ScopeRef>;
  values: Record<string, number>;
  prev?: ScopeRef;
  depth: number;
  /** Режим описания: эффекты не применяются. */
  describing?: boolean;
}

export function makeContext(game: Game, root: ScopeRef, scopes: Record<string, ScopeRef> = {}): ScriptContext {
  return { game, root, scopes: { ...scopes }, values: {}, depth: 0 };
}

export function charRef(id: string): ScopeRef {
  return { type: 'character', id };
}
export function titleRef(id: string): ScopeRef {
  return { type: 'title', id };
}
export function provRef(id: string): ScopeRef {
  return { type: 'province', id };
}

export function sameScope(a: ScopeRef | null | undefined, b: ScopeRef | null | undefined): boolean {
  return !!a && !!b && a.type === b.type && a.id === b.id;
}

export function isYes(v: unknown): boolean {
  return v === true || v === 'yes' || v === 1 || v === 'true';
}
