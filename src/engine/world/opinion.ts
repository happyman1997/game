import type { OpinionModifierDef, TraitDef } from '../content/defs';
import type { TextValue } from '../core/localization';
import type { Game } from '../game';
import type { Character } from '../types';
import { isAdult, isParentOf, isSibling } from './characters';
import { stat } from './stats';

/**
 * Мнение персонажа a о персонаже b — сумма «частей» от поставщиков мнения.
 * Встроенные поставщики (черты, культура, вера, семья, сюзерен, сохранённые
 * модификаторы) зарегистрированы в registries.opinionProviders наравне с
 * моддерскими.
 */
export interface OpinionPart {
  label: string;
  value: number;
}
export type OpinionProviderFn = (game: Game, a: Character, b: Character) => OpinionPart[] | OpinionPart | null | undefined;
export interface OpinionProvider {
  label?: TextValue;
  fn: OpinionProviderFn;
}

export function opinionBreakdown(game: Game, a: Character, b: Character): OpinionPart[] {
  const out: OpinionPart[] = [];
  if (a.id === b.id) return out;
  for (const [id, p] of game.engine.registries.opinionProviders.entries()) {
    try {
      const r = p.fn(game, a, b);
      if (!r) continue;
      for (const part of Array.isArray(r) ? r : [r]) if (part.value) out.push(part);
    } catch (e) {
      game.scriptError(`Поставщик мнения ${id}: ${(e as Error).message}`);
    }
  }
  return out;
}

export function opinion(game: Game, a: Character, b: Character): number {
  if (a.id === b.id) return 100;
  const key = `op:${a.id}>${b.id}`;
  const cached = game.statCache.get(key);
  if (cached) return cached.v;
  const v = Math.max(-100, Math.min(100, Math.round(opinionBreakdown(game, a, b).reduce((s, p) => s + p.value, 0))));
  game.statCache.set(key, { v });
  return v;
}

/** Добавляет модификатор мнения: a станет иначе относиться к b. */
export function addOpinion(game: Game, a: Character, b: Character, modId: string, value?: number): void {
  const def = game.content.get<OpinionModifierDef>('opinion_modifiers', modId);
  const v = value ?? def?.value ?? 0;
  const list = (a.opinions[b.id] ??= []);
  const months = def?.months ?? (def?.years != null ? def.years * 12 : undefined);
  const expires = months != null ? game.date + Math.round(months * 30) : undefined;
  if (!def?.stacking) {
    const ex = list.find((e) => e.mod === modId);
    if (ex) {
      ex.value = v;
      ex.expires = expires;
      game.statCache.delete(`op:${a.id}>${b.id}`);
      return;
    }
  }
  list.push({ mod: modId, value: v, expires });
  game.statCache.delete(`op:${a.id}>${b.id}`);
}

export function removeOpinion(game: Game, a: Character, b: Character, modId: string): void {
  const list = a.opinions[b.id];
  if (!list) return;
  a.opinions[b.id] = list.filter((e) => e.mod !== modId);
  if (!a.opinions[b.id].length) delete a.opinions[b.id];
}

export function hasOpinionModifier(a: Character, b: Character, modId: string): boolean {
  return !!a.opinions[b.id]?.some((e) => e.mod === modId);
}

/** Ежемесячно: истечение и затухание модификаторов мнения. */
export function decayOpinions(game: Game): void {
  for (const c of game.living()) {
    for (const [target, list] of Object.entries(c.opinions)) {
      const kept = list.filter((e) => {
        if (e.expires != null && e.expires <= game.date) return false;
        const def = game.content.get<OpinionModifierDef>('opinion_modifiers', e.mod);
        if (def?.decay) {
          const s = Math.sign(e.value);
          e.value -= s * def.decay;
          if (Math.sign(e.value) !== s || e.value === 0) return false;
        }
        return true;
      });
      const t = game.char(target);
      if (kept.length && t && t.death === undefined) c.opinions[target] = kept;
      else delete c.opinions[target];
    }
  }
}

// ------------------------------------------------------------ встроенные поставщики

export const builtinOpinionProviders: Record<string, OpinionProviderFn> = {
  stored: (game, a, b) =>
    (a.opinions[b.id] ?? []).map((e) => ({ label: game.nameOf('opinion_modifiers', e.mod), value: Math.round(e.value) })),

  traits: (game, a, b) => {
    let v = 0;
    for (const t of a.traits) {
      const comp = game.content.get<TraitDef>('traits', t)?.compatibility;
      if (!comp) continue;
      for (const t2 of b.traits) v += comp[t2] ?? 0;
    }
    return v ? { label: game.loc.t('opinion.traits'), value: v } : null;
  },

  general: (game, _a, b) => {
    const v = Math.round(stat(game, b, 'general_opinion'));
    return v ? { label: game.loc.t('opinion.general'), value: v } : null;
  },

  attraction: (game, a, b) => {
    if (a.female === b.female || !isAdult(game, a) || !isAdult(game, b)) return null;
    const v = Math.round(stat(game, b, 'attraction_opinion'));
    return v ? { label: game.loc.t('opinion.attraction'), value: v } : null;
  },

  culture: (game, a, b) => {
    const o = game.defines.opinion ?? {};
    const same = a.culture === b.culture;
    const v = same ? (o.same_culture ?? 0) : (o.different_culture ?? 0);
    return v ? { label: game.loc.t(same ? 'opinion.same_culture' : 'opinion.different_culture'), value: v } : null;
  },

  faith: (game, a, b) => {
    const o = game.defines.opinion ?? {};
    const same = a.faith === b.faith;
    const v = same ? (o.same_faith ?? 0) : (o.different_faith ?? 0);
    return v ? { label: game.loc.t(same ? 'opinion.same_faith' : 'opinion.different_faith'), value: v } : null;
  },

  family: (game, a, b) => {
    const o = game.defines.opinion ?? {};
    const parts: OpinionPart[] = [];
    if (a.spouses.includes(b.id)) parts.push({ label: game.loc.t('opinion.spouse'), value: o.spouse ?? 20 });
    if (isParentOf(b, a)) parts.push({ label: game.loc.t('opinion.parent'), value: o.parent ?? 20 });
    if (isParentOf(a, b)) parts.push({ label: game.loc.t('opinion.child'), value: o.child ?? 20 });
    if (isSibling(a, b)) parts.push({ label: game.loc.t('opinion.sibling'), value: o.sibling ?? 10 });
    else if (a.dynasty && a.dynasty === b.dynasty && !isParentOf(a, b) && !isParentOf(b, a))
      parts.push({ label: game.loc.t('opinion.same_dynasty'), value: o.same_dynasty ?? 5 });
    return parts;
  },

  liege: (game, a, b) => {
    if (a.liege !== b.id || !a.titles.length) return null;
    const o = game.defines.opinion ?? {};
    const v = Math.round((o.liege_base ?? 0) + stat(game, b, 'vassal_opinion'));
    return v ? { label: game.loc.t('opinion.liege'), value: v } : null;
  },

  claim: (game, a, b) => {
    // Претенденты недолюбливают тех, кто держит их титулы.
    const v = b.titles.some((t) => a.claims.includes(t)) ? (game.defines.opinion?.holds_my_claim ?? -15) : 0;
    return v ? { label: game.loc.t('opinion.holds_claim'), value: v } : null;
  },
};
