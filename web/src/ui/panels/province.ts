import type { BuildingDef, HoldingDef, TitleDef } from '../../engine/content/defs';
import { charFullName } from '../../engine/world/characters';
import { buildingCandidates, buildingCost, buildingSlots, startBuilding } from '../../engine/world/decisions';
import { countyLevy, countyTax } from '../../engine/world/economy';
import { armiesAt, provinceFort } from '../../engine/world/military';
import {
  canCreateTitle,
  canUsurpTitle,
  controlledShare,
  createTitle,
  deJureCounties,
  deJureVassalTitles,
  provinceController,
  titleActionCost,
  titleFullName,
  usurpTitle,
} from '../../engine/world/titles';
import type { App } from '../app';
import { type Child, esc, fmt, h } from '../dom';
import { bar, button, charLink, costText, modifiersHtml, provLink, reasonsHtml, section, titleCoa, titleLink } from '../widgets';

function deJureChain(app: App, id: string): string[] {
  const g = app.game!;
  const out: string[] = [];
  let t = g.content.get<TitleDef>('titles', id)?.liege;
  while (t) {
    out.push(t);
    t = g.content.get<TitleDef>('titles', t)?.liege;
  }
  return out;
}

export function titleActions(app: App, titleId: string): HTMLElement | null {
  const g = app.game!;
  const p = g.player;
  const def = g.content.get<TitleDef>('titles', titleId);
  if (!p || !def || def.tier === 'county' || g.state.gameOver) return null;
  const st = g.state.titles[titleId];
  const { have, total } = controlledShare(g, p, titleId);
  if (have === 0 || have / Math.max(1, total) < 0.25) return null;
  const box = h('div', { class: 'title-actions' });
  if (!st.holder && !def.no_create) {
    const r = canCreateTitle(g, p, titleId);
    const cost = titleActionCost(g, titleId, 'create');
    box.append(button(`👑 ${app.t('ui.create_title')} (${costText(app, cost)})`, () => {
      if (createTitle(g, p, titleId)) app.toast(app.t('ui.title_created'), 'good');
      app.markDirty(true);
    }, { disabled: !r.ok, tip: () => `<div>${esc(app.t('ui.counties_controlled', { have, total }))}</div>${reasonsHtml(app, r.reasons)}` }));
  } else if (st.holder && st.holder !== p.id) {
    const r = canUsurpTitle(g, p, titleId);
    const cost = titleActionCost(g, titleId, 'usurp');
    box.append(button(`⚔ ${app.t('ui.usurp_title')} (${costText(app, cost)})`, () => {
      if (usurpTitle(g, p, titleId)) app.toast(app.t('ui.title_usurped'), 'good');
      app.markDirty(true);
    }, { disabled: !r.ok, tip: () => `<div>${esc(app.t('ui.counties_controlled', { have, total }))}</div>${reasonsHtml(app, r.reasons)}` }));
  }
  return box.children.length ? box : null;
}

