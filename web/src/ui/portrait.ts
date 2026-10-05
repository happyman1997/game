/**
 * Процедурные портреты персонажей (SVG). Внешность берётся из «генов»
 * персонажа (dna), возраста, пола и ранга. Мод может заменить генератор:
 * window.CAD_PORTRAIT = (game, character) => '<svg>...</svg>'.
 */
import { hashString } from '../engine/core/rng';
import type { Game } from '../engine/game';
import type { Character } from '../engine/types';
import { ageOf } from '../engine/world/characters';
import { primaryTier } from '../engine/world/titles';

const HAIR = ['#1b1410', '#33221a', '#52341f', '#7a4d29', '#9c4a24', '#b88a4e', '#d9bb7c'];
const cache = new Map<string, string>();

function mix(a: string, b: string, t: number): string {
  const pa = [1, 3, 5].map((i) => parseInt(a.slice(i, i + 2), 16));
  const pb = [1, 3, 5].map((i) => parseInt(b.slice(i, i + 2), 16));
  return `#${pa.map((v, i) => Math.round(v + (pb[i] - v) * t).toString(16).padStart(2, '0')).join('')}`;
}

export function portraitSvg(game: Game, c: Character, size = 96): string {
  const custom = (globalThis as any).CAD_PORTRAIT;
  if (typeof custom === 'function') return custom(game, c, size);
  const age = ageOf(game, c);
  const tier = primaryTier(game, c);
  const dead = c.death !== undefined;
  const clothes = c.titles[0] ? game.content.get('titles', c.titles[0])?.color ?? '#5a4a3a' : c.dynasty ? '#6a5a48' : '#5a5048';
  const key = `${c.id}:${age}:${tier}:${dead}:${clothes}:${size}`;
  const cached = cache.get(key);
  if (cached) return cached;
  const h = hashString(c.id) >>> 0;
  const skin = mix('#f3d6bf', '#a87a58', c.dna.skin);
  let hair = HAIR[Math.min(HAIR.length - 1, Math.floor(c.dna.hair * HAIR.length))];
  if (age > 45) hair = mix(hair, '#c8c8c4', Math.min(1, (age - 45) / 30));
  const child = age < 14;
  const s = child ? 0.86 : 1;
  const headY = child ? 54 : 50;
  const faceW = 19 + c.dna.face * 4;
  const eyeY = headY - 2;
  const beard = !c.female && age >= 18;
  const beardStyle = h % 3;
  const hairStyle = (h >> 3) % 3;
  const cy = headY - 26 * s;

  const parts: string[] = [];
  parts.push(`<defs><radialGradient id="bg${h}" cx="50%" cy="35%" r="75%"><stop offset="0" stop-color="${mix(clothes, '#ffffff', 0.25)}"/><stop offset="1" stop-color="${mix(clothes, '#000000', 0.55)}"/></radialGradient></defs>`);
  parts.push(`<rect width="100" height="120" fill="url(#bg${h})"/>`);
  // плечи
  parts.push(`<path d="M10 120 Q14 ${92 + (child ? 6 : 0)} 50 ${88 + (child ? 6 : 0)} Q86 ${92 + (child ? 6 : 0)} 90 120 Z" fill="${mix(clothes, '#000', 0.15)}" stroke="#00000055"/>`);
  parts.push(`<path d="M38 ${90 + (child ? 6 : 0)} L50 ${104 + (child ? 4 : 0)} L62 ${90 + (child ? 6 : 0)}" fill="none" stroke="${mix(clothes, '#fff', 0.4)}" stroke-width="2"/>`);
  // волосы сзади (длинные у женщин)
  if (c.female) parts.push(`<path d="M${50 - faceW - 4} ${headY - 8} Q${50 - faceW - 8} ${headY + 34} ${50 - faceW + 4} ${headY + 40} L${50 + faceW - 4} ${headY + 40} Q${50 + faceW + 8} ${headY + 34} ${50 + faceW + 4} ${headY - 8} Z" fill="${hair}"/>`);
  // шея и голова
  parts.push(`<rect x="${50 - 7 * s}" y="${headY + 14 * s}" width="${14 * s}" height="${16 * s}" fill="${mix(skin, '#000', 0.12)}"/>`);
  parts.push(`<ellipse cx="50" cy="${headY}" rx="${faceW * s}" ry="${25 * s}" fill="${skin}" stroke="#00000033"/>`);
  // глаза и брови
  const eyeC = c.dna.eyes > 0.6 ? '#3a5a8a' : c.dna.eyes > 0.3 ? '#4a6a3a' : '#3a2a1a';
  parts.push(`<ellipse cx="${50 - 7 * s}" cy="${eyeY}" rx="2.6" ry="1.8" fill="#fff"/><ellipse cx="${50 + 7 * s}" cy="${eyeY}" rx="2.6" ry="1.8" fill="#fff"/>`);
  parts.push(`<circle cx="${50 - 7 * s}" cy="${eyeY}" r="1.3" fill="${eyeC}"/><circle cx="${50 + 7 * s}" cy="${eyeY}" r="1.3" fill="${eyeC}"/>`);
  parts.push(`<path d="M${50 - 11 * s} ${eyeY - 5} q4 -2 8 0 M${50 + 3 * s} ${eyeY - 5} q4 -2 8 0" stroke="${mix(hair, '#000', 0.3)}" stroke-width="1.4" fill="none"/>`);
  parts.push(`<path d="M50 ${eyeY + 2} l-2 7 h4" stroke="${mix(skin, '#000', 0.3)}" fill="none" stroke-width="1"/>`);
  parts.push(`<path d="M${50 - 5} ${headY + 13 * s} q5 ${c.female ? 3 : 2} 10 0" stroke="${c.female ? '#a0484a' : mix(skin, '#000', 0.4)}" stroke-width="${c.female ? 1.8 : 1.2}" fill="none"/>`);
  if (age > 40) parts.push(`<path d="M${50 - 13} ${eyeY + 6} q3 2 5 0 M${50 + 8} ${eyeY + 6} q3 2 5 0" stroke="#00000033" fill="none"/>`);
  // борода
  if (beard) {
    const bw = faceW * s;
    if (beardStyle === 0) parts.push(`<path d="M${50 - bw + 2} ${headY + 2} Q50 ${headY + 40} ${50 + bw - 2} ${headY + 2} Q50 ${headY + 22} ${50 - bw + 2} ${headY + 2} Z" fill="${hair}"/>`);
    else if (beardStyle === 1) parts.push(`<path d="M${50 - 9} ${headY + 9} Q50 ${headY + 30} ${50 + 9} ${headY + 9} Q50 ${headY + 17} ${50 - 9} ${headY + 9} Z" fill="${hair}"/>`);
    parts.push(`<path d="M${50 - 8} ${headY + 9} q8 -4 16 0" stroke="${hair}" stroke-width="3" fill="none"/>`);
  }
  // волосы сверху
  const top = cy - 2;
  if (c.female) parts.push(`<path d="M${50 - faceW * s - 3} ${headY} Q${50 - faceW * s} ${top - 6} 50 ${top - 4} Q${50 + faceW * s} ${top - 6} ${50 + faceW * s + 3} ${headY} Q${50 + 8} ${top + 8} 50 ${top + 10} Q${50 - 8} ${top + 8} ${50 - faceW * s - 3} ${headY} Z" fill="${hair}"/>`);
  else if (hairStyle === 0 || age > 60) parts.push(`<path d="M${50 - faceW * s - 1} ${headY - 4} Q${50 - faceW * s} ${top - 4} 50 ${top - 3} Q${50 + faceW * s} ${top - 4} ${50 + faceW * s + 1} ${headY - 4} Q50 ${top + 6} ${50 - faceW * s - 1} ${headY - 4} Z" fill="${hair}"/>`);
  else parts.push(`<path d="M${50 - faceW * s - 2} ${headY + 4} Q${50 - faceW * s - 3} ${top - 6} 50 ${top - 4} Q${50 + faceW * s + 3} ${top - 6} ${50 + faceW * s + 2} ${headY + 4} L${50 + faceW * s - 2} ${headY - 6} Q50 ${top + 4} ${50 - faceW * s + 2} ${headY - 6} Z" fill="${hair}"/>`);
  // корона
  const gold = '#e2b84a';
  const ct = top - 6;
  if (tier === 1) parts.push(`<rect x="${50 - 15}" y="${ct + 4}" width="30" height="4" rx="1" fill="${gold}" stroke="#7a5a10" stroke-width="0.6"/>`);
  if (tier === 2) parts.push(`<path d="M35 ${ct + 9} L35 ${ct + 2} L41 ${ct + 6} L50 ${ct - 1} L59 ${ct + 6} L65 ${ct + 2} L65 ${ct + 9} Z" fill="${gold}" stroke="#7a5a10" stroke-width="0.6"/>`);
  if (tier === 3) parts.push(`<path d="M33 ${ct + 10} L33 ${ct - 1} L40 ${ct + 5} L45 ${ct - 4} L50 ${ct + 3} L55 ${ct - 4} L60 ${ct + 5} L67 ${ct - 1} L67 ${ct + 10} Z" fill="${gold}" stroke="#7a5a10" stroke-width="0.7"/><circle cx="50" cy="${ct + 6}" r="1.6" fill="#b02020"/>`);
  if (tier >= 4) parts.push(`<path d="M32 ${ct + 10} L32 ${ct - 2} Q50 ${ct - 16} 68 ${ct - 2} L68 ${ct + 10} Z" fill="${gold}" stroke="#7a5a10" stroke-width="0.7"/><path d="M50 ${ct - 12} v-6 M47 ${ct - 15} h6" stroke="${gold}" stroke-width="2"/><circle cx="42" cy="${ct + 5}" r="1.5" fill="#2050b0"/><circle cx="58" cy="${ct + 5}" r="1.5" fill="#b02020"/>`);
  const filter = dead ? ' style="filter:grayscale(1) brightness(0.8)"' : '';
  const out = `<svg viewBox="0 0 100 120" width="${size}" height="${Math.round(size * 1.2)}"${filter} xmlns="http://www.w3.org/2000/svg">${parts.join('')}</svg>`;
  if (cache.size > 2000) cache.clear();
  cache.set(key, out);
  return out;
}
