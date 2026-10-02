import type { CasusBelliDef } from '../../engine/content/defs';
import { militaryStrength } from '../../engine/world/economy';
import { titleFullName, topLiege } from '../../engine/world/titles';
import {
  aiWillAcceptSurrender,
  aiWillAcceptWhitePeace,
  availableWarTargets,
  canAffordWar,
  declareWar,
  endWar,
  participantSide,
  warCost,
  warsOf,
  warscore,
} from '../../engine/world/war';
import type { App } from '../app';
import { clear, esc, fmt, h, signed } from '../dom';
import { button, charLink, costText, section } from '../widgets';

export function renderWarsPanel(app: App): HTMLElement {
  const g = app.game!;
  const p = g.player!;
  const root = h('div', { class: 'wars-panel' });
  const wars = warsOf(g, p.id);
  if (!wars.length) root.append(h('p', { class: 'muted' }, app.t('ui.no_wars')));
  for (const w of wars) {
    const side = participantSide(w, p.id)!;
    const ws = warscore(g, w);
    const mine = side === 'att' ? ws.total : -ws.total;
    const leader = (side === 'att' ? w.attacker : w.defender) === p.id;
    const enemySide = side === 'att' ? 'def' : 'att';
    const cb = g.content.get<CasusBelliDef>('casus_belli', w.cb);
    const card = h('div', { class: 'war-card' },
      h('div', { class: 'war-name' }, `${cb?.icon ?? '⚔'} ${w.name ?? ''}`),
      h('div', { class: 'muted' }, g.nameOf('casus_belli', w.cb), w.target ? ` · ${titleFullName(g, w.target)}` : ''),
      h('div', { class: 'war-sides' },
        h('div', { class: 'side' }, h('div', { class: 'side-head' }, app.t('ui.attackers')), ...w.attackers.map((x) => h('div', null, charLink(app, x, true)))),
        h('div', { class: 'side' }, h('div', { class: 'side-head' }, app.t('ui.defenders')), ...w.defenders.map((x) => h('div', null, charLink(app, x, true)))),
      ),
      h('div', { class: 'warscore', tip: () => `<div class="tip-title">${esc(app.t('ui.warscore'))}</div><div class="bd-row"><span>${esc(app.t('ui.ws_battles'))}</span><span>${signed(side === 'att' ? ws.battle : -ws.battle)}</span></div><div class="bd-row"><span>${esc(app.t('ui.ws_occupation'))}</span><span>${signed(side === 'att' ? ws.occupation : -ws.occupation)}</span></div><div class="bd-row"><span>${esc(app.t('ui.ws_ticking'))}</span><span>${signed(side === 'att' ? ws.ticking : -ws.ticking)}</span></div>${ws.extra.map((x) => `<div class="bd-row"><span>${esc(x.label)}</span><span>${signed(side === 'att' ? x.value : -x.value)}</span></div>`).join('')}` },
        h('div', { class: 'ws-track' }, h('div', { class: ['ws-fill', mine >= 0 ? 'good' : 'bad'], style: { width: `${Math.abs(mine) / 2}%`, left: mine >= 0 ? '50%' : `${50 - Math.abs(mine) / 2}%` } })),
        h('div', { class: 'ws-val' }, `${app.t('ui.warscore')}: ${signed(mine)}%`)),
    );
    if (leader) {
      const enemyAccepts = aiWillAcceptSurrender(g, w, enemySide);
      const outcomeWin = side === 'att' ? 'victory' : 'defeat';
      const outcomeLose = side === 'att' ? 'defeat' : 'victory';
      card.append(h('div', { class: 'war-actions' },
        button(app.t('ui.enforce_peace'), () => { endWar(g, w, outcomeWin); app.markDirty(true); }, { disabled: !(mine >= 100 || enemyAccepts), cls: 'btn-gold', tip: app.t('ui.enforce_peace_tip') }),
        button(app.t('ui.white_peace'), () => {
          if (aiWillAcceptWhitePeace(g, w, enemySide)) {
            endWar(g, w, 'white_peace');
            app.toast(app.t('ui.white_peace_accepted'), 'good');
          } else app.toast(app.t('ui.white_peace_refused'), 'bad');
          app.markDirty(true);
        }),
        button(app.t('ui.surrender'), () => { endWar(g, w, outcomeLose); app.markDirty(true); }, { cls: 'btn-red' }),
      ));
    }
    root.append(card);
  }
  // Возможные войны
  const targets = availableWarTargets(g, p).slice(0, 12);
  if (targets.length) {
    root.append(section(app.t('ui.possible_wars'), ...targets.map((t) => {
      const cb = g.content.get<CasusBelliDef>('casus_belli', t.cb);
      return h('div', { class: 'cb-row' },
        h('span', null, `${cb?.icon ?? '⚔'} ${g.nameOf('casus_belli', t.cb)}: `, t.title ? titleFullName(g, t.title) : '', ' — ', charLink(app, t.defender, true)),
        button(app.t('ui.declare'), () => openDeclareWar(app, t.defender), { cls: 'btn-small' }));
    })));
  }
  return root;
}

/** Окно объявления войны персонажу (его верховному сюзерену). */
export function openDeclareWar(app: App, defenderId: string) {
  const g = app.game!;
  const p = g.player!;
  const def = g.char(defenderId)!;
  const targets = availableWarTargets(g, p).filter((t) => t.defender === defenderId || t.defender === topLiege(g, def).id);
  const body = h('div', { class: 'declare-war' });
  let close: () => void = () => {};
  const render = () => {
    clear(body);
    body.append(h('h3', null, `⚔ ${app.t('ui.declare_war')}`));
    body.append(h('div', { class: 'strength' }, `${app.t('ui.your_strength')}: ${fmt(militaryStrength(g, p))} · ${app.t('ui.enemy_strength')}: ${fmt(militaryStrength(g, def))}`));
    for (const t of targets) {
      const cb = g.content.get<CasusBelliDef>('casus_belli', t.cb);
      const cost = warCost(g, p, t);
      const afford = canAffordWar(g, p, t);
      body.append(h('div', { class: 'cb-card' },
        h('div', { class: 'cb-title' }, `${cb?.icon ?? '⚔'} ${g.nameOf('casus_belli', t.cb)}`),
        h('div', { class: 'muted' }, g.descOf('casus_belli', t.cb)),
        h('div', null, app.t('ui.target'), ': ', t.title ? titleFullName(g, t.title) : '—', ` (${app.t('ui.counties_n', { n: t.counties.length })})`),
        h('div', null, app.t('ui.enemy'), ': ', charLink(app, t.defender, true)),
        h('div', null, `${app.t('ui.cost')}: ${costText(app, cost)}`),
        button(app.t('ui.declare'), () => {
          const w = declareWar(g, p, t);
          close();
          if (w) app.toast(app.t('ui.war_declared'), 'bad');
          app.openTab('wars');
        }, { disabled: !afford, cls: 'btn-red' }),
      ));
    }
    if (!targets.length) body.append(h('p', { class: 'muted' }, app.t('ui.no_cb')));
    body.append(h('div', { class: 'modal-buttons' }, button(app.t('ui.cancel'), () => close())));
  };
  render();
  close = app.modal(body, { cls: 'ia-modal' });
}