export function renderProvincePanel(app: App, id: string): HTMLElement {
  const g = app.game!;
  const def = g.content.get('provinces', id);
  const st = g.state.provinces[id];
  if (!def) return h('div');
  const root = h('div', { class: 'prov-panel' });
  if (def.impassable || !st) {
    root.append(h('h3', null, g.nameOf('provinces', id)), h('p', { class: 'muted' }, app.t('ui.impassable')));
    return root;
  }
  const holder = g.char(g.state.titles[id]?.holder);
  const ctrl = provinceController(g, id);
  root.append(h('div', { class: 'prov-head' }, titleCoa(app, id, 48), h('div', null,
    h('h3', null, titleFullName(g, id)),
    h('div', { class: 'chain' }, ...deJureChain(app, id).flatMap((t, i) => [i ? ' › ' : '', titleLink(app, t)])),
  )));
  root.append(h('div', { class: 'kv' },
    h('div', null, app.t('ui.holder')), h('div', null, holder ? charLink(app, holder.id, true) : app.t('ui.none')),
    ctrl && holder && ctrl.id !== holder.id ? [h('div', { class: 'bad' }, app.t('ui.occupant')), h('div', null, charLink(app, ctrl.id, true))] : null,
    h('div', null, app.t('ui.terrain')), h('div', null, g.nameOf('terrain', def.terrain)),
    h('div', null, app.t('ui.culture')), h('div', null, g.nameOf('cultures', st.culture)),
    h('div', null, app.t('ui.faith')), h('div', null, g.nameOf('faiths', st.faith)),
    h('div', null, app.t('ui.development')), h('div', null, fmt(st.development)),
    h('div', null, app.t('ui.tax')), h('div', null, `${fmt(countyTax(g, id), 2)} 💰/${app.t('ui.month_short')}`),
    h('div', null, app.t('ui.levy')), h('div', null, fmt(countyLevy(g, id))),
    h('div', null, app.t('ui.fort')), h('div', null, fmt(provinceFort(g, id))),
  ));
  root.append(h('div', { class: 'holdings' }, ...def.holdings.map((hd: string) => {
    const hdef = g.content.get<HoldingDef>('holdings', hd);
    return h('span', { class: 'holding', tip: `<div class="tip-title">${esc(g.nameOf('holdings', hd))}</div>${modifiersHtml(app, { tax: hdef?.tax ?? 0, levy: hdef?.levy ?? 0, fort: hdef?.fort ?? 0 })}` }, `${hdef?.icon ?? '🏠'} ${g.nameOf('holdings', hd)}`);
  })));
  if (st.siege) root.append(h('div', { class: 'siege' }, `🏰 ${app.t('ui.siege')}: ${Math.floor(st.siege.progress)}%`, bar(st.siege.progress, 100, 'siege-bar')));
  if (st.modifiers.length) root.append(h('div', { class: 'modifiers' }, ...st.modifiers.map((m) => {
    const md = g.content.get('modifiers', m.id);
    return h('span', { class: ['modifier', md?.good ? 'good' : 'bad'], tip: modifiersHtml(app, md?.modifiers) }, `${md?.icon ?? '✦'} ${g.nameOf('modifiers', m.id)}`);
  })));

  // постройки
  const builds = h('div', { class: 'buildings' });
  for (const b of st.buildings) {
    const bd = g.content.get<BuildingDef>('buildings', b);
    builds.append(h('div', { class: 'building built', tip: `<div class="tip-title">${esc(g.nameOf('buildings', b))}</div>${modifiersHtml(app, bd?.modifiers)}${modifiersHtml(app, bd?.owner_modifiers)}` }, `${bd?.icon ?? '🏠'} ${g.nameOf('buildings', b)}`));
  }
  if (st.construction) {
    const bd = g.content.get<BuildingDef>('buildings', st.construction.building);
    const total = bd?.days ?? 1;
    const left = st.construction.done - g.date;
    builds.append(h('div', { class: 'building building-progress' }, `🚧 ${g.nameOf('buildings', st.construction.building)} — ${app.t('ui.days_left', { n: left })}`, bar(total - left, total)));
  }
  root.append(section(`${app.t('ui.buildings')} (${st.buildings.length}/${buildingSlots(g, id)})`, builds));
  const p = g.player;
  if (p && holder?.id === p.id) {
    const cands = buildingCandidates(g, p, id);
    if (cands.length) {
      root.append(section(app.t('ui.build'), h('div', { class: 'build-list' }, ...cands.map(({ def: bd, blockers }) => {
        const cost = buildingCost(g, bd, p, id);
        return button(h('span', null, `${bd.icon ?? '🏠'} ${g.nameOf('buildings', bd.id)} `, h('small', null, `${costText(app, cost)} · ${app.t('ui.days_n', { n: bd.days })}`)), () => {
          if (startBuilding(g, p, id, bd.id)) app.toast(app.t('ui.construction_started'), 'good');
          app.markDirty(true);
        }, { disabled: blockers.length > 0, cls: 'build-btn', tip: () => `<div class="tip-title">${esc(g.nameOf('buildings', bd.id))}</div>${g.descOf('buildings', bd.id) ? `<p>${esc(g.descOf('buildings', bd.id))}</p>` : ''}${modifiersHtml(app, bd.modifiers)}${modifiersHtml(app, bd.owner_modifiers)}${reasonsHtml(app, blockers)}` });
      }))));
    }
  }
  const armies = armiesAt(g, id);
  if (armies.length) root.append(section(app.t('ui.armies_here'), ...armies.map((a) => h('div', { class: 'army-row', onclick: () => app.selectArmy(a.id) }, `⚔ ${fmt(a.size)} — `, charLink(app, a.owner, true)))));
  const actions: Child[] = deJureChain(app, id).map((t) => titleActions(app, t));
  if (actions.some(Boolean)) root.append(section(app.t('ui.title_actions'), ...actions));
  for (const s of g.engine.ui.provinceSections.values().sort((a, b) => (a.order ?? 0) - (b.order ?? 0))) {
    try {
      const r = s.render(g, id, app);
      if (r) root.append(section(g.loc.resolve(s.title), typeof r === 'string' ? h('div', { html: r }) : r));
    } catch (e) {
      console.error(e);
    }
  }
  return root;
}

export function renderTitlePanel(app: App, id: string): HTMLElement {
  const g = app.game!;
  const def = g.content.get<TitleDef>('titles', id);
  const st = g.state.titles[id];
  if (!def || !st) return h('div');
  if (def.tier === 'county' && g.state.provinces[id]) return renderProvincePanel(app, id);
  const root = h('div', { class: 'title-panel' });
  root.append(h('div', { class: 'prov-head' }, titleCoa(app, id, 56), h('div', null, h('h3', null, titleFullName(g, id)), h('div', { class: 'chain' }, ...deJureChain(app, id).flatMap((t, i) => [i ? ' › ' : '', titleLink(app, t)])))));
  root.append(h('div', { class: 'kv' },
    h('div', null, app.t('ui.holder')), h('div', null, st.holder ? charLink(app, st.holder, true) : app.t('ui.none')),
    h('div', null, app.t('ui.counties')), h('div', null, fmt(deJureCounties(g, id).length)),
  ));
  const act = titleActions(app, id);
  if (act) root.append(act);
  const vassals = deJureVassalTitles(g, id);
  root.append(section(app.t('ui.de_jure_vassals'), h('div', { class: 'title-list' }, ...vassals.map((t) => h('div', { class: 'title-row' }, titleCoa(app, t, 18), titleLink(app, t), ' ', h('span', { class: 'muted' }, g.state.titles[t]?.holder ? charFullName(g, g.char(g.state.titles[t].holder)!, false) : app.t('ui.none')))))));
  if (st.history.length) {
    root.append(section(app.t('ui.history'), h('div', { class: 'history' }, ...[...st.history].reverse().slice(0, 12).map((e) => h('div', null, `${Math.floor(e.from / 365)}: `, charLink(app, e.holder))))));
  }
  return root;
}

export { provLink };
