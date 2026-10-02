import { deepMerge, isPlainObject } from '../core/merge';
import { hashString } from '../core/rng';
import type { ContentStore } from './store';
import type { ProvinceDef, TitleDef } from './defs';

/** Значения по умолчанию — мод core (и любые другие) их переопределяют. */
export const DEFAULT_DEFINES = {
  character: {
    adult_age: 16,
    marriage_age: 16,
    base_health: 5,
    personality_traits: 3,
    base_stats: { fertility: 0.5 },
  },
  economy: {},
  military: {},
  war: {},
  ai: {},
  opinion: {},
  titles: { create_fraction: 0.51 },
  succession: { default_law: 'partition' },
  script_stat_values: ['general_opinion', 'vassal_opinion', 'monthly_prestige', 'monthly_piety', 'prowess'],
};

export function parseColor(c: unknown, fallbackSeed: string): string {
  if (typeof c === 'string' && /^#?[0-9a-f]{6}$/i.test(c)) return c.startsWith('#') ? c : `#${c}`;
  if (Array.isArray(c) && c.length >= 3) {
    return `#${c
      .slice(0, 3)
      .map((x) => Math.max(0, Math.min(255, Math.round(Number(x) <= 1 && c.every((y) => Number(y) <= 1) ? Number(x) * 255 : Number(x)))).toString(16).padStart(2, '0'))
      .join('')}`;
  }
  const h = hashString(fallbackSeed);
  const hue = (h >>> 0) % 360;
  return hslToHex(hue, 45, 45);
}

export function hslToHex(h: number, s: number, l: number): string {
  s /= 100;
  l /= 100;
  const k = (n: number) => (n + h / 30) % 12;
  const a = s * Math.min(l, 1 - l);
  const f = (n: number) => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
  return `#${[f(0), f(8), f(4)].map((x) => Math.round(x * 255).toString(16).padStart(2, '0')).join('')}`;
}

export function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace('#', '');
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
}

function vary(hex: string, seed: string, amount = 18): string {
  const [r, g, b] = hexToRgb(hex);
  const h = hashString(seed);
  const d = ((h & 0xff) / 255 - 0.5) * 2 * amount;
  const clamp = (x: number) => Math.max(0, Math.min(255, Math.round(x + d)));
  return `#${[clamp(r), clamp(g), clamp(b)].map((x) => x.toString(16).padStart(2, '0')).join('')}`;
}

/**
 * Приводит контент к каноническому виду: значения по умолчанию,
 * графства из провинций, цвета и т.п. Вызывается после загрузки модов,
 * до инициализации их скриптов.
 */
export function normalizeContent(content: ContentStore): void {
  content.setSingleton('defines', deepMerge(DEFAULT_DEFINES, content.singleton('defines')));

  for (const t of content.all<TitleDef>('titles')) {
    if (!['county', 'duchy', 'kingdom', 'empire'].includes(t.tier)) t.tier = 'duchy';
  }
  for (const t of content.all<TitleDef>('titles')) {
    t.color = parseColor(t.color, t.id);
  }
  for (const p of content.all<ProvinceDef>('provinces')) {
    p.holdings ??= ['castle'];
    p.development ??= 5;
    if (p.impassable) continue;
    const existing = content.get<TitleDef>('titles', p.id);
    const duchy = p.duchy ?? existing?.liege;
    const duchyColor = duchy ? content.get<TitleDef>('titles', duchy)?.color : undefined;
    content.set('titles', p.id, {
      ...(existing ?? {}),
      tier: 'county',
      liege: duchy,
      color: existing?.color && existing.color !== parseColor(undefined, p.id) ? existing.color : p.color ? parseColor(p.color, p.id) : duchyColor ? vary(duchyColor, p.id) : parseColor(undefined, p.id),
      capital: p.id,
      province: p.id,
    });
  }
  for (const c of content.all('cultures')) {
    c.color = parseColor(c.color, c.id);
    c.male_names ??= ['John'];
    c.female_names ??= ['Mary'];
  }
  for (const f of content.all('faiths')) f.color = parseColor(f.color, f.id);
  for (const t of content.all('terrain')) {
    t.color = parseColor(t.color, t.id);
    t.defense ??= 0;
    t.movement ??= 1;
    t.height ??= 0.2;
  }
  for (const e of content.all('events')) {
    if (e.options && !Array.isArray(e.options)) e.options = Object.values(e.options);
  }
  for (const oa of content.all('on_actions')) {
    if (oa.events && !Array.isArray(oa.events)) oa.events = Object.keys(oa.events);
  }
  for (const s of content.all('skills')) s.color = parseColor(s.color, s.id);
  for (const t of content.all('traits')) {
    if (t.modifiers && !isPlainObject(t.modifiers)) t.modifiers = {};
  }
}
