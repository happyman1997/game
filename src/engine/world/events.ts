import type { EventDef, EventOptionDef, OnActionDef } from '../content/defs';
import { durationDays } from '../core/date';
import { isPlainObject } from '../core/merge';
import type { Game } from '../game';
import { type ScriptContext, makeContext } from '../script/context';
import { evalTrigger, evalValue, runEffect } from '../script/interpreter';
import type { PendingEvent, ScopeRef } from '../types';

/**
 * Исполнение событий из данных. Событие адресовано персонажу (root).
 * Для игрока событие ставится в очередь и показывается окном; ИИ выбирает
 * вариант по весам ai_chance.
 */
export class EventRuntime {
  constructor(private game: Game) {}

  def(id: string): EventDef | undefined {
    return this.game.content.get<EventDef>('events', id);
  }

  /** Запустить событие сейчас или через delayDays. */
  trigger(id: string, target: ScopeRef, scopes: Record<string, ScopeRef> = {}, delayDays = 0): void {
    if (delayDays > 0) {
      this.game.state.scheduled.push({ date: this.game.date + delayDays, event: id, target, scopes: { ...scopes } });
      return;
    }
    this.fire(id, target, scopes);
  }

  private cooldownKey(id: string) {
    return `ev:${id}`;
  }

  canFire(def: EventDef, target: ScopeRef, ctx: ScriptContext): boolean {
    const game = this.game;
    if (target.type === 'character') {
      const c = game.char(target.id);
      if (!c || c.death !== undefined) return false;
      const until = c.flags[this.cooldownKey(def.id)];
      if (until !== undefined && (until === 0 || until > game.date)) return false;
    }
    return evalTrigger(ctx, target, def.trigger);
  }

  /** Возвращает true, если событие сработало. */
  fire(id: string, target: ScopeRef, scopes: Record<string, ScopeRef> = {}, opts: { force?: boolean } = {}): boolean {
    const game = this.game;
    const def = this.def(id);
    if (!def) {
      game.scriptError(`Нет события "${id}"`);
      return false;
    }
    const ctx = makeContext(game, target, scopes);
    if (!opts.force && !this.canFire(def, target, ctx)) return false;
    if (!game.engine.hooks.veto('event.before_fire', { game, event: id, target, scopes })) return false;
    if (target.type === 'character') {
      const c = game.char(target.id)!;
      if (def.once) c.flags[this.cooldownKey(id)] = 0;
      else if (def.cooldown) c.flags[this.cooldownKey(id)] = game.date + durationDays(def.cooldown);
    }
    runEffect(ctx, target, def.immediate);
    const opts2 = this.visibleOptions(def, ctx, target);
    if (def.hidden || !def.options?.length) {
      runEffect(ctx, target, def.after);
      game.emit('event.fired', { event: id, target });
      return true;
    }
    if (target.type === 'character' && game.isPlayer(target.id)) {
      const pe: PendingEvent = { uid: game.newId('ev'), event: id, target, scopes: { ...ctx.scopes } };
      game.state.pendingEvents.push(pe);
      game.emit('event.player', { pending: pe });
      game.notify('event');
      return true;
    }
    // ИИ
    const pick = game.rng.weighted(opts2, (o) => Math.max(0, evalValue(ctx, target, o.opt.ai_chance ?? 1)));
    const chosen = pick ?? opts2[0];
    if (chosen) runEffect(ctx, target, chosen.opt.effect);
    runEffect(ctx, target, def.after);
    game.emit('event.fired', { event: id, target, option: chosen?.index });
    return true;
  }

  visibleOptions(def: EventDef, ctx: ScriptContext, target: ScopeRef): { opt: EventOptionDef; index: number }[] {
    return (def.options ?? []).map((opt, index) => ({ opt, index })).filter(({ opt }) => evalTrigger(ctx, target, opt.trigger));
  }

  contextFor(pe: PendingEvent): ScriptContext {
    return makeContext(this.game, pe.target, pe.scopes);
  }

  /** Игрок выбрал вариант события. */
  choose(uid: string, optionIndex: number): void {
    const game = this.game;
    const i = game.state.pendingEvents.findIndex((p) => p.uid === uid);
    if (i < 0) return;
    const pe = game.state.pendingEvents[i];
    game.state.pendingEvents.splice(i, 1);
    const def = this.def(pe.event);
    if (!def) return;
    const ctx = this.contextFor(pe);
    if (!game.exists(pe.target)) return;
    const opt = def.options?.[optionIndex];
    if (opt) runEffect(ctx, pe.target, opt.effect);
    runEffect(ctx, pe.target, def.after);
    game.emit('event.fired', { event: pe.event, target: pe.target, option: optionIndex });
    game.notify('event');
  }

  /** Ежедневно: отложенные события. */
  processScheduled(): void {
    const game = this.game;
    const due = game.state.scheduled.filter((s) => s.date <= game.date);
    if (!due.length) return;
    game.state.scheduled = game.state.scheduled.filter((s) => s.date > game.date);
    for (const s of due) this.fire(s.event, s.target, s.scopes);
  }

  /** Выполнить on_action из данных: эффект, обязательные события и случайное событие. */
  runOnAction(id: string, root: ScopeRef, scopes: Record<string, ScopeRef>): void {
    const game = this.game;
    const def = game.content.get<OnActionDef>('on_actions', id);
    if (!def) return;
    if (root.type === 'character' && game.char(root.id)?.death !== undefined && id !== 'on_death') return;
    const ctx = makeContext(game, root, scopes);
    runEffect(ctx, root, def.effect);
    for (const ev of def.events ?? []) this.fire(ev, root, ctx.scopes);
    const re = def.random_events;
    if (re) {
      const chance = re.chance == null ? 100 : evalValue(ctx, root, re.chance);
      if (game.rng.next() * 100 >= chance) return;
      const entries: { event: string; weight: unknown }[] = Array.isArray(re.events)
        ? re.events.map((e) => ({ event: e.event, weight: e.weight ?? 1 }))
        : isPlainObject(re.events)
          ? Object.entries(re.events).map(([event, weight]) => ({ event, weight }))
          : [];
      const candidates: { event: string; w: number }[] = [];
      for (const e of entries) {
        const ed = this.def(e.event);
        if (!ed) {
          game.scriptError(`on_action ${id}: нет события "${e.event}"`);
          continue;
        }
        const evCtx = makeContext(game, root, ctx.scopes);
        if (!this.canFire(ed, root, evCtx)) continue;
        const w = evalValue(evCtx, root, e.weight) * (ed.weight != null ? evalValue(evCtx, root, ed.weight) : 1);
        if (w > 0) candidates.push({ event: e.event, w });
      }
      const pick = game.rng.weighted(candidates, (c) => c.w);
      if (pick) this.fire(pick.event, root, ctx.scopes);
    }
  }
}
