import type { SuccessionLawDef, TitleDef } from '../../engine/content/defs';
import { makeContext } from '../../engine/script/context';
import { evalValue, failedTriggers } from '../../engine/script/interpreter';
import { ageOf, charFullName } from '../../engine/world/characters';
import { domainCounties, realmCounties } from '../../engine/world/titles';
import { domainLimit, incomeBreakdown, monthlyIncome } from '../../engine/world/economy';
import { opinion } from '../../engine/world/opinion';
import { heirsOf, lawOf } from '../../engine/world/succession';
import { canCreateTitle } from '../../engine/world/titles';
import type { App } from '../app';
import { esc, fmt, h, signed } from '../dom';
import { breakdownHtml, button, charLink, costText, reasonsHtml, section, titleCoa, titleLink } from '../widgets';
import { titleActions } from './province';

export function renderRealmPanel(app: App): HTMLElement {
  const g = app.game!;
  const p = g.player!;
  const root = h('div', { class: 'realm-panel' });
  const dom = domainCounties(g, p);
  const limit = domainLimit(g, p);
  root.append(h('div', { class: 'kv' },
    h('div', null, app.t('ui.domain')), h('div', { class: dom.length > limit ? 'bad' : '', tip: app.t('ui.domain_tip') }, `${dom.length} / ${limit}`),
    h('div', null, app.t('ui.realm_size')), h('div', null, fmt(realmCounties(g, p).length)),
    h('div', null, app.t('ui.income')), h('div', { tip: () => breakdownHtml(incomeBreakdown(g, p), 1) }, `${signed(monthlyIncome(g, p), 1)} 💰`),
  ));

  // наследование
  const law = lawOf(g, p);
  const heirs = heirsOf(g, p).slice(0, 5);
  const succ = h('div', null,
    h('div', { tip: law ? g.descOf('succession_laws', law.id) : '' }, `📜 ${law ? g.nameOf('succession_laws', law.id) : '—'}`),
    h('ol', { class: 'heirs' }, ...heirs.map((id) => h('li', null, charLink(app, id), ` (${ageOf(g, g.char(id)!)})`))),
  );
  if (p.titles.length) {
    const lawBtns = h('div', { class: 'law-btns' });
    for (const l of g.content.all<SuccessionLawDef>('succession_laws')) {
      if (l.id === law?.id) continue;
      const ctx = makeContext(g, { type: 'character', id: p.id });
      const cost = Math.round(evalValue(ctx, ctx.root, l.change_cost?.prestige ?? 0));
      const reasons = failedTriggers(ctx, ctx.root, l.can_change);
      if (cost > 0 && p.prestige < cost) reasons.push(app.t('ui.need_prestige', { value: cost }));
      lawBtns.append(button(`${g.nameOf('succession_laws', l.id)} (${costText(app, { prestige: cost })})`, () => {
        p.prestige -= cost;
        p.successionLaw = l.id;
        app.toast(app.t('ui.law_changed'), 'good');
        app.markDirty(true);
      }, { disabled: reasons.length > 0, cls: 'btn-small', tip: () => `<p>${esc(g.descOf('succession_laws', l.id))}</p>${reasonsHtml(app, reasons)}` }));
    }
    succ.append(h('div', { class: 'muted' }, app.t('ui.change_law')), lawBtns);
  }
  root.append(section(app.t('ui.succession'), succ));

  // титулы и возможные
  root.append(section(app.t('ui.titles'), h('div', { class: 'title-list' }, ...p.titles.map((t) => h('div', { class: 'title-row' }, titleCoa(app, t, 20), titleLink(app, t))))));
  const candidates = new Set<string>();
  for (const c of realmCounties(g, p)) {
    let t = g.content.get<TitleDef>('titles', c)?.liege;
    while (t) {
      if (!p.titles.includes(t)) candidates.add(t);
      t = g.content.get<TitleDef>('titles', t)?.liege;
    }
  }
  const createRows = [...candidates]
    .map((t) => ({ t, r: canCreateTitle(g, p, t) }))
    .sort((a, b) => Number(b.r.ok) - Number(a.r.ok))
    .slice(0, 8)
    .map(({ t }) => h('div', { class: 'title-row' }, titleCoa(app, t, 18), titleLink(app, t), titleActions(app, t)));
  if (createRows.length) root.append(section(app.t('ui.claimable_titles'), ...createRows));

  // вассалы
  const vassals = g.vassalsOf(p.id);
  root.append(section(`${app.t('ui.vassals')} (${vassals.length})`, ...vassals.map((v) => {
    const op = opinion(g, v, p);
    return h('div', { class: 'vassal-row' }, charLink(app, v.id, true), h('span', { class: op >= 0 ? 'good' : 'bad' }, ` ${signed(op)}`));
  })));
  // двор
  const court = g.courtiersOf(p.id);
  root.append(section(`${app.t('ui.court')} (${court.length})`, ...court.map((c) => h('div', { class: 'court-row' }, charLink(app, c.id), h('span', { class: 'muted' }, ` ${ageOf(g, c)}`)))));
  if (p.dynasty) {
    const d = g.state.dynasties[p.dynasty];
    const members = g.living().filter((x) => x.dynasty === p.dynasty);
    root.append(section(app.t('ui.dynasty'), h('div', null, app.t('ui.dynasty_n', { name: g.nameOf('dynasties', p.dynasty) }), ` · ⭐ ${fmt(d?.prestige ?? 0)} · ${app.t('ui.members_n', { n: members.length })}`)));
  }
  void charFullName;
  return root;
}
