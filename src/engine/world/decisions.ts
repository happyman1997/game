import type { BuildingDef, DecisionDef } from '../content/defs';
import { durationDays } from '../core/date';
import type { Game } from '../game';
import { type ScriptContext, makeContext } from '../script/context';
import { evalTrigger, evalValue, failedTriggers, runEffect } from '../script/interpreter';
import type { Character } from '../types';
import { domainCounties } from './titles';

// ------------------------------------------------------------ решения

export function decisionContext(game: Game, c: Character): ScriptContext {
  return makeContext(game, { type: 'character', id: c.id }, { actor: { type: 'character', id: c.id } });
}

export function decisionCost(game: Game, def: DecisionDef, c: Character) {
  const ctx = decisionContext(game, c);
  return {
    gold: Math.round(evalValue(ctx, ctx.root, def.cost?.gold ?? 0)),
    prestige: Math.round(evalValue(ctx, ctx.root, def.cost?.prestige ?? 0)),
    piety: Math.round(evalValue(ctx, ctx.root, def.cost?.piety ?? 0)),
  };
}

export function isDecisionShown(game: Game, def: DecisionDef, c: Character): boolean {
  const ctx = decisionContext(game, c);
  return evalTrigger(ctx, ctx.root, def.is_shown);
}

export function decisionBlockers(game: Game, def: DecisionDef, c: Character): string[] {
  const ctx = decisionContext(game, c);
  const out = failedTriggers(ctx, ctx.root, def.is_valid);
  const cost = decisionCost(game, def, c);
  if (c.gold < cost.gold) out.push(game.loc.t('ui.need_gold', { value: cost.gold }));
  if (c.prestige < cost.prestige) out.push(game.loc.t('ui.need_prestige', { value: cost.prestige }));
  if (c.piety < cost.piety) out.push(game.loc.t('ui.need_piety', { value: cost.piety }));
  const cd = c.flags[`dec:${def.id}`];
  if (cd !== undefined && (cd === 0 || cd > game.date)) out.push(game.loc.t('ui.on_cooldown', { days: cd === 0 ? '∞' : cd - game.date }));
  return out;
}

export function takeDecision(game: Game, def: DecisionDef, c: Character): boolean {
  if (!isDecisionShown(game, def, c) || decisionBlockers(game, def, c).length) return false;
  if (!game.engine.hooks.veto('decision.before', { game, decision: def.id, character: c })) return false;
  const cost = decisionCost(game, def, c);
  c.gold -= cost.gold;
  c.prestige -= cost.prestige;
  c.piety -= cost.piety;
  if (def.cooldown) c.flags[`dec:${def.id}`] = game.date + durationDays(def.cooldown);
  const ctx = decisionContext(game, c);
  runEffect(ctx, ctx.root, def.effect);
  game.emit('decision.taken', { decision: def.id, character: c.id });
  return true;
}

// ------------------------------------------------------------ постройки

export function buildingSlots(game: Game, provId: string): number {
  const def = game.content.get('provinces', provId);
  return (def?.holdings?.length ?? 1) * (game.defines.buildings?.slots_per_holding ?? 2);
}

export function buildingCandidates(game: Game, c: Character, provId: string): { def: BuildingDef; blockers: string[] }[] {
  const p = game.state.provinces[provId];
  const pdef = game.content.get('provinces', provId);
  if (!p || !pdef) return [];
  const out: { def: BuildingDef; blockers: string[] }[] = [];
  const full = p.buildings.length >= buildingSlots(game, provId);
  for (const b of game.content.all<BuildingDef>('buildings')) {
    if (p.buildings.includes(b.id)) continue;
    if (b.holding && !pdef.holdings.includes(b.holding)) continue;
    if ((b.requires ?? []).some((r) => !p.buildings.includes(r))) continue;
    const blockers: string[] = [];
    if (game.state.titles[provId]?.holder !== c.id) blockers.push(game.loc.t('ui.not_your_domain'));
    if (p.construction) blockers.push(game.loc.t('ui.already_building'));
    if (p.occupant) blockers.push(game.loc.t('ui.occupied'));
    if (full) blockers.push(game.loc.t('ui.no_slots'));
    const ctx = makeContext(game, { type: 'province', id: provId }, { builder: { type: 'character', id: c.id } });
    blockers.push(...failedTriggers(ctx, ctx.root, b.trigger));
    const cost = buildingCost(game, b, c, provId);
    if (c.gold < cost.gold) blockers.push(game.loc.t('ui.need_gold', { value: cost.gold }));
    if (c.prestige < cost.prestige) blockers.push(game.loc.t('ui.need_prestige', { value: cost.prestige }));
    out.push({ def: b, blockers });
  }
  return out;
}

export function buildingCost(game: Game, b: BuildingDef, c: Character, provId: string) {
  const ctx = makeContext(game, { type: 'province', id: provId }, { builder: { type: 'character', id: c.id } });
  return {
    gold: Math.round(evalValue(ctx, ctx.root, b.cost?.gold ?? 0)),
    prestige: Math.round(evalValue(ctx, ctx.root, b.cost?.prestige ?? 0)),
  };
}

export function startBuilding(game: Game, c: Character, provId: string, buildingId: string): boolean {
  const cand = buildingCandidates(game, c, provId).find((x) => x.def.id === buildingId);
  if (!cand || cand.blockers.length) return false;
  const cost = buildingCost(game, cand.def, c, provId);
  c.gold -= cost.gold;
  c.prestige -= cost.prestige;
  game.state.provinces[provId].construction = { building: buildingId, done: game.date + cand.def.days, by: c.id };
  game.emit('building.started', { province: provId, building: buildingId, by: c.id });
  return true;
}

export function dailyConstruction(game: Game): void {
  for (const p of Object.values(game.state.provinces)) {
    if (!p.construction || p.construction.done > game.date) continue;
    const b = p.construction.building;
    p.buildings.push(b);
    p.construction = undefined;
    game.statCache.clear();
    const holder = game.state.titles[p.id]?.holder;
    game.message(
      game.loc.t('msg.building_done', { building: game.nameOf('buildings', b), place: game.nameOf('provinces', p.id) }),
      'good',
      { type: 'province', id: p.id },
      [holder],
    );
    game.emit('building.completed', { province: p.id, building: b });
  }
}

export function domainBuildOptions(game: Game, c: Character) {
  return domainCounties(game, c).flatMap((p) =>
    buildingCandidates(game, c, p)
      .filter((x) => !x.blockers.length)
      .map((x) => ({ province: p, def: x.def })),
  );
}
