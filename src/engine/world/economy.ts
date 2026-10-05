import type { Game } from '../game';
import type { Character } from '../types';
import { domainCounties, primaryTier } from './titles';
import { provStat, skill, stat } from './stats';

/**
 * Экономика: налоги с графств, ополчения, лимит домена, ежемесячные
 * престиж и благочестие. Все коэффициенты — в defines.economy.
 */
export interface IncomePart {
  label: string;
  value: number;
}

function econ(game: Game) {
  return game.defines.economy ?? {};
}

export function countyTax(game: Game, countyId: string): number {
  const p = game.state.provinces[countyId];
  if (!p) return 0;
  const e = econ(game);
  const base = provStat(game, countyId, 'tax');
  return base * (1 + p.development * (e.development_tax ?? 0.02)) * (1 + provStat(game, countyId, 'tax_mult'));
}

export function countyLevy(game: Game, countyId: string): number {
  const p = game.state.provinces[countyId];
  if (!p) return 0;
  const e = econ(game);
  const base = provStat(game, countyId, 'levy');
  return base * (1 + p.development * (e.development_levy ?? 0.01)) * (1 + provStat(game, countyId, 'levy_mult'));
}

export function domainLimit(game: Game, c: Character): number {
  const e = econ(game);
  const tierBonus = (e.domain_limit_by_tier ?? [0, 0, 1, 2, 3])[primaryTier(game, c)] ?? 0;
  return Math.floor(
    (e.domain_limit_base ?? 2) + skill(game, c, e.domain_skill ?? 'stewardship') / (e.domain_limit_per_skill ?? 5) + tierBonus + stat(game, c, 'domain_limit'),
  );
}

function isOccupied(game: Game, countyId: string): boolean {
  return !!game.state.provinces[countyId]?.occupant;
}

/** Валовый налог с собственного домена (без вассалов). */
export function domainTax(game: Game, c: Character): number {
  return game.cachedDaily(`dtax:${c.id}`, () => computeDomainTax(game, c));
}

function computeDomainTax(game: Game, c: Character): number {
  const e = econ(game);
  const counties = domainCounties(game, c);
  let sum = 0;
  for (const cid of counties) if (!isOccupied(game, cid)) sum += countyTax(game, cid);
  const skillMult = 1 + skill(game, c, e.tax_skill ?? 'stewardship') * (e.tax_per_skill ?? 0.02);
  const over = Math.max(0, counties.length - domainLimit(game, c));
  const overMult = Math.max(0.2, 1 - over * (e.over_domain_penalty ?? 0.2));
  return sum * skillMult * (1 + stat(game, c, 'tax_mult')) * overMult;
}

export function vassalTaxShare(game: Game): number {
  return econ(game).vassal_tax_share ?? 0.15;
}

export function armyMaintenance(game: Game, c: Character): number {
  const per100 = econ(game).levy_maintenance_per_100 ?? 0.25;
  let men = 0;
  for (const a of Object.values(game.state.armies)) if (a.owner === c.id) men += a.size - (a.regiments ?? []).reduce((x, r) => x + r.size, 0);
  return Math.max(0, (men / 100) * per100 * (1 + stat(game, c, 'army_upkeep_mult')));
}

export function incomeBreakdown(game: Game, c: Character): IncomePart[] {
  const parts: IncomePart[] = [];
  if (!c.titles.length) {
    const flat = stat(game, c, 'monthly_income');
    if (flat) parts.push({ label: game.loc.t('ui.other_income'), value: flat });
    return parts;
  }
  const dom = domainTax(game, c);
  parts.push({ label: game.loc.t('ui.domain_tax'), value: dom });
  const share = vassalTaxShare(game);
  let fromVassals = 0;
  const taxMult = Math.max(0, 1 + stat(game, c, 'vassal_tax_mult'));
  for (const v of game.vassalsOf(c.id)) if (!inRevolt(game, v.id, c.id)) fromVassals += domainTax(game, v) * share * taxMult;
  if (fromVassals) parts.push({ label: game.loc.t('ui.vassal_tax'), value: fromVassals });
  if (c.liege) {
    const l = game.char(c.liege);
    parts.push({ label: game.loc.t('ui.liege_tax'), value: -dom * share * (l ? Math.max(0, 1 + stat(game, l, 'vassal_tax_mult')) : 1) });
  }
  const flat = stat(game, c, 'monthly_income');
  if (flat) parts.push({ label: game.loc.t('ui.other_income'), value: flat });
  const army = armyMaintenance(game, c);
  if (army) parts.push({ label: game.loc.t('ui.army_upkeep'), value: -army });
  for (const extra of game.engine.hooks.collect<IncomePart>('economy.income', { game, character: c })) parts.push(extra);
  return parts;
}

