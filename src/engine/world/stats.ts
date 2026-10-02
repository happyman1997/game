import type { BuildingDef, HoldingDef, ModifierDef, TraitDef } from '../content/defs';
import type { TextValue } from '../core/localization';
import type { Game } from '../game';
import type { Character } from '../types';
import { ageOf, skillIds } from './characters';
import { domainCounties } from './titles';

/**
 * Характеристики персонажа = база + сумма модификаторов из всех источников:
 * черты, временные модификаторы, культура, вера, возраст и «поставщики»
 * модификаторов, которые регистрируют моды (registries.modifierProviders).
 */
export type ModifierProviderFn = (game: Game, c: Character) => Record<string, number> | null | undefined;
export interface ModifierProvider {
  label?: TextValue;
  fn: ModifierProviderFn;
}

export type ProvinceModifierProviderFn = (game: Game, provId: string) => Record<string, number> | null | undefined;
export interface ProvinceModifierProvider {
  label?: TextValue;
  fn: ProvinceModifierProviderFn;
}

export interface StatPart {
  label: string;
  value: number;
}

function addInto(out: Record<string, number>, mods: Record<string, number> | null | undefined) {
  if (!mods) return;
  for (const [k, v] of Object.entries(mods)) if (typeof v === 'number') out[k] = (out[k] ?? 0) + v;
}

interface Source {
  label: string;
  mods: Record<string, number>;
}

function sources(game: Game, c: Character): Source[] {
  const out: Source[] = [];
  const base: Record<string, number> = { health: c.health };
  for (const s of skillIds(game)) base[s] = c.skills[s] ?? 0;
  addInto(base, game.defines.character?.base_stats);
  out.push({ label: game.loc.t('ui.base_value'), mods: base });
  for (const t of c.traits) {
    const d = game.content.get<TraitDef>('traits', t);
    if (d?.modifiers) out.push({ label: game.nameOf('traits', t), mods: d.modifiers });
  }
  for (const m of c.modifiers) {
    const d = game.content.get<ModifierDef>('modifiers', m.id);
    if (d?.modifiers) out.push({ label: game.nameOf('modifiers', m.id), mods: d.modifiers });
  }
  const cul = game.content.get('cultures', c.culture);
  if (cul?.modifiers) out.push({ label: game.nameOf('cultures', c.culture), mods: cul.modifiers });
  const faith = game.content.get('faiths', c.faith);
  if (faith?.modifiers) out.push({ label: game.nameOf('faiths', c.faith), mods: faith.modifiers });
  for (const [id, p] of game.engine.registries.modifierProviders.entries()) {
    try {
      const mods = p.fn(game, c);
      if (mods && Object.keys(mods).length) out.push({ label: p.label ? game.loc.resolve(p.label) : game.loc.tOr(`modsrc.${id}`, id), mods });
    } catch (e) {
      game.scriptError(`Поставщик модификаторов ${id}: ${(e as Error).message}`);
    }
  }
  return out;
}

function ageAdjust(game: Game, c: Character, out: Record<string, number>): Record<string, number> {
  const age = ageOf(game, c);
  const ch = game.defines.character ?? {};
  const adj: Record<string, number> = {};
  const adult = ch.adult_age ?? 16;
  if (age < adult) {
    const f = Math.max(0.15, age / adult);
    for (const s of skillIds(game)) adj[s] = (out[s] ?? 0) * f - (out[s] ?? 0);
  }
  const oldStart = ch.old_age_start ?? 50;
  if (age > oldStart) {
    const y = age - oldStart;
    adj.health = -y * (ch.old_age_health_per_year ?? 0.08);
    adj.prowess = -y * (ch.old_age_prowess_per_year ?? 0.2);
    adj.fertility = -y * (ch.old_age_fertility_per_year ?? 0.02);
  }
  return adj;
}

export function charStats(game: Game, c: Character): Record<string, number> {
  const cached = game.statCache.get(c.id);
  if (cached) return cached;
  const out: Record<string, number> = {};
  for (const s of sources(game, c)) addInto(out, s.mods);
  addInto(out, ageAdjust(game, c, out));
  game.statCache.set(c.id, out);
  return out;
}

export function stat(game: Game, c: Character, key: string): number {
  return charStats(game, c)[key] ?? 0;
}

/** Навык для отображения и формул: округлён, не меньше нуля. */
export function skill(game: Game, c: Character, key: string): number {
  return Math.max(0, Math.round(stat(game, c, key)));
}

export function statBreakdown(game: Game, c: Character, key: string): StatPart[] {
  const parts: StatPart[] = [];
  const total: Record<string, number> = {};
  for (const s of sources(game, c)) {
    addInto(total, s.mods);
    const v = s.mods[key];
    if (v) parts.push({ label: s.label, value: v });
  }
  const adj = ageAdjust(game, c, total)[key];
  if (adj) parts.push({ label: game.loc.t('ui.age'), value: adj });
  return parts;
}

// ------------------------------------------------------------ провинции

export function provStats(game: Game, provId: string): Record<string, number> {
  const key = `prov:${provId}`;
  const cached = game.statCache.get(key);
  if (cached) return cached;
  const out: Record<string, number> = {};
  const def = game.content.get('provinces', provId);
  const st = game.state.provinces[provId];
  if (def && st) {
    for (const h of def.holdings ?? []) {
      const hd = game.content.get<HoldingDef>('holdings', h);
      if (hd) addInto(out, { tax: hd.tax, levy: hd.levy, fort: hd.fort });
    }
    for (const b of st.buildings) addInto(out, game.content.get<BuildingDef>('buildings', b)?.modifiers);
    for (const m of st.modifiers) addInto(out, game.content.get<ModifierDef>('modifiers', m.id)?.modifiers);
    addInto(out, { development_growth: game.content.get('terrain', def.terrain)?.development_growth ?? 0 });
    for (const [id, p] of game.engine.registries.provinceModifierProviders.entries()) {
      try {
        addInto(out, p.fn(game, provId));
      } catch (e) {
        game.scriptError(`Поставщик модификаторов провинции ${id}: ${(e as Error).message}`);
      }
    }
  }
  game.statCache.set(key, out);
  return out;
}

export function provStat(game: Game, provId: string, key: string): number {
  return provStats(game, provId)[key] ?? 0;
}

/** Встроенный поставщик: «владельческие» модификаторы зданий в домене. */
export const buildingOwnerProvider: ModifierProviderFn = (game, c) => {
  if (!c.titles.length) return null;
  const out: Record<string, number> = {};
  for (const county of domainCounties(game, c)) {
    for (const b of game.state.provinces[county]?.buildings ?? []) {
      addInto(out, game.content.get<BuildingDef>('buildings', b)?.owner_modifiers);
    }
  }
  return out;
};

/** Встроенный поставщик: стресс снижает навыки на высоких уровнях. */
export const stressProvider: ModifierProviderFn = (game, c) => {
  const lvl = Math.floor(c.stress / 100);
  if (lvl <= 0) return null;
  const per = game.defines.character?.stress_skill_penalty ?? 1;
  const out: Record<string, number> = {};
  for (const s of skillIds(game)) out[s] = -per * lvl;
  return out;
};
