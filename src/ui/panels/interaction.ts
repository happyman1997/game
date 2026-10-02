import type { InteractionDef } from '../../engine/content/defs';
import { describeEffect } from '../../engine/script/interpreter';
import type { ScopeRef } from '../../engine/types';
import { ageOf, charFullName } from '../../engine/world/characters';
import {
  acceptance,
  executeInteraction,
  interactionBlockers,
  interactionContext,
  interactionCost,
  secondaryCandidates,
  targetOptions,
} from '../../engine/world/interactions';
import { schemeContext } from '../../engine/world/schemes';
import type { App } from '../app';
import { clear, esc, h, signed } from '../dom';
import { breakdownHtml, button, costText, descLinesHtml, portrait } from '../widgets';

/** Окно взаимодействия: выбор кандидата/цели, прогноз согласия, отправка. */
export function openInteraction(app: App, def: InteractionDef, actorId: string, recipientId: string) {
  const g = app.game!;
  let secondary: string | undefined;
  let target: ScopeRef | undefined;
  const body = h('div', { class: 'interaction' });
  let close: () => void = () => {};

  const render = () => {
    clear(body);
    const actor = g.char(actorId)!;
    const recipient = g.char(recipientId)!;
    body.append(
      h('div', { class: 'ia-head' },
        portrait(app, actor, 56, false),
        h('div', { class: 'ia-title' }, h('h3', null, `${def.icon ?? ''} ${g.nameOf('interactions', def.id)}`), h('div', { class: 'muted' }, g.descOf('interactions', def.id))),
        portrait(app, recipient, 56, false),
      ),
    );
    if (def.secondary_actor) {
      const cands = secondaryCandidates(g, def, actor, recipient);
      if (!secondary && cands.length === 1) secondary = cands[0].id;
      body.append(h('div', { class: 'ia-sub' }, g.text(def.secondary_actor.title ?? 'ui.choose_candidate')));
      const list = h('div', { class: 'cand-list' });
      for (const c of cands) {
        const acc = acceptance(g, def, actor, recipient, { secondary: c.id, target });
        list.append(h('div', { class: ['cand', secondary === c.id && 'selected'], onclick: () => { secondary = c.id; render(); } },
          portrait(app, c, 36, false),
          h('div', null, h('div', null, charFullName(g, c, true)), h('div', { class: 'muted' }, app.t('ui.age_n', { n: ageOf(g, c) }))),
          acc.auto ? null : h('span', { class: acc.total > 0 ? 'good' : 'bad' }, signed(acc.total)),
        ));
      }
      if (!cands.length) list.append(h('div', { class: 'muted' }, app.t('ui.no_candidates')));
      body.append(list);
    }
    if (def.target) {
      const opts = targetOptions(g, def, actor, recipient);
      if (!target && opts.length === 1) target = opts[0].ref;
      body.append(h('div', { class: 'ia-sub' }, g.text(def.target.title ?? 'ui.choose_target')));
      const list = h('div', { class: 'cand-list' });
      for (const o of opts) {
        list.append(h('div', { class: ['cand', target?.id === o.ref?.id && 'selected'], onclick: () => { target = o.ref; render(); } }, o.label));
      }
      body.append(list);
    }
    const args = { secondary, target };
    const ctx = interactionContext(g, def, actor, recipient, args);
    const cost = interactionCost(g, def, ctx);
    body.append(h('div', { class: 'ia-cost' }, `${app.t('ui.cost')}: ${costText(app, cost)}`));
    const ready = (!def.secondary_actor || secondary) && (!def.target || target);
    if (ready) {
      if (def.scheme) {
        const tmp = { id: 'preview', type: def.scheme, owner: actor.id, target: recipient.id, progress: 0, start: g.date, discovered: false };
        const sdef = g.content.get('schemes', def.scheme);
        const sctx = schemeContext(g, tmp);
        body.append(h('div', { class: 'ia-effects', html: `<div class="tip-title">${esc(app.t('ui.on_success'))}</div>${descLinesHtml(describeEffect(sctx, sctx.root, sdef?.on_success))}` }));
      } else {
        const acc = acceptance(g, def, actor, recipient, args);
        if (!acc.auto) {
          body.append(h('div', { class: ['ia-accept', acc.total > 0 ? 'good' : 'bad'] },
            h('div', { class: 'tip-title' }, `${app.t(acc.total > 0 ? 'ui.will_accept' : 'ui.will_decline')} (${signed(acc.total)})`),
            h('div', { html: breakdownHtml(acc.parts) })));
        }
        const lines = describeEffect(ctx, ctx.root, def.on_accept);
        if (lines.length) body.append(h('div', { class: 'ia-effects', html: `<div class="tip-title">${esc(app.t('ui.effects'))}</div>${descLinesHtml(lines)}` }));
      }
    }
    const blockers = ready ? interactionBlockers(g, def, actor, recipient, args) : [];
    if (blockers.length) body.append(h('div', { class: 'tip-bad' }, ...blockers.map((b) => h('div', null, `✗ ${b}`))));
    body.append(h('div', { class: 'modal-buttons' },
      button(app.t(def.scheme ? 'ui.start_scheme' : 'ui.send'), () => {
        const res = executeInteraction(g, def, actor, recipient, args);
        close();
        app.toast(app.t(`ui.ia_result.${res}`), res === 'accepted' || res === 'scheme' ? 'good' : res === 'declined' || res === 'invalid' ? 'bad' : 'info');
        app.markDirty(true);
      }, { disabled: !ready || blockers.length > 0, cls: 'btn-gold' }),
      button(app.t('ui.cancel'), () => close()),
    ));
  };
  render();
  close = app.modal(body, { cls: 'ia-modal' });
}
