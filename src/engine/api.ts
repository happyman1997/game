/**
 * API, которое получает JS-скрипт мода в функции init(api).
 *
 *   export function init(api) {
 *     api.script.effect('my_effect', { apply(ctx, scope, arg) { ... } });
 *     api.systems.add({ id: 'my_system', order: 100, onMonth(game) { ... } });
 *     api.hooks.on('character.death', ({ game, character }) => { ... });
 *     api.ui.mapModes.register('my_mode', { name: 'Мой режим', color: (game, p) => '#ff0000' });
 *   }
 */
import { dateParts, durationDays, makeDate, parseDate } from './core/date';
import { deepMerge } from './core/merge';
import { fbm, valueNoise } from './core/noise';
import { Rng, hashString } from './core/rng';
import type { Engine } from './engine';
import type { HookHandler } from './core/hooks';
import type { ModManifest } from './mods/types';
import { charRef, makeContext, provRef, titleRef } from './script/context';
import { describeEffect, evalTrigger, evalValue, resolveScope, runEffect } from './script/interpreter';
import type { EffectDef, LinkDef, ListLinkDef, TriggerDef, ValueDef } from './script/registry';
import type { GameSystem } from './systems/core';
import * as world from './world';

export function createModApi(engine: Engine, mod: ModManifest) {
  const owner = mod?.id ?? 'unknown';
  return {
    mod,
    engine,
    content: engine.content,
    loc: engine.loc,
    formats: engine.formats,
    defines: () => engine.content.singleton('defines'),
    registries: engine.registries,
    ui: engine.ui,
    world,
    hooks: {
      on: (name: string, fn: HookHandler, priority = 0) => engine.hooks.on(name, fn, { priority, owner }),
      emit: (name: string, payload: any) => engine.hooks.emit(name, payload),
    },
    script: {
      trigger: (name: string, def: TriggerDef) => engine.script.triggers.register(name, def, owner),
      effect: (name: string, def: EffectDef) => engine.script.effects.register(name, def, owner),
      value: (name: string, def: ValueDef) => engine.script.values.register(name, def, owner),
      link: (name: string, def: LinkDef) => engine.script.links.register(name, def, owner),
      list: (name: string, def: ListLinkDef) => engine.script.lists.register(name, def, owner),
      constant: (name: string, v: number) => engine.script.constants.register(name, v, owner),
      evalTrigger,
      runEffect,
      evalValue,
      resolveScope,
      describeEffect,
      makeContext,
      charRef,
      titleRef,
      provRef,
    },
    systems: {
      add: (s: GameSystem) => engine.systems.register(s.id, s, owner),
      replace: (id: string, s: Partial<GameSystem>) => {
        const prev = engine.systems.get(id);
        engine.systems.register(id, { ...(prev ?? { order: 100 }), ...s, id } as GameSystem, owner);
      },
      remove: (id: string) => engine.systems.delete(id),
      get: (id: string) => engine.systems.get(id),
      list: () => engine.systems.ids(),
    },
    util: { Rng, hashString, parseDate, makeDate, dateParts, durationDays, deepMerge, valueNoise, fbm },
    log: (...args: unknown[]) => console.log(`[${owner}]`, ...args),
  };
}

export type ModAPI = ReturnType<typeof createModApi>;
