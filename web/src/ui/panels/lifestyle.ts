import {
  type PerkDef,
  canUnlockPerk,
  currentLifestyle,
  focusChangeBlockedUntil,
  focusesOf,
  hasPerk,
  isFocusShown,
  lifestyles,
  monthlyXp,
  perkCost,
  perkRequirementsMet,
  setFocus,
  treesOf,
  unlockPerk,
} from '../../engine/features/lifestyles';
import { makeContext } from '../../engine/script/context';
import { describeEffect } from '../../engine/script/interpreter';
import type { Character } from '../../engine/types';
import type { App } from '../app';
import { esc, fmt, h } from '../dom';
import { bar, button, descLinesHtml, modifiersHtml, section } from '../widgets';

/** Вкладка «Образ жизни» игрока: фокусы, опыт и деревья перков. */
export function renderLifestylePanel(app: App): HTMLElement {
  const g = app.game!;
  const p = g.player!;
  const root = h('div', { class: 'lifestyle-panel' });
  const all = lifestyles(g);
  if (!all.length) return root;
  const cur = currentLifestyle(g, p);
  const viewId = app.lifestyleView && all.some((l) => l.id === app.lifestyleView) ? app.lifestyleView : (cur?.id ?? all[0].id);

  // переключатель образов жизни
  root.append(h('div', { class: 'ls-tabs' }, ...all.map((l) =>
    button(h('span', null, `${l.icon ?? '•'} `, g.nameOf('lifestyles', l.id)), () => { app.lifestyleView = l.id; app.markDirty(true); }, {
      cls: `ls-tab ${l.id === viewId ? 'active' : ''} ${l.id === cur?.id ? 'current' : ''}`,
      tip: app.t('ui.lifestyle_skill', { skill: g.nameOf('skills', l.skill) }),
    }))));

  const view = all.find((l) => l.id === viewId)!;
  const xp = Math.floor(p.lifestyle?.xp[view.id] ?? 0);
  const cost = perkCost(g, p, view.id);
  const trees = treesOf(g, view.id);
  const allDone = trees.every((t) => t.perks.every((x) => hasPerk(p, x.id)));
  const head = h('div', { class: 'ls-head', style: { borderColor: view.color } },
    h('div', { class: 'ls-title' }, `${view.icon ?? ''} ${g.nameOf('lifestyles', view.id)}`),
    allDone ? h('div', { class: 'good' }, app.t('ui.lifestyle_all_done')) : h('div', null, app.t('ui.lifestyle_xp', { xp: fmt(xp), cost: fmt(cost) }), bar(xp, cost)),
    view.id === cur?.id ? h('div', { class: 'muted' }, app.t('ui.lifestyle_xp_month', { n: fmt(monthlyXp(g, p), 1) })) : null,
  );
  root.append(head);

  // фокусы
  const block = focusChangeBlockedUntil(g, p);
  const focusRow = h('div', { class: 'ls-focuses' });
  for (const f of focusesOf(g, view.id)) {
    if (!isFocusShown(g, p, f.id)) continue;
    const active = p.lifestyle?.focus === f.id;
    focusRow.append(h('div', {
      class: ['ls-focus', active && 'active'],
      tip: () => `<div class="tip-title">${esc(f.icon ?? '')} ${esc(g.nameOf('focuses', f.id))}</div><p>${esc(g.descOf('focuses', f.id))}</p>${modifiersHtml(app, f.modifiers)}${!active && block ? `<div class="tip-bad">${esc(app.t('ui.focus_cooldown', { days: block - g.date }))}</div>` : ''}`,
      onclick: () => {
        if (active || block) return;
        setFocus(g, p, f.id);
        app.markDirty(true);
      },
    }, h('div', { class: 'ls-focus-icon' }, f.icon ?? '◆'), h('div', { class: 'ls-focus-name' }, g.nameOf('focuses', f.id)), active ? h('div', { class: 'ls-focus-mark' }, '✔') : null));
  }
  root.append(section(app.t('ui.focus'), focusRow));

  // деревья
  const treesEl = h('div', { class: 'ls-trees' });
  for (const t of trees) {
    const col = h('div', { class: 'ls-tree' }, h('div', { class: 'ls-tree-name' }, g.loc.tOr(`perk_tree.${t.tree}`, t.tree)));
    t.perks.forEach((perk, i) => {
      if (i) col.append(h('div', { class: 'ls-link' }));
      col.append(perkNode(app, p, perk, xp, cost));
    });
    treesEl.append(col);
  }
  root.append(treesEl);
  return root;
}

