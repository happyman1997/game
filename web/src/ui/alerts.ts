/**
 * Оповещения в верхней панели. Встроенные регистрируются здесь в общий
 * реестр engine.ui.alerts — моды добавляют свои так же:
 *
 *   api.ui.alerts.register('my_alert', { id: 'my_alert', check: (game) => ({ icon: '🔔', text: '…', action: { tab: 'realm' } }) });
 */
import type { Engine } from '../engine/engine';
import { availablePerks, currentLifestyle, perkCost } from '../engine/features/lifestyles';
import { councilCandidates, councilPositions, isPositionShown } from '../engine/features/council';
import { factionsAgainst, factionOf } from '../engine/features/factions';
import { prisonersOf } from '../engine/features/prison';
import { recruitBlockers, regimentTypes } from '../engine/features/regiments';
import type { Game } from '../engine/game';
import type { Alert, AlertAction } from '../engine/uiRegistry';
import { domainLimit } from '../engine/world/economy';
import { heirsOf } from '../engine/world/succession';
import { canCreateTitle, domainCounties, realmCounties } from '../engine/world/titles';
import { warsOf } from '../engine/world/war';
import type { App } from './app';
import { esc, h } from './dom';

export function registerBuiltinAlerts(engine: Engine): void {
  // Мод, зарегистрировавший оповещение с тем же id, заменяет встроенное.
  const reg = (id: string, order: number, check: (g: Game) => Alert | Alert[] | null | undefined) => {
    if (!engine.ui.alerts.has(id)) engine.ui.alerts.register(id, { id, order, check }, 'core');
  };
  const t = (g: Game, k: string, p?: Record<string, unknown>) => g.loc.t(k, p);

  reg('perk_available', 10, (g) => {
    const p = g.player!;
    if (!g.engine.hasFeature('lifestyles')) return null;
    const l = currentLifestyle(g, p);
    if (!l || !availablePerks(g, p, l.id).length) return null;
    if ((p.lifestyle?.xp[l.id] ?? 0) < perkCost(g, p, l.id)) return null;
    return { icon: '🌿', kind: 'good', text: t(g, 'alert.perk_available', { lifestyle: g.nameOf('lifestyles', l.id) }), action: { tab: 'lifestyle' } };
  });
  reg('council_vacant', 20, (g) => {
    const p = g.player!;
    if (!g.engine.hasFeature('council') || !p.titles.length) return null;
    const empty = councilPositions(g).filter((pos) => isPositionShown(g, p, pos) && !p.council?.[pos.id]?.holder && councilCandidates(g, p, pos.id).length);
    if (!empty.length) return null;
    return { icon: '🪑', kind: 'info', text: t(g, 'alert.council_vacant', { list: empty.map((x) => g.nameOf('council_positions', x.id)).join(', ') }), action: { tab: 'realm' } };
  });
  reg('title_creatable', 30, (g) => {
    const p = g.player!;
    const cands = new Set<string>();
    for (const c of realmCounties(g, p)) {
      let tt = g.content.get('titles', c)?.liege;
      while (tt) {
        if (!p.titles.includes(tt)) cands.add(tt);
        tt = g.content.get('titles', tt)?.liege;
      }
    }
    const ok = [...cands].filter((x) => canCreateTitle(g, p, x).ok);
    if (!ok.length) return null;
    return { icon: '👑', kind: 'good', text: t(g, 'alert.title_creatable', { list: ok.map((x) => g.scopeName({ type: 'title', id: x })).join(', ') }), action: { tab: 'realm' } };
  });
  reg('faction_threat', 40, (g) => {
    if (!g.engine.hasFeature('factions')) return null;
    const p = g.player!;
    const out: Alert[] = [];
    const threat = factionsAgainst(g, p.id).filter((f) => f.discontent >= 50);
    if (threat.length) out.push({ icon: '⚑', kind: 'bad', text: t(g, 'alert.faction_threat', { n: Math.max(...threat.map((f) => Math.round(f.discontent))) }), action: { tab: 'realm' } });
    const mine = factionOf(g, p);
    if (mine && mine.leader === p.id && mine.discontent >= 100) out.push({ icon: '📯', kind: 'good', text: t(g, 'alert.faction_ready'), action: { tab: 'realm' } });
    return out;
  });
  reg('no_heir', 50, (g) => {
    const p = g.player!;
    if (!p.titles.length || heirsOf(g, p).length) return null;
    return { icon: '⚠', kind: 'bad', text: t(g, 'alert.no_heir'), action: { character: p.id } };
  });
  reg('unmarried', 55, (g) => {
    const p = g.player!;
    if (p.spouses.length || (g.date - p.birth) / 365 < (g.defines.character?.marriage_age ?? 16) || (g.date - p.birth) / 365 > 60) return null;
    return { icon: '💍', kind: 'info', text: t(g, 'alert.unmarried'), action: { character: p.id } };
  });
  reg('debt', 60, (g) => (g.player!.gold < 0 ? { icon: '💸', kind: 'bad', text: t(g, 'alert.debt'), action: { tab: 'realm' } } : null));
  reg('over_domain', 65, (g) => {
    const p = g.player!;
    const n = domainCounties(g, p).length;
    const lim = domainLimit(g, p);
    return n > lim ? { icon: '🏚', kind: 'bad', text: t(g, 'alert.over_domain', { n, limit: lim }), action: { tab: 'realm' } } : null;
  });
  reg('enemy_in_realm', 70, (g) => {
    const p = g.player!;
    const wars = warsOf(g, p.id);
    if (!wars.length) return null;
    const mine = new Set(realmCounties(g, p));
    const occupied = [...mine].filter((c) => g.state.provinces[c]?.occupant && wars.some((w) => w.id === g.state.provinces[c].occupantWar));
    if (!occupied.length) return null;
    return { icon: '🔥', kind: 'bad', text: t(g, 'alert.occupied', { n: occupied.length }), action: { province: occupied[0] } };
  });
  reg('schemes_against', 75, (g) => {
    const n = Object.values(g.state.schemes).filter((s) => s.target === g.state.player && s.discovered).length;
    return n ? { icon: '🗡', kind: 'bad', text: t(g, 'alert.schemes_against', { n }), action: { tab: 'intrigue' } } : null;
  });
  reg('prisoners', 80, (g) => {
    if (!g.engine.hasFeature('prison')) return null;
    const n = prisonersOf(g, g.state.player!).length;
    return n ? { icon: '⛓', kind: 'info', text: t(g, 'alert.prisoners', { n }), action: { tab: 'intrigue' } } : null;
  });
  reg('imprisoned', 81, (g) => {
    const p = g.player!;
    return p.prison ? { icon: '⛓', kind: 'bad', text: t(g, 'alert.imprisoned', { jailer: g.scopeName({ type: 'character', id: p.prison.by }) }), action: { character: p.prison.by } } : null;
  });
  reg('can_recruit', 90, (g) => {
    if (!g.engine.hasFeature('regiments')) return null;
    const p = g.player!;
    if (!p.titles.length || p.gold < 150) return null;
    const ok = regimentTypes(g).some((d) => !recruitBlockers(g, p, d).length);
    return ok ? { icon: '🛡', kind: 'info', text: t(g, 'alert.can_recruit'), action: { tab: 'military' } } : null;
  });
}

