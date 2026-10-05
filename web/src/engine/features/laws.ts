/**
 * Законы державы (realm laws) — например, власть короны. Закон состоит в
 * группе (law_groups), в группе законы упорядочены по level. Закон даёт
 * правителю модификаторы (налоги и войска с вассалов, мнение вассалов) и
 * открывает права, которые данные проверяют триггерами (has_realm_law,
 * <группа>_level). Смена закона стоит престижа и возможна раз в несколько лет.
 *
 * Данные:
 *   law_groups: { icon, default, is_shown, cooldown_years, order }
 *   realm_laws: { group, level, icon, modifiers, can_change, change_cost, ai_will_do }
 */
import type { TextValue } from '../core/localization';
import type { Engine } from '../engine';
import type { Game } from '../game';
import { type ScriptContext, makeContext } from '../script/context';
import { evalTrigger, evalValue, failedTriggers, runEffect } from '../script/interpreter';
import type { Character, ScopeRef } from '../types';
import { costBlockers } from '../world/economy';
import type { EngineFeature } from './feature';

export interface LawGroupDef {
  id: string;
  name?: TextValue;
  icon?: string;
  order?: number;
  default: string;
  is_shown?: unknown;
  cooldown_years?: number;
}

export interface RealmLawDef {
  id: string;
  name?: TextValue;
  group: string;
  level: number;
  icon?: string;
  modifiers?: Record<string, number>;
  can_change?: unknown;
  change_cost?: { gold?: unknown; prestige?: unknown; piety?: unknown };
  on_change?: unknown;
  ai_will_do?: unknown;
}

export function lawGroups(game: Game): LawGroupDef[] {
  return game.content.all<LawGroupDef>('law_groups').sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
}

export function lawsOfGroup(game: Game, group: string): RealmLawDef[] {
  return game.content.all<RealmLawDef>('realm_laws').filter((l) => l.group === group).sort((a, b) => a.level - b.level);
}

export function isGroupShown(game: Game, c: Character, g: LawGroupDef): boolean {
  if (!c.titles.length) return false;
  const ctx = makeContext(game, { type: 'character', id: c.id });
  return evalTrigger(ctx, ctx.root, g.is_shown);
}

/** Действующий закон группы (у безземельных и при скрытой группе — нет). */
export function currentLaw(game: Game, c: Character, group: string): RealmLawDef | undefined {
  const gd = game.content.get<LawGroupDef>('law_groups', group);
  if (!gd || !c.titles.length) return undefined;
  const id = c.laws?.[group] ?? gd.default;
  return game.content.get<RealmLawDef>('realm_laws', id) ?? game.content.get<RealmLawDef>('realm_laws', gd.default);
}

export function lawChangeCost(game: Game, c: Character, law: RealmLawDef) {
  const ctx = makeContext(game, { type: 'character', id: c.id }, { law_owner: { type: 'character', id: c.id } });
  return {
    gold: Math.round(evalValue(ctx, ctx.root, law.change_cost?.gold ?? 0)),
    prestige: Math.round(evalValue(ctx, ctx.root, law.change_cost?.prestige ?? 0)),
    piety: Math.round(evalValue(ctx, ctx.root, law.change_cost?.piety ?? 0)),
  };
}

export function lawChangeBlockers(game: Game, c: Character, law: RealmLawDef): string[] {
  const gd = game.content.get<LawGroupDef>('law_groups', law.group);
  if (!gd) return ['?'];
  const out: string[] = [];
  const cur = currentLaw(game, c, law.group);
  if (cur?.id === law.id) out.push(game.loc.t('ui.law_current'));
  // законы меняются на одну ступень за раз
  if (cur && Math.abs(cur.level - law.level) > 1) out.push(game.loc.t('ui.law_one_step'));
  const cd = c.flags[`law_cd:${law.group}`];
  if (cd !== undefined && cd > game.date) out.push(game.loc.t('ui.on_cooldown', { days: cd - game.date }));
  const ctx = makeContext(game, { type: 'character', id: c.id });
  out.push(...failedTriggers(ctx, ctx.root, law.can_change));
  out.push(...costBlockers(game, c, lawChangeCost(game, c, law)));
  return out;
}

