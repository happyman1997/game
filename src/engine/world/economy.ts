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
  for (const a of Object.values(game.state.armies)) if (a.owner === c.id) men += a.size;
  return (men / 100) * per100;
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
  for (const v of game.vassalsOf(c.id)) fromVassals += domainTax(game, v) * share;
  if (fromVassals) parts.push({ label: game.loc.t('ui.vassal_tax'), value: fromVassals });
  if (c.liege) parts.push({ label: game.loc.t('ui.liege_tax'), value: -dom * share });
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
  const share = econ(game).vassal_levy_share ?? 0.35;
  let sum = domainLevy(game, c) + stat(game, c, 'levy_flat');
  for (const v of game.vassalsOf(c.id)) sum += realmLevy(game, v, depth + 1) * share;
  return Math.round(sum);
}

/** Приблизительная «военная сила» для ИИ: ополчение + уже поднятые армии. */
export function militaryStrength(game: Game, c: Character): number {
  let raised = 0;
  for (const a of Object.values(game.state.armies)) if (a.owner === c.id) raised += a.size;
  return raised > 0 ? raised : realmLevy(game, c);
}
