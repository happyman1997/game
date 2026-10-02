import type { InteractionDef } from '../content/defs';
import { durationDays } from '../core/date';
import type { TextValue } from '../core/localization';
import type { Game } from '../game';
import { type ScriptContext, makeContext } from '../script/context';
import { evalTrigger, evalValue, failedTriggers, runEffect } from '../script/interpreter';
import type { Character, ScopeRef } from '../types';
import { isAlive } from './characters';
import { startScheme } from './schemes';
import { costBlockers } from './economy';

/**
 * Взаимодействия персонажей (брак, подарок, вассалитет, интриги...).
 * Полностью описываются в данных: условия показа/доступности, цена,
 * согласие ИИ (ai_accept со слагаемыми desc для подсказки), эффекты.
 */
export interface InteractionOption {
  id: string;
  label: string;
  ref?: ScopeRef;
}

export interface InteractionTargetProvider {
  label?: TextValue;
  options(game: Game, actor: Character, recipient: Character): InteractionOption[];
}

/** Кто принимает решение по взаимодействию (поле decider в данных). */
export interface InteractionDecider {
  decider(game: Game, recipient: Character, actor?: Character): Character | undefined;
}

export interface InteractionArgs {
  secondary?: string;
  target?: ScopeRef;
}

export function interactionContext(game: Game, def: InteractionDef, actor: Character, recipient: Character, args: InteractionArgs = {}): ScriptContext {
  const scopes: Record<string, ScopeRef> = {
    actor: { type: 'character', id: actor.id },
    recipient: { type: 'character', id: recipient.id },
    decider: { type: 'character', id: deciderOf(game, def, recipient).id },
  };
  if (args.secondary) scopes.secondary_actor = { type: 'character', id: args.secondary };
  if (args.target) scopes.target = args.target;
  const ctx = makeContext(game, scopes.actor, scopes);
  return ctx;
}

/** Кто принимает решение: сам получатель или (decider: guardian) его опекун-сюзерен. */
export function deciderOf(game: Game, def: InteractionDef, recipient: Character): Character {
  if (!def.decider || def.decider === 'recipient') return recipient;
  if (def.decider === 'guardian') {
    if (!recipient.titles.length && recipient.liege) {
      const g = game.char(recipient.liege);
      if (g && isAlive(g)) return g;
    }
    return recipient;
  }
  const d = game.engine.registries.interactionDeciders.get(def.decider)?.decider(game, recipient);
  return d && isAlive(d) ? d : recipient;
}

export function interactionDefs(game: Game): InteractionDef[] {
  return game.content.all<InteractionDef>('interactions');
}

export function isInteractionShown(game: Game, def: InteractionDef, actor: Character, recipient: Character): boolean {
  if (!isAlive(actor) || !isAlive(recipient)) return false;
  if (def.self ? actor.id !== recipient.id : actor.id === recipient.id) return false;
  // Пленники ничего не предпринимают; с пленником доступны только взаимодействия с prisoner: only/allowed.
  if (actor.prison) return false;
  const mode = def.prisoner ?? 'never';
  if (recipient.prison ? mode === 'never' : mode === 'only') return false;
  const ctx = interactionContext(game, def, actor, recipient);
  return evalTrigger(ctx, ctx.root, def.is_shown);
}

function cooldownKey(def: InteractionDef, recipient: Character) {
  return `ia:${def.id}:${recipient.id}`;
}

export function interactionCost(game: Game, def: InteractionDef, ctx: ScriptContext) {
  return {
    gold: Math.round(evalValue(ctx, ctx.root, def.cost?.gold ?? 0)),
    prestige: Math.round(evalValue(ctx, ctx.root, def.cost?.prestige ?? 0)),
    piety: Math.round(evalValue(ctx, ctx.root, def.cost?.piety ?? 0)),
  };
}

export function secondaryCandidates(game: Game, def: InteractionDef, actor: Character, recipient: Character): Character[] {
  if (!def.secondary_actor) return [];
  const lists = Array.isArray(def.secondary_actor.list) ? def.secondary_actor.list : [def.secondary_actor.list];
  const ctx = interactionContext(game, def, actor, recipient);
  const seen = new Set<string>();
  const out: Character[] = [];
  for (const name of lists) {
    const list = game.engine.script.lists.get(name);
    if (!list) {
      game.scriptError(`Взаимодействие ${def.id}: нет списка "${name}"`);
      continue;
    }
    for (const ref of list.list(ctx, ctx.root)) {
      if (ref.type !== 'character' || seen.has(ref.id)) continue;
      seen.add(ref.id);
      const c = game.char(ref.id);
      if (!c || !isAlive(c)) continue;
      const sctx = interactionContext(game, def, actor, recipient, { secondary: c.id });
      if (evalTrigger(sctx, { type: 'character', id: c.id }, def.secondary_actor.trigger)) out.push(c);
    }
  }
  return out;
}

export function targetOptions(game: Game, def: InteractionDef, actor: Character, recipient: Character): InteractionOption[] {
  if (!def.target) return [];
  const p = game.engine.registries.interactionTargets.get(def.target.provider);
  if (!p) {
    game.scriptError(`Взаимодействие ${def.id}: нет поставщика целей "${def.target.provider}"`);
    return [];
  }
  return p.options(game, actor, recipient);
}

