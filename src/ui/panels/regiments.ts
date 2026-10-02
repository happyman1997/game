import {
  type RegimentTypeDef,
  disbandRegiment,
  isTypeShown,
  recruitBlockers,
  recruitRegiment,
  regimentCap,
  regimentCost,
  regimentTypes,
} from '../../engine/features/regiments';
import type { Army, Character, Regiment } from '../../engine/types';
import type { App } from '../app';
import { esc, fmt, h, signed } from '../dom';
import { bar, button, costText, reasonsHtml, section } from '../widgets';

export function regimentTypeTooltip(app: App, def: RegimentTypeDef): string {
  const g = app.game!;
  const name = (id: string) => g.nameOf('regiment_types', id);
  const counteredBy = g.content.all<RegimentTypeDef>('regiment_types').filter((d) => d.counters?.[def.id]).map((d) => d.id);
  let html = `<div class="tip-title">${esc(def.icon ?? '')} ${esc(name(def.id))}</div>`;
  const desc = g.descOf('regiment_types', def.id);
  if (desc) html += `<p>${esc(desc)}</p>`;
  html += `<div>${esc(app.t('ui.regiment_stats', { size: def.size, power: def.power }))}</div>`;
  html += `<div class="muted">${esc(app.t('ui.regiment_upkeep_n', { n: fmt(def.upkeep, 2), mult: g.defines.regiments?.raised_upkeep_mult ?? 2 }))}</div>`;
  const counters = Object.keys(def.counters ?? {});
  if (counters.length) html += `<div class="good">${esc(app.t('ui.regiment_counters', { list: counters.map(name).join(', ') }))}</div>`;
  if (counteredBy.length) html += `<div class="bad">${esc(app.t('ui.regiment_countered_by', { list: counteredBy.map(name).join(', ') }))}</div>`;
  const terr = Object.entries(def.terrain ?? {});
  if (terr.length) html += `<div class="muted">${esc(app.t('ui.regiment_terrain', { list: terr.map(([t, v]) => `${g.nameOf('terrain', t)} ${signed(Math.round(v * 100))}%`).join(', ') }))}</div>`;
  return html;
}

function inArmy(app: App, c: Character, r: Regiment): boolean {
  return Object.values(app.game!.state.armies).some((a) => a.owner === c.id && a.regiments?.some((x) => x.id === r.id));
}

/** Раздел «Профессиональные войска» во вкладке армии игрока. */
export function renderRegimentsSection(app: App, p: Character): HTMLElement | null {
  const g = app.game!;
  const types = regimentTypes(g);
  if (!types.length || !p.titles.length) return null;
  const cap = regimentCap(g, p);
  const regs = p.regiments ?? [];
  const list = h('div', { class: 'regiments' });
  for (const r of regs) {
    const def = g.content.get<RegimentTypeDef>('regiment_types', r.type);
    if (!def) continue;
    const raised = inArmy(app, p, r);
    list.append(h('div', { class: 'regiment-row', tip: () => regimentTypeTooltip(app, def) },
      h('span', { class: 'reg-icon' }, def.icon ?? '⚔'),
      h('div', { class: 'reg-main' },
        h('div', null, g.nameOf('regiment_types', r.type), raised ? h('span', { class: 'muted' }, ` · ${app.t('ui.regiment_in_army')}`) : r.size < def.size ? h('span', { class: 'muted' }, ` · ${app.t('ui.regiment_reinforcing')}`) : null),
        bar(r.size, def.size),
        h('div', { class: 'muted' }, `${fmt(r.size)} / ${fmt(def.size)} · ${app.t('ui.regiment_power', { n: fmt(r.size * def.power) })}`),
      ),
      button('✕', () => { disbandRegiment(g, p, r.id); app.markDirty(true); }, { cls: 'btn-small btn-red', tip: app.t('ui.dismiss_regiment') }),
    ));
  }
  if (!regs.length) list.append(h('div', { class: 'muted' }, app.t('ui.no_regiments')));

  const shop = h('div', { class: 'reg-shop' });
  for (const def of types) {
    if (!isTypeShown(g, p, def) && def.can_recruit && JSON.stringify(def.can_recruit).includes('culture')) continue;
    const blockers = recruitBlockers(g, p, def);
    const cost = regimentCost(g, p, def);
    shop.append(button(h('span', null, `${def.icon ?? '⚔'} `, g.nameOf('regiment_types', def.id), h('span', { class: 'muted' }, ` · ${costText(app, cost)}`)), () => {
      recruitRegiment(g, p, def.id);
      app.markDirty(true);
    }, { cls: 'btn-small reg-buy', disabled: blockers.length > 0, tip: () => regimentTypeTooltip(app, def) + reasonsHtml(app, blockers) }));
  }
  return section(`🛡 ${app.t('ui.regiments')} — ${app.t('ui.regiments_n', { n: regs.length, cap })}`,
    h('p', { class: 'hint' }, app.t('ui.regiments_hint')), list,
    h('div', { class: 'section-sub' }, app.t('ui.recruit_regiment')), shop);
}

/** Состав армии (для окна армии). */
export function armyRegimentsBlock(app: App, a: Army): HTMLElement | null {
  const g = app.game!;
  if (!a.regiments?.length) return null;
  return section(app.t('ui.army_regiments'), ...a.regiments.map((r) => {
    const def = g.content.get<RegimentTypeDef>('regiment_types', r.type);
    return h('div', { class: 'regiment-row small', tip: def ? () => regimentTypeTooltip(app, def) : undefined },
      h('span', { class: 'reg-icon' }, def?.icon ?? '⚔'), `${g.nameOf('regiment_types', r.type)} — ${fmt(r.size)}`);
  }));
}
