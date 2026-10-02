import { schemeMonthlyProgress, schemeSuccessChance, endScheme } from '../../engine/world/schemes';
import type { App } from '../app';
import { fmt, h } from '../dom';
import { bar, button, charLink, section } from '../widgets';

export function renderIntriguePanel(app: App): HTMLElement {
  const g = app.game!;
  const p = g.player!;
  const root = h('div', { class: 'intrigue-panel' });
  const mine = Object.values(g.state.schemes).filter((s) => s.owner === p.id);
  root.append(h('p', { class: 'hint' }, app.t('ui.scheme_hint')));
  root.append(section(app.t('ui.my_schemes'), ...(mine.length ? mine.map((s) => {
    const def = g.content.get('schemes', s.type);
    return h('div', { class: 'scheme-card' },
      h('div', null, `${def?.icon ?? '🗡'} ${g.nameOf('schemes', s.type)} → `, charLink(app, s.target, true)),
      bar(s.progress, 100),
      h('div', { class: 'muted' }, app.t('ui.scheme_stats', { progress: Math.floor(s.progress), speed: fmt(schemeMonthlyProgress(g, s), 1), chance: schemeSuccessChance(g, s) }), s.discovered ? ` · ${app.t('ui.discovered')}` : ''),
      button(app.t('ui.abandon'), () => { endScheme(g, s.id); app.markDirty(true); }, { cls: 'btn-small' }),
    );
  }) : [h('div', { class: 'muted' }, app.t('ui.none'))])));
  const against = Object.values(g.state.schemes).filter((s) => s.target === p.id && s.discovered);
  if (against.length) {
    root.append(section(app.t('ui.schemes_against'), ...against.map((s) => h('div', { class: 'scheme-card bad' }, `${g.nameOf('schemes', s.type)}: `, charLink(app, s.owner, true), ` (${Math.floor(s.progress)}%)`))));
  }
  return root;
}