/** Причины, по которым взаимодействие сейчас недоступно (пусто — доступно). */
export function interactionBlockers(game: Game, def: InteractionDef, actor: Character, recipient: Character, args: InteractionArgs = {}): string[] {
  const ctx = interactionContext(game, def, actor, recipient, args);
  const out = failedTriggers(ctx, ctx.root, def.is_valid);
  const cost = interactionCost(game, def, ctx);
  out.push(...costBlockers(game, actor, cost));
  const cd = actor.flags[cooldownKey(def, recipient)];
  if (cd && cd > game.date) out.push(game.loc.t('ui.on_cooldown', { days: cd - game.date }));
  if (def.secondary_actor && !args.secondary && secondaryCandidates(game, def, actor, recipient).length === 0)
    out.push(game.loc.t('ui.no_candidates'));
  if (def.target && !args.target && targetOptions(game, def, actor, recipient).length === 0) out.push(game.loc.t('ui.no_targets'));
  if (def.scheme) {
    const dup = Object.values(game.state.schemes).some((s) => s.owner === actor.id && s.type === def.scheme && s.target === recipient.id);
    if (dup) out.push(game.loc.t('ui.scheme_exists'));
  }
  return out;
}

export function isAutoAccept(game: Game, def: InteractionDef, ctx: ScriptContext, actor: Character, recipient: Character): boolean {
  if (def.scheme) return true;
  if (actor.id === recipient.id || ctx.scopes.decider?.id === actor.id) return true;
  if (def.auto_accept === true || def.auto_accept === 'yes') return true;
  if (def.auto_accept && typeof def.auto_accept === 'object') return evalTrigger(ctx, ctx.root, def.auto_accept);
  return def.ai_accept == null;
}

export function acceptance(game: Game, def: InteractionDef, actor: Character, recipient: Character, args: InteractionArgs = {}) {
  const ctx = interactionContext(game, def, actor, recipient, args);
  if (isAutoAccept(game, def, ctx, actor, recipient)) return { auto: true, total: 1, parts: [] as { label: string; value: number }[] };
  const parts: { label: string; value: number }[] = [];
  const total = evalValue(ctx, ctx.scopes.decider, def.ai_accept, parts);
  return { auto: false, total, parts };
}

export type InteractionResult = 'accepted' | 'declined' | 'pending' | 'invalid' | 'scheme';

export function executeInteraction(game: Game, def: InteractionDef, actor: Character, recipient: Character, args: InteractionArgs = {}): InteractionResult {
  if (!isInteractionShown(game, def, actor, recipient)) return 'invalid';
  if (interactionBlockers(game, def, actor, recipient, args).length) return 'invalid';
  if (!game.engine.hooks.veto('interaction.before', { game, interaction: def.id, actor, recipient, args })) return 'invalid';
  const ctx = interactionContext(game, def, actor, recipient, args);
  const cost = interactionCost(game, def, ctx);
  actor.gold -= cost.gold;
  actor.prestige -= cost.prestige;
  actor.piety -= cost.piety;
  if (def.cooldown) actor.flags[cooldownKey(def, recipient)] = game.date + durationDays(def.cooldown);

  if (def.scheme) {
    const s = startScheme(game, def.scheme, actor, recipient);
    if (s) runEffect(ctx, ctx.root, def.on_accept);
    return s ? 'scheme' : 'invalid';
  }
  if (isAutoAccept(game, def, ctx, actor, recipient)) {
    runEffect(ctx, ctx.root, def.on_accept);
    game.emit('interaction', { interaction: def.id, actor: actor.id, recipient: recipient.id, accepted: true });
    return 'accepted';
  }
  if (game.isPlayer(deciderOf(game, def, recipient).id)) {
    game.state.pendingRequests.push({
      uid: game.newId('rq'),
      interaction: def.id,
      actor: actor.id,
      recipient: recipient.id,
      secondary: args.secondary,
      target: args.target,
    });
    game.notify('event');
    return 'pending';
  }
  const acc = acceptance(game, def, actor, recipient, args);
  const ok = acc.total > 0;
  runEffect(ctx, ctx.root, ok ? def.on_accept : def.on_decline);
  if (game.isPlayer(actor.id)) {
    game.message(
      game.text(ok ? (def.accept_text ?? 'msg.interaction_accepted') : (def.decline_text ?? 'msg.interaction_declined'), ctx, {
        who: game.scopeName({ type: 'character', id: recipient.id }),
        what: game.nameOf('interactions', def.id),
      }),
      ok ? 'good' : 'bad',
      { type: 'character', id: recipient.id },
    );
  }
  game.emit('interaction', { interaction: def.id, actor: actor.id, recipient: recipient.id, accepted: ok });
  return ok ? 'accepted' : 'declined';
}

/** Игрок ответил на предложение ИИ. */
export function resolveRequest(game: Game, uid: string, accept: boolean): void {
  const i = game.state.pendingRequests.findIndex((r) => r.uid === uid);
  if (i < 0) return;
  const r = game.state.pendingRequests[i];
  game.state.pendingRequests.splice(i, 1);
  const def = game.content.get<InteractionDef>('interactions', r.interaction);
  const actor = game.char(r.actor);
  const recipient = game.char(r.recipient);
  if (!def || !isAlive(actor) || !isAlive(recipient)) return;
  if (r.secondary && !game.isAlive(r.secondary)) return;
  const ctx = interactionContext(game, def, actor, recipient, { secondary: r.secondary, target: r.target });
  if (accept && failedTriggers(ctx, ctx.root, def.is_valid).length) return;
  runEffect(ctx, ctx.root, accept ? def.on_accept : def.on_decline);
  game.emit('interaction', { interaction: def.id, actor: actor.id, recipient: recipient.id, accepted: accept });
  game.notify('event');
}
