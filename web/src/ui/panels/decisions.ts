import type { DecisionDef } from '../../engine/content/defs';
import { decisionBlockers, decisionCost, isDecisionShown, takeDecision } from '../../engine/world/decisions';
import type { App } from '../app';
import { esc, h } from '../dom';
import { button, costText, effectTooltip, reasonsHtml } from '../widgets';

export function renderDecisionsPanel(app: App): HTMLElement {
  const g = app.game!;
  const p = g.player!;
  const root = h('div', { class: 'decisions-panel' });
  const defs = g.content.all<DecisionDef>('decisions').filter((d) => isDecisionShown(g, d, p));
  defs.sort((a, b) => Number(!!b.major) - Number(!!a.major));
  for (const d of defs) {
    const blockers = decisionBlockers(g, d, p);
    const cost = decisionCost(g, d, p);
    root.append(h('div', { class: ['decision', d.major && 'major', blockers.length && 'blocked'] },
      h('div', { class: 'dec-title' }, `${d.icon ?? '📜'} ${g.nameOf('decisions', d.id)}`),
      h('div', { class: 'muted' }, g.descOf('decisions', d.id)),
      h('div', { class: 'dec-foot' },
        h('span', null, costText(app, cost)),
        button(app.t('ui.take_decision'), () => {
          if (takeDecision(g, d, p)) app.toast(g.nameOf('decisions', d.id), 'good');
          app.markDirty(true);
        }, {
          disabled: blockers.length > 0,
          cls: 'btn-gold btn-small',
          tip: () => `${effectTooltip(app, d.effect, { type: 'character', id: p.id }, { actor: { type: 'character', id: p.id } }, app.t('ui.effects'))}${reasonsHtml(app, blockers)}`,
        }),
      ),
    ));
  }
  if (!defs.length) root.append(h('p', { class: 'muted' }, esc(app.t('ui.no_decisions'))));
  return root;
}
