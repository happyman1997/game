import { Registry } from '../core/registry';
import type { ScopeRef, ScopeType } from '../types';
import type { ScriptContext } from './context';

/**
 * Реестры скриптового языка. Встроенные триггеры/эффекты регистрируются
 * так же, как и моддерские — мод может добавить новый или переопределить
 * существующий.
 */
export interface TriggerDef {
  scopes?: ScopeType[];
  doc?: string;
  eval(ctx: ScriptContext, scope: ScopeRef, arg: any): boolean;
  /** Описание для подсказки «почему недоступно». */
  describe?(ctx: ScriptContext, scope: ScopeRef, arg: any): string | null;
}

export interface EffectDef {
  scopes?: ScopeType[];
  doc?: string;
  apply(ctx: ScriptContext, scope: ScopeRef, arg: any): void;
  /** Текст для подсказки. null — не показывать. */
  describe?(ctx: ScriptContext, scope: ScopeRef, arg: any): string | string[] | null;
}

export interface ValueDef {
  scopes?: ScopeType[];
  doc?: string;
  /** arg — необязательный скоуп-аргумент: opinion(scope:actor). */
  get(ctx: ScriptContext, scope: ScopeRef, arg?: ScopeRef | null): number;
}

export interface LinkDef {
  from?: ScopeType[];
  to?: ScopeType;
  doc?: string;
  resolve(ctx: ScriptContext, scope: ScopeRef): ScopeRef | null | undefined;
}

export interface ListLinkDef {
  from?: ScopeType[];
  to?: ScopeType;
  doc?: string;
  list(ctx: ScriptContext, scope: ScopeRef): ScopeRef[];
}

export class ScriptRegistry {
  readonly triggers = new Registry<TriggerDef>('триггер');
  readonly effects = new Registry<EffectDef>('эффект');
  readonly values = new Registry<ValueDef>('значение');
  readonly links = new Registry<LinkDef>('ссылка на скоуп');
  readonly lists = new Registry<ListLinkDef>('список');
  readonly constants = new Registry<number>('константа');
}
