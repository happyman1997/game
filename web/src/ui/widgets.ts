/** Общие элементы интерфейса: ссылки на персонажей/титулы, портреты, кнопки. */
import { makeContext } from '../engine/script/context';
import { type DescLine, describeEffect } from '../engine/script/interpreter';
import type { Character, ScopeRef } from '../engine/types';
import { charFullName } from '../engine/world/characters';
import { titleFullName } from '../engine/world/titles';
import type { App } from './app';
import { coaSvg } from './coa';
import { type Child, esc, fmt, h, signed, svg } from './dom';
import { portraitSvg } from './portrait';

export function portrait(app: App, c: Character, size = 72, clickable = true): HTMLElement {
  const el = svg(portraitSvg(app.game!, c, size), 'portrait');
  if (clickable) {
    el.classList.add('clickable');
    el.addEventListener('click', () => app.openCharacter(c.id));
  }
  return el;
}

export function titleCoa(app: App, titleId: string | undefined, size = 32): HTMLElement {
  const g = app.game!;
  if (!titleId) return h('span', { class: 'coa-empty' });
  const def = g.content.get('titles', titleId);
  const el = svg(coaSvg(def?.coa, titleId, size), 'coa clickable');
  el.addEventListener('click', () => app.openTitle(titleId));
  return el;
}

export function dynastyCoa(app: App, dynId: string | undefined, size = 32): HTMLElement {
  const g = app.game!;
  if (!dynId) return h('span', { class: 'coa-empty' });
  const st = g.state.dynasties[dynId];
  const def = g.content.get('dynasties', dynId);
  return svg(coaSvg(def?.coa ?? st?.coa, dynId, size), 'coa');
}

export function charLink(app: App, id: string | undefined | null, withRank = false): Child {
  const g = app.game!;
  const c = g.char(id);
  if (!c) return h('span', { class: 'muted' }, '—');
  const dead = c.death !== undefined;
  return h(
    'a',
    {
      class: ['link', 'char-link', dead && 'dead', g.isPlayer(c.id) && 'is-player'],
      onclick: (e: Event) => {
        e.stopPropagation();
        app.openCharacter(c.id);
      },
      tip: () => app.characterTooltip(c.id),
    },
    charFullName(g, c, withRank),
    dead ? ' ✝' : '',
  );
}

export function titleLink(app: App, id: string | undefined): Child {
  const g = app.game!;
  if (!id) return h('span', { class: 'muted' }, '—');
  return h('a', { class: 'link title-link', onclick: () => app.openTitle(id) }, titleFullName(g, id));
}

export function provLink(app: App, id: string | undefined): Child {
  const g = app.game!;
  if (!id) return h('span', { class: 'muted' }, '—');
  return h('a', { class: 'link prov-link', onclick: () => app.openProvince(id, true) }, g.nameOf('provinces', id));
}

export function scopeLink(app: App, ref: ScopeRef | undefined): Child {
  if (!ref) return null;
  if (ref.type === 'character') return charLink(app, ref.id);
  if (ref.type === 'title') return titleLink(app, ref.id);
  if (ref.type === 'province') return provLink(app, ref.id);
  return app.game!.scopeName(ref);
}

export function button(label: Child, onclick: () => void, opts: { disabled?: boolean; tip?: any; cls?: string } = {}): HTMLButtonElement {
  return h(
    'button',
    {
      class: ['btn', opts.cls],
      disabled: opts.disabled,
      tip: opts.tip,
      onclick: (e: Event) => {
        e.stopPropagation();
        if (!opts.disabled) onclick();
      },
    },
    label,
  );
}

export function section(title: Child, ...children: Child[]): HTMLElement {
  return h('div', { class: 'section' }, h('div', { class: 'section-title' }, title), ...children);
}

export function bar(value: number, max: number, cls = ''): HTMLElement {
  const pct = Math.max(0, Math.min(100, (value / Math.max(1e-9, max)) * 100));
  return h('div', { class: `bar ${cls}` }, h('div', { class: 'bar-fill', style: { width: `${pct}%` } }));
}

export function costText(app: App, cost: { gold?: number; prestige?: number; piety?: number }): string {
  const parts: string[] = [];
  if (cost.gold) parts.push(`${fmt(cost.gold)} 💰`);
  if (cost.prestige) parts.push(`${fmt(cost.prestige)} ⭐`);
  if (cost.piety) parts.push(`${fmt(cost.piety)} ✝`);
  return parts.join(' · ') || app.t('ui.free');
}

/** HTML-список строк описания эффекта для подсказки. */
export function descLinesHtml(lines: DescLine[]): string {
  if (!lines.length) return '';
  return `<div class="fx-lines">${lines.map((l) => `<div class="fx-line" style="padding-left:${l.depth * 12}px">${esc(l.text)}</div>`).join('')}</div>`;
}

export function effectTooltip(app: App, block: unknown, root: ScopeRef, scopes: Record<string, ScopeRef> = {}, header?: string): string {
  const g = app.game!;
  const ctx = makeContext(g, root, scopes);
  const lines = describeEffect(ctx, root, block);
  return `${header ? `<div class="tip-title">${esc(header)}</div>` : ''}${descLinesHtml(lines)}`;
}

export function reasonsHtml(app: App, reasons: string[]): string {
  if (!reasons.length) return '';
  return `<div class="tip-bad">${reasons.map((r) => `✗ ${esc(r)}`).join('<br>')}</div>`;
}

export function breakdownHtml(parts: { label: string; value: number }[], digits = 0): string {
  return parts.map((p) => `<div class="bd-row"><span>${esc(p.label)}</span><span class="${p.value >= 0 ? 'good' : 'bad'}">${signed(p.value, digits)}</span></div>`).join('');
}

export function modifiersHtml(app: App, mods: Record<string, number> | undefined): string {
  if (!mods) return '';
  return Object.entries(mods)
    .map(([k, v]) => {
      const bad = k === 'stress_gain_mult' ? v > 0 : v < 0;
      const pct = /mult/.test(k) || k === 'fertility';
      const val = pct ? `${v > 0 ? '+' : ''}${Math.round(v * 100)}%` : signed(v, Math.abs(v) < 1 ? 1 : 0);
      return `<div class="bd-row"><span>${esc(app.game!.loc.tOr(`stat.${k}`, k))}</span><span class="${bad ? 'bad' : 'good'}">${val}</span></div>`;
    })
    .join('');
}