export function changeLaw(game: Game, c: Character, lawId: string, free = false): boolean {
  const law = game.content.get<RealmLawDef>('realm_laws', lawId);
  if (!law) return false;
  if (!free && lawChangeBlockers(game, c, law).length) return false;
  const gd = game.content.get<LawGroupDef>('law_groups', law.group)!;
  if (!free) {
    const cost = lawChangeCost(game, c, law);
    c.gold -= cost.gold;
    c.prestige -= cost.prestige;
    c.piety -= cost.piety;
    c.flags[`law_cd:${law.group}`] = game.date + Math.round((gd.cooldown_years ?? 5) * 365);
  }
  const prev = currentLaw(game, c, law.group);
  (c.laws ??= {})[law.group] = law.id;
  const ctx = makeContext(game, { type: 'character', id: c.id }, prev ? {} : {});
  runEffect(ctx, ctx.root, law.on_change);
  game.statCache.clear();
  game.emit('law.changed', { character: c, law: law.id, previous: prev?.id });
  if (game.isPlayer(c.id) || game.vassalsOf(c.id).some((v) => game.isPlayer(v.id))) {
    game.message(game.loc.t('msg.law_changed', { who: game.scopeName({ type: 'character', id: c.id }), law: game.nameOf('realm_laws', law.id) }), 'info', { type: 'character', id: c.id });
  }
  return true;
}

export function yearlyLawsAI(game: Game): void {
  for (const c of game.rulers()) {
    if (game.isPlayer(c.id) || c.prison || c.death !== undefined) continue;
    for (const gd of lawGroups(game)) {
      if (!isGroupShown(game, c, gd)) continue;
      const cur = currentLaw(game, c, gd.id);
      const opts = lawsOfGroup(game, gd.id).filter((l) => l.id !== cur?.id && !lawChangeBlockers(game, c, l).length);
      if (!opts.length) continue;
      const ctx = makeContext(game, { type: 'character', id: c.id });
      let best: { l: RealmLawDef; v: number } | undefined;
      for (const l of opts) {
        const v = l.ai_will_do != null ? evalValue(ctx, ctx.root, l.ai_will_do) : 0;
        if (v > 0 && (!best || v > best.v)) best = { l, v };
      }
      if (best && game.rng.next() * 100 < best.v) changeLaw(game, c, best.l.id);
    }
  }
}

export const lawsFeature: EngineFeature = {
  id: 'laws',
  doc: 'Законы державы: власть короны и другие группы законов',
  install(engine: Engine) {
    engine.systems.register('laws', { id: 'laws', order: 85, onYear: yearlyLawsAI }, 'core/laws');
    engine.registries.modifierProviders.register('realm_laws', {
      fn: (game, c) => {
        if (!c.titles.length) return null;
        const out: { label: string; modifiers: Record<string, number> }[] = [];
        for (const gd of lawGroups(game)) {
          if (!isGroupShown(game, c, gd)) continue;
          const l = currentLaw(game, c, gd.id);
          if (l?.modifiers) out.push({ label: game.nameOf('realm_laws', l.id), modifiers: l.modifiers });
        }
        return out;
      },
    }, 'core/laws');
  },
  script(engine: Engine) {
    const { triggers, effects, values } = engine.script;
    const ch = (ctx: ScriptContext, s: ScopeRef | null | undefined) => (s?.type === 'character' ? ctx.game.char(s.id) : undefined);
    triggers.register('has_realm_law', {
      scopes: ['character'],
      doc: 'Действует закон державы',
      eval: (ctx, s, arg) => {
        const c = ch(ctx, s);
        const law = ctx.game.content.get<RealmLawDef>('realm_laws', String(arg));
        return !!c && !!law && currentLaw(ctx.game, c, law.group)?.id === law.id;
      },
      describe: (ctx, _s, arg) => ctx.game.loc.t('tr.has_realm_law', { value: ctx.game.nameOf('realm_laws', String(arg)) }),
    }, 'core/laws');
    for (const gd of engine.content.all<LawGroupDef>('law_groups')) {
      values.register(`${gd.id}_level`, {
        scopes: ['character'],
        doc: `Уровень закона группы ${gd.id} (−1, если не действует)`,
        get: (ctx, s) => {
          const c = ch(ctx, s);
          const l = c ? currentLaw(ctx.game, c, gd.id) : undefined;
          return l ? l.level : -1;
        },
      }, 'core/laws');
    }
    effects.register('set_realm_law', {
      scopes: ['character'],
      doc: 'Установить закон державы (без цены и перерыва)',
      apply: (ctx, s, arg) => { const c = ch(ctx, s); if (c) changeLaw(ctx.game, c, String(arg), true); },
      describe: (ctx, _s, arg) => ctx.game.loc.t('fx.set_realm_law', { value: ctx.game.nameOf('realm_laws', String(arg)) }),
    }, 'core/laws');
    engine.registries.contentValidators.register('laws', (e, v) => {
      for (const gd of e.content.all<LawGroupDef>('law_groups')) {
        v.ref('realm_laws', gd.default, `law_groups/${gd.id} default`);
        v.trigger(gd.is_shown, `law_groups/${gd.id} is_shown`);
      }
      for (const l of e.content.all<RealmLawDef>('realm_laws')) {
        v.ref('law_groups', l.group, `realm_laws/${l.id}`);
        v.trigger(l.can_change, `realm_laws/${l.id} can_change`);
        v.effect(l.on_change, `realm_laws/${l.id} on_change`);
      }
    }, 'core/laws');
  },
};
