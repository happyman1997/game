/**
 * «Механики» — крупные игровые подсистемы (образ жизни, совет, темница,
 * фракции, профессиональные войска). Каждая механика — отдельный модуль,
 * который при установке регистрирует свои системы, скриптовые триггеры и
 * эффекты, поставщики модификаторов и проверки контента — ровно теми же
 * способами, что доступны JS-модам. Механику можно отключить из данных:
 *
 *   defines:
 *     disabled_features: [council]
 *
 * а мод может зарегистрировать свою механику через api.features.add().
 */
import type { ScriptValidator } from '../content/validate';
import { isPlainObject } from '../core/merge';
import type { Engine } from '../engine';
import type { ScriptContext } from '../script/context';
import { evalValue } from '../script/interpreter';
import type { ScopeRef } from '../types';

export interface EngineFeature {
  id: string;
  /** Краткое описание для справочника. */
  doc?: string;
  /**
   * Словарь скриптов механики (триггеры, эффекты, значения, ссылки, списки) и
   * проверки контента. Регистрируется ВСЕГДА — даже если механика отключена,
   * чтобы данные других модов, упоминающие её триггеры, не ломались
   * (на пустом состоянии они просто вернут «нет»/0).
   */
  script?(engine: Engine): void;
  /** Системы, хуки и поставщики модификаторов — только для включённой механики. */
  install(engine: Engine): void;
}

/** Проверка контента механики (вызывается после загрузки модов). */
export type ContentValidator = (engine: Engine, v: ScriptValidator) => void;

/**
 * Модификаторы со скриптовыми значениями:
 *   { tax_mult: { value: stewardship, multiply: 0.01 }, prowess: 2 }
 */
export function evalModifiers(ctx: ScriptContext, scope: ScopeRef, mods: Record<string, unknown> | undefined): Record<string, number> {
  const out: Record<string, number> = {};
  if (!isPlainObject(mods)) return out;
  for (const [k, v] of Object.entries(mods)) {
    const n = typeof v === 'number' ? v : evalValue(ctx, scope, v);
    if (n) out[k] = n;
  }
  return out;
}

export function asList<T>(v: T | T[] | undefined | null): T[] {
  if (v == null) return [];
  return Array.isArray(v) ? v : [v];
}
