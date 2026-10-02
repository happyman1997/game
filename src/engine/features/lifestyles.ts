/**
 * Образ жизни (lifestyles). Взрослый персонаж выбирает фокус одного из
 * образов жизни, каждый месяц копит опыт этого образа жизни и тратит его на
 * перки — узлы деревьев. Последний перк дерева обычно даёт черту.
 *
 * Данные:
 *   lifestyles:   { skill, icon, color, order, is_shown }
 *   focuses:      { lifestyle, icon, modifiers, is_shown, ai_will_do }
 *   perks:        { lifestyle, tree, requires, icon, modifiers, trait, effect, ai_will_do }
 *   defines.lifestyle: { base_xp, xp_per_skill, perk_cost, perk_cost_growth, focus_change_cooldown_months }
 */
import type { TextValue } from '../core/localization';
import type { Engine } from '../engine';
import type { Game } from '../game';
import { makeContext } from '../script/context';
import { evalTrigger, evalValue, runEffect } from '../script/interpreter';
import type { Character, LifestyleState } from '../types';
import { addTrait, isAdult, traitDef } from '../world/characters';
import { skill, stat } from '../world/stats';
import { type EngineFeature, asList } from './feature';

export interface LifestyleDef {
  id: string;
  name?: TextValue;
  skill: string;
  icon?: string;
  color?: string;
  order?: number;
  is_shown?: unknown;
}

export interface FocusDef {
  id: string;
  name?: TextValue;
  lifestyle: string;
  icon?: string;
  modifiers?: Record<string, number>;
  is_shown?: unknown;
  ai_will_do?: unknown;
}

export interface PerkDef {
  id: string;
  name?: TextValue;
  lifestyle: string;
  tree: string;
  requires?: string | string[];
  icon?: string;
  modifiers?: Record<string, number>;
  trait?: string;
  effect?: unknown;
  ai_will_do?: unknown;
}

function defs(game: Game) {
  return game.defines.lifestyle ?? {};
}

export function lifestyleState(c: Character): LifestyleState {
  c.lifestyle ??= { xp: {}, perks: [] };
  return c.lifestyle;
}

export function lifestyles(game: Game): LifestyleDef[] {
  return game.content.all<LifestyleDef>('lifestyles').sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
}

export function focusesOf(game: Game, lifestyle: string): FocusDef[] {
  return game.content.all<FocusDef>('focuses').filter((f) => f.lifestyle === lifestyle);
}

export function perksOf(game: Game, lifestyle: string): PerkDef[] {
  return game.content.all<PerkDef>('perks').filter((p) => p.lifestyle === lifestyle);
}

/** Деревья образа жизни: tree → перки в порядке глубины (корни первыми). */
export function treesOf(game: Game, lifestyle: string): { tree: string; perks: PerkDef[] }[] {
  const byTree = new Map<string, PerkDef[]>();
  for (const p of perksOf(game, lifestyle)) {
    const l = byTree.get(p.tree) ?? [];
    l.push(p);
    byTree.set(p.tree, l);
  }
  const depth = (p: PerkDef, seen = new Set<string>()): number => {
    if (seen.has(p.id)) return 0;
    seen.add(p.id);
    const req = asList(p.requires).map((r) => game.content.get<PerkDef>('perks', r)).filter((x): x is PerkDef => !!x);
    return req.length ? 1 + Math.max(...req.map((r) => depth(r, seen))) : 0;
  };
  return [...byTree.entries()].map(([tree, perks]) => ({ tree, perks: perks.map((p) => ({ p, d: depth(p) })).sort((a, b) => a.d - b.d).map((x) => x.p) }));
}

export function currentLifestyle(game: Game, c: Character): LifestyleDef | undefined {
  const f = c.lifestyle?.focus ? game.content.get<FocusDef>('focuses', c.lifestyle.focus) : undefined;
  return f ? game.content.get<LifestyleDef>('lifestyles', f.lifestyle) : undefined;
}

export function hasPerk(c: Character, perk: string): boolean {
  return !!c.lifestyle?.perks.includes(perk);
}

export function perkCost(game: Game, c: Character, lifestyle: string): number {
  const d = defs(game);
  const owned = (c.lifestyle?.perks ?? []).filter((p) => game.content.get<PerkDef>('perks', p)?.lifestyle === lifestyle).length;
  return Math.round((d.perk_cost ?? 300) + (d.perk_cost_growth ?? 100) * owned);
}

export function perkRequirementsMet(game: Game, c: Character, perk: PerkDef): boolean {
  return asList(perk.requires).every((r) => hasPerk(c, r));
}

