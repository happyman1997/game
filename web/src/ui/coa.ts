/**
 * Процедурные гербы (SVG). Герб можно задать в данных титула или династии:
 *   coa: { field: azure, division: per_pale, field2: gules,
 *          ordinary: cross, ordinary_tincture: or,
 *          charge: fleur, charge_tincture: or, count: 3 }
 * Если не задан — генерируется детерминированно из id.
 */
import { Rng, hashString } from '../engine/core/rng';

export const TINCTURES: Record<string, string> = {
  or: '#e2b43c',
  argent: '#efeee6',
  gules: '#b4262a',
  azure: '#2a4f9e',
  vert: '#2e7a3c',
  sable: '#262422',
  purpure: '#6a3a86',
};
const METALS = ['or', 'argent'];
const COLOURS = ['gules', 'azure', 'vert', 'sable', 'purpure'];

export interface CoaSpec {
  field: string;
  division?: string;
  field2?: string;
  ordinary?: string;
  ordinary_tincture?: string;
  charge?: string;
  charge_tincture?: string;
  count?: number;
}

const CHARGES: Record<string, string> = {
  roundel: '<circle cx="0" cy="0" r="7"/>',
  mullet: '<path d="M0 -9 L2.6 -2.8 L9 -2.8 L3.8 1.2 L5.6 8 L0 4 L-5.6 8 L-3.8 1.2 L-9 -2.8 L-2.6 -2.8 Z"/>',
  lozenge: '<path d="M0 -9 L6 0 L0 9 L-6 0 Z"/>',
  cross: '<path d="M-2.5 -9 H2.5 V-2.5 H9 V2.5 H2.5 V9 H-2.5 V2.5 H-9 V-2.5 H-2.5 Z"/>',
  crescent: '<path d="M-7 -2 A7.5 7.5 0 1 0 7 -2 A6 6 0 1 1 -7 -2 Z"/>',
  crown: '<path d="M-9 5 L-9 -4 L-4.5 0 L0 -7 L4.5 0 L9 -4 L9 5 Z"/>',
  fleur: '<path d="M0 -10 C4 -6 4 -2 0 2 C-4 -2 -4 -6 0 -10 Z M-1.5 2 C-6 -4 -11 -1 -7 4 C-5 6 -2 4 -1.5 2 Z M1.5 2 C6 -4 11 -1 7 4 C5 6 2 4 1.5 2 Z M-5 4 H5 V6 H-5 Z M-1 6 H1 L0 10 Z"/>',
  tower: '<path d="M-6 9 V-3 H-7 V-8 H-4 V-6 H-1.5 V-8 H1.5 V-6 H4 V-8 H7 V-3 H6 V9 Z M-2 9 V4 A2 2 0 0 1 2 4 V9 Z" fill-rule="evenodd"/>',
};

function contrast(base: string, rng: Rng): string {
  return METALS.includes(base) ? rng.pick(COLOURS)! : rng.pick(METALS)!;
}

export function randomCoa(seed: string): CoaSpec {
  const rng = new Rng({ s: hashString(seed) });
  const field = rng.chance(0.4) ? rng.pick(METALS)! : rng.pick(COLOURS)!;
  const spec: CoaSpec = { field };
  const r = rng.next();
  if (r < 0.25) {
    spec.division = rng.pick(['per_pale', 'per_fess', 'quarterly', 'per_bend'])!;
    spec.field2 = contrast(field, rng);
  }
  if (!spec.division && rng.chance(0.55)) {
    spec.ordinary = rng.pick(['cross', 'saltire', 'fess', 'pale', 'bend', 'chevron', 'chief', 'bordure'])!;
    spec.ordinary_tincture = contrast(field, rng);
  }
  if (rng.chance(0.6)) {
    spec.charge = rng.pick(Object.keys(CHARGES))!;
    const base = spec.ordinary === 'chief' || spec.ordinary === 'bordure' ? field : spec.division ? field : field;
    spec.charge_tincture = contrast(base, rng);
    spec.count = rng.pick([1, 1, 2, 3, 3])!;
  }
  return spec;
}