let cache: { date: number; player?: string; alerts: Alert[] } | null = null;

export function collectAlerts(game: Game, force = false): Alert[] {
  if (!game.state.player || !game.player) return [];
  if (!force && cache && cache.date === game.date && cache.player === game.state.player) return cache.alerts;
  const out: Alert[] = [];
  for (const spec of game.engine.ui.alerts.values().sort((a, b) => (a.order ?? 0) - (b.order ?? 0))) {
    try {
      const r = spec.check(game);
      if (!r) continue;
      for (const a of Array.isArray(r) ? r : [r]) if (a) out.push(a);
    } catch (e) {
      console.error(`Оповещение ${spec.id}:`, e);
    }
  }
  cache = { date: game.date, player: game.state.player, alerts: out };
  return out;
}

export function invalidateAlerts(): void {
  cache = null;
}

export function runAlertAction(app: App, a?: AlertAction): void {
  if (!a) return;
  if (a.tab) {
    if (!(app.panel?.kind === 'tab' && app.panel.id === a.tab)) app.openTab(a.tab);
  }
  else if (a.character) app.openCharacter(a.character);
  else if (a.title) app.openTitle(a.title);
  else if (a.province) {
    app.openProvince(a.province, true);
    app.map.focus(a.province);
  }
}

export function renderAlerts(app: App): HTMLElement {
  const g = app.game!;
  const box = h('div', { class: 'tb-alerts' });
  for (const a of collectAlerts(g)) {
    box.append(h('button', {
      class: ['alert', `alert-${a.kind ?? 'info'}`],
      tip: `<div class="alert-tip ${esc(a.kind ?? 'info')}">${esc(a.text)}</div>`,
      onclick: (e: Event) => {
        e.stopPropagation();
        runAlertAction(app, a.action);
      },
    }, a.icon));
  }
  return box;
}