export function availablePerks(game: Game, c: Character, lifestyle: string): PerkDef[] {
  return perksOf(game, lifestyle).filter((p) => !hasPerk(c, p.id) && perkRequirementsMet(game, c, p));
}

export function canUnlockPerk(game: Game, c: Character, perkId: string): boolean {
  const p = game.content.get<PerkDef>('perks', perkId);
  if (!p || hasPerk(c, perkId) || !perkRequirementsMet(game, c, p)) return false;
  return (c.lifestyle?.xp[p.lifestyle] ?? 0) >= perkCost(game, c, p.lifestyle);
}

/** Открывает перк. free — без траты опыта (из скрипта). */
export function unlockPerk(game: Game, c: Character, perkId: string, free = false): boolean {
  const p = game.content.get<PerkDef>('perks', perkId);
  if (!p || hasPerk(c, perkId)) return false;
  if (!free && !canUnlockPerk(game, c, perkId)) return false;
  const st = lifestyleState(c);
  if (!free) st.xp[p.lifestyle] = (st.xp[p.lifestyle] ?? 0) - perkCost(game, c, p.lifestyle);
  st.perks.push(p.id);
  if (p.trait) addTrait(game, c, p.trait);
  if (p.effect) {
    const ctx = makeContext(game, { type: 'character', id: c.id }, { perk_owner: { type: 'character', id: c.id } });
    runEffect(ctx, ctx.root, p.effect);
  }
  delete c.flags['tmp:perk_notified'];
  game.monthCache.delete(`lifestyle:${c.id}`);
  game.statCache.delete(c.id);
  game.emit('perk.gained', { character: c, perk: p.id });
  if (game.isPlayer(c.id)) game.message(game.loc.t('msg.perk_gained', { perk: game.nameOf('perks', p.id) }), 'good');
  game.notify('character');
  return true;
}

export function focusChangeBlockedUntil(game: Game, c: Character): number {
  const st = c.lifestyle;
  if (!st?.focus || st.focusSince == null) return 0;
  const until = st.focusSince + Math.round((defs(game).focus_change_cooldown_months ?? 12) * 30);
  return until > game.date ? until : 0;
}

export function isFocusShown(game: Game, c: Character, focusId: string): boolean {
  const f = game.content.get<FocusDef>('focuses', focusId);
  if (!f) return false;
  const l = game.content.get<LifestyleDef>('lifestyles', f.lifestyle);
  const ctx = makeContext(game, { type: 'character', id: c.id });
  return evalTrigger(ctx, ctx.root, l?.is_shown) && evalTrigger(ctx, ctx.root, f.is_shown);
}

export function setFocus(game: Game, c: Character, focusId: string | undefined, force = false): boolean {
  if (focusId && !game.content.get<FocusDef>('focuses', focusId)) return false;
  if (!force && focusChangeBlockedUntil(game, c)) return false;
  const st = lifestyleState(c);
  if (st.focus === focusId) return false;
  st.focus = focusId;
  st.focusSince = game.date;
  game.monthCache.delete(`lifestyle:${c.id}`);
  game.statCache.delete(c.id);
  game.emit('lifestyle.focus_changed', { character: c, focus: focusId });
  return true;
}

function lifestyleModifiers(game: Game, c: Character, st: LifestyleState) {
  const out: { label: string; modifiers: Record<string, number> }[] = [];
  const f = st.focus ? game.content.get<FocusDef>('focuses', st.focus) : undefined;
  if (f?.modifiers && isAdult(game, c)) out.push({ label: game.loc.t('ui.focus_n', { name: game.nameOf('focuses', f.id) }), modifiers: f.modifiers });
  for (const id of st.perks) {
    const p = game.content.get<PerkDef>('perks', id);
    if (p?.modifiers) out.push({ label: game.nameOf('perks', id), modifiers: p.modifiers });
  }
  return out;
}

export function monthlyXp(game: Game, c: Character): number {
  const l = currentLifestyle(game, c);
  if (!l) return 0;
  const d = defs(game);
  const base = (d.base_xp ?? 20) + skill(game, c, l.skill) * (d.xp_per_skill ?? 2);
  return Math.max(0, base * (1 + stat(game, c, 'lifestyle_xp_mult')));
}

