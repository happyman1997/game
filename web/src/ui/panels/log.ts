import { dateParts } from '../../engine/core/date';
import type { App } from '../app';
import { h } from '../dom';

export function renderLogPanel(app: App): HTMLElement {
  const g = app.game!;
  const root = h('div', { class: 'log-panel' });
  for (const m of [...g.state.messages].reverse().slice(0, 150)) {
    const { y, m: mo, d } = dateParts(m.date);
    root.append(h('div', { class: ['msg', `msg-${m.kind}`], onclick: () => {
      if (m.ref?.type === 'character') app.openCharacter(m.ref.id);
      else if (m.ref?.type === 'province') app.openProvince(m.ref.id, true);
    } }, h('span', { class: 'msg-date' }, `${d}.${mo}.${y}`), ' ', m.text));
  }
  return root;
}
