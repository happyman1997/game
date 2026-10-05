import { knightCap, knightsOf, knightsPower } from '../../engine/features/knights';
import type { Character } from '../../engine/types';
import { skill } from '../../engine/world/stats';
import type { App } from '../app';
import { fmt, h } from '../dom';
import { charLink, portrait, section } from '../widgets';

/** Раздел «Рыцари» во вкладке армии. */
export function renderKnightsSection(app: App, p: Character): HTMLElement | null {
  const g = app.game!;
  if (!g.engine.hasFeature('knights') || !p.titles.length) return null;
  const knights = knightsOf(g, p);
  const cap = knightCap(g, p);
  return section(`🛡 ${app.t('ui.knights')} — ${knights.length} / ${cap}`,
    h('p', { class: 'hint' }, app.t('ui.knights_hint', { n: fmt(knightsPower(g, p)) })),
    ...(knights.length
      ? knights.map((k) => h('div', { class: 'knight-row' }, portrait(app, k, 28), charLink(app, k.id, true), h('span', { class: 'knight-prowess' }, `💪 ${skill(g, k, 'prowess')}`)))
      : [h('div', { class: 'muted' }, app.t('ui.no_knights'))]));
}