/** ИИ (и стартовый выбор для всех): фокус по навыкам и образованию. */
export function aiChooseFocus(game: Game, c: Character): string | undefined {
  const edu = c.traits.map((t) => traitDef(game, t)?.education?.skill).find(Boolean);
  const opts: { id: string; w: number }[] = [];
  const ctx = makeContext(game, { type: 'character', id: c.id });
  for (const l of lifestyles(game)) {
    if (!evalTrigger(ctx, ctx.root, l.is_shown)) continue;
    const base = Math.max(1, skill(game, c, l.skill)) + (edu === l.skill ? 10 : 0);
    for (const f of focusesOf(game, l.id)) {
      if (!evalTrigger(ctx, ctx.root, f.is_shown)) continue;
      const w = base * Math.max(0, f.ai_will_do != null ? evalValue(ctx, ctx.root, f.ai_will_do) : 1);
      if (w > 0) opts.push({ id: f.id, w });
    }
  }
  return game.rng.weighted(opts, (o) => o.w)?.id;
}

export function aiChoosePerk(game: Game, c: Character, lifestyle: string): string | undefined {
  const ctx = makeContext(game, { type: 'character', id: c.id });
  const opts = availablePerks(game, c, lifestyle).map((p) => ({ id: p.id, w: Math.max(0, p.ai_will_do != null ? evalValue(ctx, ctx.root, p.ai_will_do) : 10) }));
  return game.rng.weighted(
    opts.filter((o) => o.w > 0),
    (o) => o.w,
  )?.id;
}

export function monthlyLifestyles(game: Game): void {
  for (const c of game.living()) {
    if (!isAdult(game, c) || c.prison) continue;
    const st = lifestyleState(c);
    if (!st.focus || !game.content.get('focuses', st.focus)) {
      setFocus(game, c, aiChooseFocus(game, c), true);
      if (!st.focus) continue;
    }
    const l = currentLifestyle(game, c);
    if (!l) continue;
    if (!availablePerks(game, c, l.id).length) continue; // всё изучено
    st.xp[l.id] = (st.xp[l.id] ?? 0) + monthlyXp(game, c);
    if (st.xp[l.id] < perkCost(game, c, l.id)) continue;
    if (game.isPlayer(c.id)) {
      if (!c.flags['tmp:perk_notified']) {
        c.flags['tmp:perk_notified'] = game.date + 3650;
        game.message(game.loc.t('msg.perk_available', { lifestyle: game.nameOf('lifestyles', l.id) }), 'good');
      }
    } else {
      const pick = aiChoosePerk(game, c, l.id);
      if (pick) unlockPerk(game, c, pick);
    }
  }
}

