import {
  type FactionDef,
  canJoinFaction,
  claimantCandidates,
  createFaction,
  factionOf,
  factionPower,
  factionsAgainst,
  joinFaction,
  leaveFaction,
  playerUltimatum,
} from '../../engine/features/factions';
import type { Character, Faction } from '../../engine/types';
import type { App } from '../app';
import { h } from '../dom';
import { bar, button, charLink, section } from '../widgets';

/** Фракции: против игрока (если он сюзерен) и против его сюзерена (если он вассал). */
export function renderFactionsSection(app: App, p: Character): HTMLElement[] {
  const g = app.game!;
  const out: HTMLElement[] = [];
  const types = g.content.all<FactionDef>('factions');
  if (!types.length) return out;
  const threshold = g.defines.factions?.power_threshold ?? 80;

  if (g.vassalsOf(p.id).length) {
    const against = factionsAgainst(g, p.id);
    out.push(section(`⚑ ${app.t('ui.factions_against_you')}`,
      h('p', { class: 'hint' }, app.t('ui.faction_hint', { n: threshold })),
      ...(against.length ? against.map((f) => factionCard(app, f, false)) : [h('div', { class: 'muted' }, app.t('ui.no_factions'))])));
  }

  const liege = g.char(p.liege);
  if (liege && p.titles.length) {
    const mine = factionOf(g, p);
    const against = factionsAgainst(g, liege.id);
    const cards: HTMLElement[] = against.map((f) => factionCard(app, f, true));
    const cooldown = p.flags.faction_cooldown !== undefined && p.flags.faction_cooldown > g.date;
    if (!mine) {
      for (const def of types) {
        if (against.some((f) => f.type === def.id)) continue;
        const claimant = def.claimant ? (claimantCandidates(g, liege).find((c) => c.id === p.id) ?? claimantCandidates(g, liege)[0])?.id : undefined;
        if (def.claimant && !claimant) continue;
        const ok = canJoinFaction(g, p, def, liege, claimant);
        cards.push(h('div', { class: 'faction-card new' },
          h('div', { class: 'faction-name', tip: g.descOf('factions', def.id) }, `${def.icon ?? '⚑'} ${g.nameOf('factions', def.id)}`),
          claimant ? h('div', { class: 'muted' }, `${app.t('ui.faction_claimant')}: `, charLink(app, claimant, true)) : null,
          button(app.t('ui.create_faction'), () => { createFaction(g, def.id, p, claimant); app.markDirty(true); }, { cls: 'btn-small', disabled: !ok, tip: cooldown ? app.t('ui.faction_cooldown') : undefined }),
        ));
      }
    }
    if (cards.length) out.push(section(`⚑ ${app.t('ui.factions_against_liege')}`, h('p', { class: 'hint' }, app.t('ui.faction_hint', { n: threshold })), ...cards));
  }
  return out;
}

function factionCard(app: App, f: Faction, asVassal: boolean): HTMLElement {
  const g = app.game!;
  const p = g.player!;
  const def = g.content.get<FactionDef>('factions', f.type);
  const power = factionPower(g, f);
  const card = h('div', { class: 'faction-card' },
    h('div', { class: 'faction-name', tip: g.descOf('factions', f.type) }, `${def?.icon ?? '⚑'} ${g.nameOf('factions', f.type)}`),
    h('div', null, `${app.t('ui.faction_leader')}: `, charLink(app, f.leader, true)),
    f.claimant ? h('div', null, `${app.t('ui.faction_claimant')}: `, charLink(app, f.claimant, true)) : null,
    h('div', { class: power >= (g.defines.factions?.power_threshold ?? 80) ? 'bad' : 'muted' }, app.t('ui.faction_power', { n: power })),
    h('div', { class: 'muted' }, app.t('ui.faction_discontent', { n: Math.round(f.discontent) })),
    bar(f.discontent, 100, 'bar-red'),
    h('details', null, h('summary', null, app.t('ui.faction_members', { n: f.members.length })), ...f.members.map((id) => h('div', null, charLink(app, id, true)))),
  );
  if (asVassal && def) {
    const liege = g.char(f.target)!;
    const member = f.members.includes(p.id);
    const btns = h('div', { class: 'faction-btns' });
    if (member) {
      btns.append(button(app.t('ui.leave_faction'), () => { leaveFaction(g, p); app.markDirty(true); }, { cls: 'btn-small' }));
      if (f.leader === p.id) btns.append(button(app.t('ui.send_ultimatum'), () => { playerUltimatum(g, f); app.markDirty(true); }, { cls: 'btn-small btn-red', disabled: f.discontent < 100 }));
    } else if (!factionOf(g, p)) {
      const ok = canJoinFaction(g, p, def, liege, f.claimant);
      btns.append(button(app.t('ui.join_faction'), () => { joinFaction(g, p, f); app.markDirty(true); }, { cls: 'btn-small', disabled: !ok }));
    }
    card.append(btns);
  }
  return card;
}
