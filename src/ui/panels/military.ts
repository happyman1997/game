import { realmLevy } from '../../engine/world/economy';
import { armiesOf, canRaiseArmy, commanderOf, daysToNext, disbandArmy, hostileWarAt, raiseArmy } from '../../engine/world/military';
import { alliesOf } from '../../engine/world/war';
import type { App } from '../app';
import { fmt, h } from '../dom';
import { bar, button, charLink, provLink, section } from '../widgets';

export function renderMilitaryPanel(app: App): HTMLElement {
  const g = app.game!;
  const p = g.player!;
  const root = h('div', { class: 'mil-panel' });
  const levy = realmLevy(g, p);
  root.append(h('div', { class: 'kv' },
    h('div', null, app.t('ui.levies')), h('div', null, fmt(levy)),
    h('div', null, app.t('ui.levy_ratio')), h('div', null, `${Math.round(p.levyRatio * 100)}%`),
  ));
  root.append(button(`⚔ ${app.t('ui.raise_army')}`, () => {
    const a = raiseArmy(g, p);
    if (a) {
      app.selectArmy(a.id);
      app.map.focus(a.location);
    }
    app.markDirty(true);
  }, { disabled: !canRaiseArmy(g, p), cls: 'btn-big', tip: app.t('ui.raise_army_tip') }));
  root.append(h('p', { class: 'hint' }, app.t('ui.move_hint')));
  const armies = armiesOf(g, p.id);
  if (armies.length) {
    root.append(section(app.t('ui.armies'), ...armies.map((a) => h('div', { class: 'army-card', onclick: () => { app.selectArmy(a.id); app.map.focus(a.location); } },
      h('div', null, `⚔ ${fmt(a.size)} / ${fmt(a.maxSize)}`), bar(a.size, a.maxSize),
      h('div', { class: 'muted' }, provLink(app, a.location), a.path.length ? ` → ${g.nameOf('provinces', a.path[a.path.length - 1])}` : ''),
    ))));
  }
  const allies = alliesOf(g, p.id);
  root.append(section(app.t('ui.allies'), allies.length ? h('div', null, ...allies.map((x) => h('div', null, charLink(app, x, true)))) : h('div', { class: 'muted' }, app.t('ui.no_allies'))));
  const truces = g.state.truces.filter((t) => t.until > g.date && (t.a === p.id || t.b === p.id));
  if (truces.length) root.append(section(app.t('ui.truces'), ...truces.map((t) => h('div', null, charLink(app, t.a === p.id ? t.b : t.a), ` — ${app.t('ui.until_year', { y: Math.floor(t.until / 365) })}`))));
  return root;
}

export function renderArmyPanel(app: App, id: string): HTMLElement {
  const g = app.game!;
  const a = g.state.armies[id];
  if (!a) return h('div', { class: 'muted' }, app.t('ui.army_gone'));
  const root = h('div', { class: 'army-panel' });
  const cmd = commanderOf(g, a);
  root.append(h('h3', null, `⚔ ${fmt(a.size)}`), bar(a.size, a.maxSize));
  const war = hostileWarAt(g, a, a.location);
  const p = g.state.provinces[a.location];
  const status = a.retreating ? app.t('ui.retreating') : a.path.length ? app.t('ui.marching', { place: g.nameOf('provinces', a.path[a.path.length - 1]), days: daysToNext(g, a) }) : p?.siege?.army === a.id ? app.t('ui.sieging', { n: Math.floor(p.siege.progress) }) : war ? app.t('ui.in_enemy_land') : app.t('ui.idle');
  root.append(h('div', { class: 'kv' },
    h('div', null, app.t('ui.owner')), h('div', null, charLink(app, a.owner, true)),
    h('div', null, app.t('ui.commander')), h('div', null, cmd ? charLink(app, cmd.id) : app.t('ui.none')),
    h('div', null, app.t('ui.location')), h('div', null, provLink(app, a.location)),
    h('div', null, app.t('ui.status')), h('div', null, status),
  ));
  if (g.isPlayer(a.owner)) {
    root.append(h('p', { class: 'hint' }, app.t('ui.move_hint')));
    root.append(button(app.t('ui.disband'), () => { disbandArmy(g, a.id); app.closePanel(); }, { cls: 'btn-red' }));
  }
  return root;
}
