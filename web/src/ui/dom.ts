/**
 * Крошечный DOM-хелпер без фреймворков: h('div', { class: 'x', onclick }, ...children).
 */
export type Child = Node | string | number | null | undefined | false | Child[];

export function h<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attrs?: Record<string, any> | null,
  ...children: Child[]
): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  if (attrs) {
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null || v === false) continue;
      if (k === 'class') el.className = Array.isArray(v) ? v.filter(Boolean).join(' ') : v;
      else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
      else if (k === 'tip') setTip(el, v);
      else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v);
      else if (k === 'html') el.innerHTML = v;
      else if (v === true) el.setAttribute(k, '');
      else el.setAttribute(k, String(v));
    }
  }
  append(el, children);
  return el;
}

export function append(el: Node, children: Child[]): void {
  for (const c of children) {
    if (c == null || c === false) continue;
    if (Array.isArray(c)) append(el, c);
    else if (c instanceof Node) el.appendChild(c);
    else el.appendChild(document.createTextNode(String(c)));
  }
}

export function clear(el: Element): void {
  while (el.firstChild) el.removeChild(el.firstChild);
}

export function svg(markup: string, cls = ''): HTMLElement {
  const span = document.createElement('span');
  span.className = `svg ${cls}`;
  span.innerHTML = markup;
  return span;
}

// ------------------------------------------------------------ подсказки

type TipContent = string | Node | (() => string | Node | null);
const tips = new WeakMap<Element, TipContent>();
let tipEl: HTMLElement | null = null;
let tipAnchor: Element | null = null;

export function setTip(el: Element, content: TipContent | null | undefined): void {
  if (content == null || content === '') tips.delete(el);
  else tips.set(el, content);
  el.classList.toggle('has-tip', !!content);
}

function findTip(target: EventTarget | null): Element | null {
  let el = target as Element | null;
  while (el && el !== document.body) {
    if (tips.has(el)) return el;
    el = el.parentElement;
  }
  return null;
}

export function initTooltips(): void {
  tipEl = h('div', { class: 'tooltip' });
  document.body.appendChild(tipEl);
  document.addEventListener('mouseover', (e) => {
    const a = findTip(e.target);
    if (a === tipAnchor) return;
    tipAnchor = a;
    if (!a) return hideTip();
    const c = tips.get(a)!;
    const content = typeof c === 'function' ? c() : c;
    if (!content) return hideTip();
    clear(tipEl!);
    if (typeof content === 'string') tipEl!.innerHTML = content;
    else tipEl!.appendChild(content);
    tipEl!.style.display = 'block';
    // начальная позиция — под элементом (до первого движения мыши)
    const ar = a.getBoundingClientRect();
    const tr = tipEl!.getBoundingClientRect();
    let x = Math.min(window.innerWidth - tr.width - 4, Math.max(4, ar.left));
    let y = ar.bottom + 6;
    if (y + tr.height > window.innerHeight - 4) y = Math.max(4, ar.top - tr.height - 6);
    tipEl!.style.left = `${x}px`;
    tipEl!.style.top = `${y}px`;
  });
  document.addEventListener('mousemove', (e) => {
    if (!tipEl || tipEl.style.display !== 'block') return;
    if (tipAnchor && !document.contains(tipAnchor)) return hideTip();
    const pad = 16;
    const r = tipEl.getBoundingClientRect();
    let x = e.clientX + pad;
    let y = e.clientY + pad;
    if (x + r.width > window.innerWidth - 4) x = e.clientX - r.width - pad;
    if (y + r.height > window.innerHeight - 4) y = Math.max(4, window.innerHeight - r.height - 4);
    tipEl.style.left = `${Math.max(4, x)}px`;
    tipEl.style.top = `${y}px`;
  });
  document.addEventListener('mousedown', () => hideTip());
}

/** Показывает «внешнюю» подсказку (например, при наведении на карту). */
export function showFloatingTip(content: string | null, x: number, y: number): void {
  if (!tipEl) return;
  if (!content) {
    if (!tipAnchor) tipEl.style.display = 'none';
    return;
  }
  tipAnchor = null;
  tipEl.innerHTML = content;
  tipEl.style.display = 'block';
  const r = tipEl.getBoundingClientRect();
  let left = x + 18;
  if (left + r.width > window.innerWidth - 4) left = x - r.width - 18;
  let top = y + 18;
  if (top + r.height > window.innerHeight - 4) top = window.innerHeight - r.height - 4;
  tipEl.style.left = `${left}px`;
  tipEl.style.top = `${top}px`;
}

export function hideTip(): void {
  if (tipEl) tipEl.style.display = 'none';
  tipAnchor = null;
}

export function esc(s: string): string {
  return s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!);
}

export function fmt(n: number, digits = 0): string {
  const v = Math.round(n * 10 ** digits) / 10 ** digits;
  return v.toLocaleString('ru-RU', { minimumFractionDigits: digits, maximumFractionDigits: digits });
}

export function signed(n: number, digits = 0): string {
  const s = fmt(n, digits);
  return n > 0 ? `+${s}` : s;
}
