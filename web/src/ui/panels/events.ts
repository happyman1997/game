import type { EventDef, InteractionDef } from '../../engine/content/defs';
import { makeContext } from '../../engine/script/context';
import { describeEffect, evalTrigger } from '../../engine/script/interpreter';
import type { PendingEvent, PendingRequest } from '../../engine/types';
import { interactionContext, resolveRequest } from '../../engine/world/interactions';
import type { App } from '../app';
import { esc, h } from '../dom';
import { button, charLink, descLinesHtml, portrait } from '../widgets';

const LETTERS = 'abcdefghij';

/** Окно события с вариантами; подсказка варианта показывает его последствия. */
export function renderEventModal(app: App, pe: PendingEvent, onClose: () => void): HTMLElement {
  const g = app.game!;
  const def = g.content.get<EventDef>('events', pe.event);
  if (!def) {
    g.state.pendingEvents = g.state.pendingEvents.filter((p) => p.uid !== pe.uid);
    onClose();
    return h('div');
  }
  const ctx = g.events.contextFor(pe);
  const theme = g.content.get('event_themes', def.theme ?? 'default') ?? g.content.get('event_themes', 'default');
  const title = g.text(def.title ?? `ev.${def.id}.t`, ctx);
  let descRaw: any = def.desc ?? `ev.${def.id}.desc`;
  if (Array.isArray(descRaw)) {
    const hit = descRaw.find((d: any) => evalTrigger(ctx, ctx.root, d.trigger));
    descRaw = hit?.desc ?? '';
  }
  const desc = g.text(descRaw, ctx);
  const people = Object.entries(pe.scopes).filter(([, r]) => r.type === 'character' && r.id !== pe.target.id && g.char(r.id)).slice(0, 2);
  const root = h('div', { class: 'event', style: { '--theme': theme?.color ?? '#8a6d3b' } as any },
    h('div', { class: 'event-banner' }, h('span', { class: 'event-icon' }, def.icon ?? theme?.icon ?? '📜'), h('h2', null, title)),
    h('div', { class: 'event-people' },
      g.char(pe.target.id) ? portrait(app, g.char(pe.target.id)!, 64, false) : null,
      ...people.map(([, r]) => h('div', { class: 'event-person' }, portrait(app, g.char(r.id)!, 64, false), h('div', { class: 'small' }, charLink(app, r.id)))),
    ),
    h('p', { class: 'event-desc' }, desc),
  );
  const opts = g.events.visibleOptions(def, ctx, pe.target);
  const list = h('div', { class: 'event-options' });
  for (const { opt, index } of opts) {
    const label = g.text(opt.name ?? `ev.${def.id}.${LETTERS[index]}`, ctx);
    list.append(button(label, () => {
      g.events.choose(pe.uid, index);
      onClose();
      app.markDirty(true);
    }, {
      cls: 'event-option',
      tip: () => {
        const c2 = makeContext(g, pe.target, pe.scopes);
        const lines = describeEffect(c2, pe.target, opt.effect);
        const extra = opt.tooltip ? `<p>${esc(g.text(opt.tooltip, c2))}</p>` : '';
        return lines.length || extra ? `${extra}${descLinesHtml(lines)}` : '';
      },
    }));
  }
  if (!opts.length) list.append(button('OK', () => { g.events.choose(pe.uid, -1); onClose(); }));
  root.append(list);
  return root;
}

/** Предложение от ИИ игроку (брак, вассалитет...). */
export function renderRequestModal(app: App, rq: PendingRequest, onClose: () => void): HTMLElement {
  const g = app.game!;
  const def = g.content.get<InteractionDef>('interactions', rq.interaction);
  const actor = g.char(rq.actor);
  const recipient = g.char(rq.recipient);
  if (!def || !actor || !recipient) {
    resolveRequest(g, rq.uid, false);
    onClose();
    return h('div');
  }
  const ctx = interactionContext(g, def, actor, recipient, { secondary: rq.secondary, target: rq.target });
  const lines = describeEffect(ctx, ctx.root, def.on_accept);
  const root = h('div', { class: 'event', style: { '--theme': '#6a5a2a' } as any },
    h('div', { class: 'event-banner' }, h('span', { class: 'event-icon' }, def.icon ?? '✉'), h('h2', null, g.nameOf('interactions', def.id))),
    h('div', { class: 'event-people' }, portrait(app, actor, 64, false), rq.secondary && g.char(rq.secondary) ? portrait(app, g.char(rq.secondary)!, 64, false) : null, portrait(app, recipient, 64, false)),
    h('p', { class: 'event-desc' }, app.t('ui.request_text', { who: app.rankedName(actor.id), what: g.nameOf('interactions', def.id) })),
    h('div', { class: 'ia-effects', html: descLinesHtml(lines) }),
    h('div', { class: 'event-options' },
      button(app.t('ui.accept'), () => { resolveRequest(g, rq.uid, true); onClose(); app.markDirty(true); }, { cls: 'event-option' }),
      button(app.t('ui.decline'), () => { resolveRequest(g, rq.uid, false); onClose(); app.markDirty(true); }, { cls: 'event-option' }),
    ),
  );
  return root;
}