export function monthlyIncome(game: Game, c: Character): number {
  return incomeBreakdown(game, c).reduce((s, p) => s + p.value, 0);
}

export function monthlyPrestige(game: Game, c: Character): number {
  const e = econ(game);
  const byTier = (e.monthly_prestige_by_tier ?? [0, 0.2, 0.5, 1, 1.5])[primaryTier(game, c)] ?? 0;
  let v = byTier + stat(game, c, 'monthly_prestige');
  if (c.gold < 0) v -= Math.min(5, -c.gold / (e.debt_prestige_divisor ?? 50));
  return v;
}

export function monthlyPiety(game: Game, c: Character): number {
  const e = econ(game);
  return skill(game, c, 'learning') * (e.piety_per_learning ?? 0.03) + stat(game, c, 'monthly_piety');
}

/** Ополчения своего домена с учётом восстановления. */
export function domainLevy(game: Game, c: Character): number {
  let sum = 0;
  for (const cid of domainCounties(game, c)) if (!isOccupied(game, cid)) sum += countyLevy(game, cid);
  return sum * (1 + stat(game, c, 'levy_mult')) * c.levyRatio;
}

/** Всё ополчение державы: свой домен + доля вассалов (рекурсивно) + бонусы. */
export function realmLevy(game: Game, c: Character, depth = 0): number {
  if (depth > 10) return 0;
  const key = `rlevy:${c.id}`;
  const cached = game.dayCache.get(key) as number | undefined;
  if (cached !== undefined) return cached;
  const v = computeRealmLevy(game, c, depth);
  game.dayCache.set(key, v);
  return v;
}

function computeRealmLevy(game: Game, c: Character, depth: number): number {
  const share = (econ(game).vassal_levy_share ?? 0.35) * Math.max(0, 1 + stat(game, c, 'vassal_levy_mult'));
  let sum = domainLevy(game, c) + stat(game, c, 'levy_flat');
  for (const v of game.vassalsOf(c.id)) if (!inRevolt(game, v.id, c.id)) sum += realmLevy(game, v, depth + 1) * share;
  return Math.round(sum);
}

/** Вассал воюет против своего сюзерена (мятеж): не платит налогов и не даёт войск. */
export function inRevolt(game: Game, vassal: string, liege: string): boolean {
  for (const w of Object.values(game.state.wars)) {
    if ((w.attackers.includes(vassal) && w.defenders.includes(liege)) || (w.defenders.includes(vassal) && w.attackers.includes(liege))) return true;
  }
  return false;
}

/** Приблизительная «военная сила» для ИИ: ополчение + уже поднятые армии. */
export function militaryStrength(game: Game, c: Character): number {
  return game.cachedDaily(`milstr:${c.id}`, () => computeMilitaryStrength(game, c));
}

function computeMilitaryStrength(game: Game, c: Character): number {
  let raised = 0;
  for (const a of Object.values(game.state.armies)) {
    if (a.owner !== c.id) continue;
    raised += a.size;
    for (const b of game.engine.hooks.collect<number>('army.power_bonus', { game, army: a, enemies: [], location: a.location })) raised += b;
  }
  let extra = 0;
  for (const b of game.engine.hooks.collect<number>('military.strength_bonus', { game, character: c })) extra += b;
  return (raised > 0 ? raised : realmLevy(game, c)) + extra;
}

/** Причины, по которым персонаж не может заплатить цену (пусто — может). Нулевая цена всегда доступна. */
export function costBlockers(game: Game, c: Character, cost: { gold?: number; prestige?: number; piety?: number }): string[] {
  const out: string[] = [];
  if ((cost.gold ?? 0) > 0 && c.gold < cost.gold!) out.push(game.loc.t('ui.need_gold', { value: cost.gold }));
  if ((cost.prestige ?? 0) > 0 && c.prestige < cost.prestige!) out.push(game.loc.t('ui.need_prestige', { value: cost.prestige }));
  if ((cost.piety ?? 0) > 0 && c.piety < cost.piety!) out.push(game.loc.t('ui.need_piety', { value: cost.piety }));
  return out;
}