const SHIELD = 'M6 6 H94 V52 Q94 88 50 106 Q6 88 6 52 Z';
const cache = new Map<string, string>();

export function coaSvg(spec: CoaSpec | undefined | null, seed: string, size = 40): string {
  const key = `${seed}:${size}:${JSON.stringify(spec ?? null)}`;
  const c = cache.get(key);
  if (c) return c;
  const s = { ...randomCoa(seed), ...(spec ?? {}) } as CoaSpec;
  if (spec && !spec.division) delete s.division;
  if (spec && !spec.ordinary) delete s.ordinary;
  if (spec && !spec.charge) delete s.charge;
  const t = (n?: string) => TINCTURES[n ?? ''] ?? n ?? '#888';
  const id = `c${(hashString(key) >>> 0).toString(36)}`;
  const parts: string[] = [];
  parts.push(`<defs><clipPath id="${id}"><path d="${SHIELD}"/></clipPath><linearGradient id="${id}g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.35"/><stop offset="0.5" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.3"/></linearGradient></defs>`);
  parts.push(`<g clip-path="url(#${id})"><rect width="100" height="110" fill="${t(s.field)}"/>`);
  const f2 = t(s.field2);
  switch (s.division) {
    case 'per_pale': parts.push(`<rect x="50" width="50" height="110" fill="${f2}"/>`); break;
    case 'per_fess': parts.push(`<rect y="52" width="100" height="60" fill="${f2}"/>`); break;
    case 'quarterly': parts.push(`<rect x="50" width="50" height="52" fill="${f2}"/><rect y="52" width="50" height="60" fill="${f2}"/>`); break;
    case 'per_bend': parts.push(`<path d="M0 0 L100 110 L0 110 Z" fill="${f2}"/>`); break;
  }
  const o = t(s.ordinary_tincture);
  switch (s.ordinary) {
    case 'cross': parts.push(`<rect x="41" width="18" height="110" fill="${o}"/><rect y="38" width="100" height="18" fill="${o}"/>`); break;
    case 'saltire': parts.push(`<path d="M0 0 L100 110 M100 0 L0 110" stroke="${o}" stroke-width="16"/>`); break;
    case 'fess': parts.push(`<rect y="40" width="100" height="22" fill="${o}"/>`); break;
    case 'pale': parts.push(`<rect x="38" width="24" height="110" fill="${o}"/>`); break;
    case 'bend': parts.push(`<path d="M0 0 L100 110" stroke="${o}" stroke-width="18"/>`); break;
    case 'chevron': parts.push(`<path d="M0 90 L50 40 L100 90" stroke="${o}" stroke-width="16" fill="none"/>`); break;
    case 'chief': parts.push(`<rect width="100" height="32" fill="${o}"/>`); break;
    case 'bordure': parts.push(`<path d="${SHIELD}" fill="none" stroke="${o}" stroke-width="16"/>`); break;
  }
  if (s.charge && CHARGES[s.charge]) {
    const n = Math.max(1, Math.min(3, s.count ?? 1));
    const pos: [number, number, number][] =
      n === 1 ? [[50, s.ordinary === 'chief' ? 64 : 52, 2.2]] : n === 2 ? [[32, 46, 1.4], [68, 46, 1.4]] : [[30, 32, 1.3], [70, 32, 1.3], [50, 72, 1.3]];
    for (const [x, y, k] of pos) parts.push(`<g transform="translate(${x} ${y}) scale(${k})" fill="${t(s.charge_tincture)}" stroke="#00000055" stroke-width="0.5">${CHARGES[s.charge]}</g>`);
  }
  parts.push(`<rect width="100" height="110" fill="url(#${id}g)"/></g>`);
  parts.push(`<path d="${SHIELD}" fill="none" stroke="#2a1d0e" stroke-width="3"/>`);
  const out = `<svg viewBox="0 0 100 112" width="${size}" height="${Math.round(size * 1.12)}" xmlns="http://www.w3.org/2000/svg">${parts.join('')}</svg>`;
  if (cache.size > 3000) cache.clear();
  cache.set(key, out);
  return out;
}