function perkNode(app: App, p: Character, perk: PerkDef, xp: number, cost: number): HTMLElement {
  const g = app.game!;
  const owned = hasPerk(p, perk.id);
  const reqOk = perkRequirementsMet(g, p, perk);
  const can = canUnlockPerk(g, p, perk.id);
  return h('div', {
    class: ['ls-perk', owned ? 'owned' : can ? 'available' : reqOk ? 'next' : 'locked'],
    tip: () => perkTooltip(app, p, perk, owned, reqOk, xp, cost),
    onclick: () => {
      if (!can) return;
      unlockPerk(g, p, perk.id);
      app.markDirty(true);
    },
  }, h('span', { class: 'ls-perk-icon' }, perk.icon ?? '◆'), h('span', { class: 'ls-perk-name' }, g.nameOf('perks', perk.id)));
}

export function perkTooltip(app: App, p: Character, perk: PerkDef, owned: boolean, reqOk: boolean, xp: number, cost: number): string {
  const g = app.game!;
  let html = `<div class="tip-title">${esc(perk.icon ?? '')} ${esc(g.nameOf('perks', perk.id))}</div>`;
  const desc = g.descOf('perks', perk.id);
  if (desc) html += `<p>${esc(desc)}</p>`;
  html += modifiersHtml(app, perk.modifiers);
  if (perk.trait) html += `<div class="good">${esc(app.t('ui.perk_grants_trait', { trait: g.nameOf('traits', perk.trait) }))}</div>${modifiersHtml(app, g.content.get('traits', perk.trait)?.modifiers)}`;
  if (perk.effect) {
    const ctx = makeContext(g, { type: 'character', id: p.id });
    html += descLinesHtml(describeEffect(ctx, ctx.root, perk.effect));
  }
  if (owned) html += `<div class="good">✔ ${esc(app.t('ui.perk_owned'))}</div>`;
  else if (!reqOk) html += `<div class="tip-bad">✗ ${esc(app.t('ui.perk_locked'))}</div>`;
  else if (xp < cost) html += `<div class="tip-bad">✗ ${esc(app.t('ui.perk_need_xp', { cost: fmt(cost), xp: fmt(xp) }))}</div>`;
  else html += `<div class="good">${esc(app.t('ui.perk_unlock'))}</div>`;
  return html;
}

/** Компактный блок для окна любого персонажа. */
export function lifestyleSummary(app: App, c: Character): HTMLElement | null {
  const g = app.game!;
  const st = c.lifestyle;
  if (!st || (!st.focus && !st.perks.length)) return null;
  const f = st.focus ? g.content.get('focuses', st.focus) : undefined;
  const row = h('div', { class: 'ls-summary' });
  if (f) row.append(h('span', { class: 'ls-sum-focus', tip: () => `<div class="tip-title">${esc(app.t('ui.focus_n', { name: g.nameOf('focuses', f.id) }))}</div>${modifiersHtml(app, f.modifiers)}` }, `${f.icon ?? '◆'} ${g.nameOf('focuses', f.id)}`));
  for (const id of st.perks) {
    const perk = g.content.get<PerkDef>('perks', id);
    if (!perk) continue;
    row.append(h('span', { class: 'ls-sum-perk', tip: () => perkTooltip(app, c, perk, true, true, 0, 0) }, perk.icon ?? '◆'));
  }
  return row;
}