export const lifestylesFeature: EngineFeature = {
  id: 'lifestyles',
  doc: 'Образ жизни: фокусы, опыт и деревья перков',
  install(engine: Engine) {
    engine.systems.register('lifestyles', { id: 'lifestyles', order: 25, onMonth: monthlyLifestyles }, 'core/lifestyles');

    engine.registries.modifierProviders.register('lifestyle', {
      fn: (game, c) => {
        const st = c.lifestyle;
        if (!st) return null;
        return game.cachedMonthly(`lifestyle:${c.id}`, () => lifestyleModifiers(game, c, st));
      },
    }, 'core/lifestyles');

  },
  script(engine: Engine) {
    const { triggers, effects, values } = engine.script;
    const ch = (ctx: any, s: any) => (s?.type === 'character' ? (ctx.game as Game).char(s.id) : undefined);
    triggers.register('has_perk', {
      scopes: ['character'],
      doc: 'Открыт перк',
      eval: (ctx, s, arg) => !!ch(ctx, s) && asList(arg).some((p) => hasPerk(ch(ctx, s)!, String(p))),
      describe: (ctx, _s, arg) => ctx.game.loc.t('tr.has_perk', { value: asList(arg).map((p) => ctx.game.nameOf('perks', String(p))).join(' / ') }),
    }, 'core/lifestyles');
    triggers.register('has_focus', {
      scopes: ['character'],
      doc: 'Выбран фокус образа жизни',
      eval: (ctx, s, arg) => asList(arg).includes(ch(ctx, s)?.lifestyle?.focus as any),
      describe: (ctx, _s, arg) => ctx.game.loc.t('tr.has_focus', { value: asList(arg).map((p) => ctx.game.nameOf('focuses', String(p))).join(' / ') }),
    }, 'core/lifestyles');
    triggers.register('has_lifestyle', {
      scopes: ['character'],
      doc: 'Текущий фокус принадлежит образу жизни',
      eval: (ctx, s, arg) => {
        const c = ch(ctx, s);
        return !!c && asList(arg).includes(currentLifestyle(ctx.game, c)?.id as any);
      },
      describe: (ctx, _s, arg) => ctx.game.loc.t('tr.has_lifestyle', { value: asList(arg).map((p) => ctx.game.nameOf('lifestyles', String(p))).join(' / ') }),
    }, 'core/lifestyles');
    values.register('num_perks', { scopes: ['character'], doc: 'Число открытых перков', get: (ctx, s) => ch(ctx, s)?.lifestyle?.perks.length ?? 0 }, 'core/lifestyles');
    values.register('lifestyle_xp', {
      scopes: ['character'],
      doc: 'Опыт текущего образа жизни',
      get: (ctx, s) => {
        const c = ch(ctx, s);
        const l = c ? currentLifestyle(ctx.game, c) : undefined;
        return c && l ? (c.lifestyle?.xp[l.id] ?? 0) : 0;
      },
    }, 'core/lifestyles');
    effects.register('add_perk', {
      scopes: ['character'],
      doc: 'Открыть перк бесплатно',
      apply: (ctx, s, arg) => { const c = ch(ctx, s); if (c) unlockPerk(ctx.game, c, String(arg), true); },
      describe: (ctx, _s, arg) => ctx.game.loc.t('fx.add_perk', { value: ctx.game.nameOf('perks', String(arg)) }),
    }, 'core/lifestyles');
    effects.register('remove_perk', {
      scopes: ['character'],
      doc: 'Убрать перк',
      apply: (ctx, s, arg) => {
        const c = ch(ctx, s);
        if (c?.lifestyle) c.lifestyle.perks = c.lifestyle.perks.filter((p) => p !== arg);
        if (c) {
          ctx.game.monthCache.delete(`lifestyle:${c.id}`);
          ctx.game.statCache.delete(c.id);
        }
      },
    }, 'core/lifestyles');
    effects.register('set_focus', {
      scopes: ['character'],
      doc: 'Сменить фокус образа жизни (без перерыва)',
      apply: (ctx, s, arg) => { const c = ch(ctx, s); if (c) setFocus(ctx.game, c, String(arg), true); },
      describe: (ctx, _s, arg) => ctx.game.loc.t('fx.set_focus', { value: ctx.game.nameOf('focuses', String(arg)) }),
    }, 'core/lifestyles');
    effects.register('add_lifestyle_xp', {
      scopes: ['character'],
      doc: 'Опыт образа жизни: число (текущий образ жизни) или { lifestyle, value }',
      apply: (ctx, s, arg) => {
        const c = ch(ctx, s);
        if (!c) return;
        const lid = typeof arg === 'object' && arg && 'lifestyle' in arg ? String(arg.lifestyle) : currentLifestyle(ctx.game, c)?.id;
        if (!lid) return;
        const st = lifestyleState(c);
        st.xp[lid] = Math.max(0, (st.xp[lid] ?? 0) + evalValue(ctx, s, typeof arg === 'object' && arg && 'lifestyle' in arg ? arg.value : arg));
      },
      describe: (ctx, s, arg) => {
        const c = ch(ctx, s);
        const lid = typeof arg === 'object' && arg && 'lifestyle' in arg ? String(arg.lifestyle) : c ? currentLifestyle(ctx.game, c)?.id : undefined;
        const v = Math.round(evalValue(ctx, s, typeof arg === 'object' && arg && 'lifestyle' in arg ? arg.value : arg));
        return ctx.game.loc.t('fx.add_lifestyle_xp', { value: v > 0 ? `+${v}` : String(v), lifestyle: lid ? ctx.game.nameOf('lifestyles', lid) : '' });
      },
    }, 'core/lifestyles');

    engine.registries.contentValidators.register('lifestyles', (e, v) => {
      for (const l of e.content.all<LifestyleDef>('lifestyles')) {
        if (!e.content.has('skills', l.skill)) v.issue(`lifestyles/${l.id}: нет навыка "${l.skill}"`);
        v.trigger(l.is_shown, `lifestyles/${l.id} is_shown`);
      }
      for (const f of e.content.all<FocusDef>('focuses')) {
        v.ref('lifestyles', f.lifestyle, `focuses/${f.id}`);
        v.trigger(f.is_shown, `focuses/${f.id} is_shown`);
      }
      for (const p of e.content.all<PerkDef>('perks')) {
        v.ref('lifestyles', p.lifestyle, `perks/${p.id}`);
        for (const r of asList(p.requires)) v.ref('perks', r, `perks/${p.id} requires`);
        if (p.trait) v.ref('traits', p.trait, `perks/${p.id}`);
        v.effect(p.effect, `perks/${p.id} effect`);
      }
    }, 'core/lifestyles');
  },
};
