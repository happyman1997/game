import { type RealmLawDef, changeLaw, currentLaw, isGroupShown, lawChangeBlockers, lawChangeCost, lawGroups, lawsOfGroup } from '../../engine/features/laws';
import type { Character } from '../../engine/types';
import type { App } from '../app';
import { esc, h } from '../dom';
import { button, costText, modifiersHtml, reasonsHtml, section } from '../widgets';

function lawTip(app: App, l: RealmLawDef): string {
  const g = app.game!;
  return `<div class="tip-title">${esc(l.icon ?? '')} ${esc(g.nameOf('realm_laws', l.id))}</div><p>${esc(g.descOf('realm_laws', l.id))}</p>${modifiersHtml(app, l.modifiers)}`;
}

/** Раздел «Законы державы» во вкладке владений. */
export function renderLawsSection(app: App, p: Character): HTMLElement | null {
  const g = app.game!;
  const groups = lawGroups(g).filter((gd) => isGroupShown(g, p, gd));
  if (!groups.length) return null;
  const out: HTMLElement[] = [];
  for (const gd of groups) {
    const cur = currentLaw(g, p, gd.id);
    const laws = lawsOfGroup(g, gd.id);
    const ladder = h('div', { class: 'law-ladder' });
    for (const l of laws) {
      const active = l.id === cur?.id;
      const blockers = active ? [] : lawChangeBlockers(g, p, l);
      ladder.append(button(h('span', null, `${l.icon ?? '•'} `, g.nameOf('realm_laws', l.id), active ? '' : h('span', { class: 'muted' }, ` · ${costText(app, lawChangeCost(g, p, l))}`)), () => {
        if (active) return;
        changeLaw(g, p, l.id);
        app.markDirty(true);
      }, { cls: `btn-small law-step ${active ? 'active' : ''}`, disabled: !active && blockers.length > 0, tip: () => lawTip(app, l) + reasonsHtml(app, blockers) }));
    }
    out.push(h('div', { class: 'law-group' },
      h('div', { class: 'law-group-name', tip: g.descOf('law_groups', gd.id) }, `${gd.icon ?? ''} ${g.nameOf('law_groups', gd.id)}`),
      ladder));
  }
  return section(app.t('ui.realm_laws'), ...out);
}
