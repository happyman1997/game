/**
 * Встроенные режимы карты. Регистрируются в engine.ui.mapModes так же,
 * как режимы из модов (JS) и из данных (map_modes).
 */
import { hexToRgb } from '../../engine/content/normalize';
import type { Engine } from '../../engine/engine';
import type { Game } from '../../engine/game';
import { makeContext } from '../../engine/script/context';
import { evalValue } from '../../engine/script/interpreter';
import type { RGB } from '../../engine/uiRegistry';
import { isInRealmOf, topLiege } from '../../engine/world/titles';
import { isAllied, isAtWarWith } from '../../engine/world/war';

function realmColor(game: Game, prov: string): string | null {
  const h = game.char(game.state.titles[prov]?.holder);
  if (!h) return '#7a7468';
  const top = topLiege(game, h);
  return game.content.get('titles', top.titles[0] ?? '')?.color ?? '#7a7468';
}

function deJureAncestor(game: Game, prov: string, tier: string): string | null {
  let t: string | undefined = prov;
  while (t) {
    const d: any = game.content.get('titles', t);
    if (d?.tier === tier) return d.color;
    t = d?.liege;
  }
  return null;
}

function lerp(a: RGB, b: RGB, t: number): RGB {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
}

export function gradientColor(stops: string[], t: number): RGB {
  const cs = stops.map(hexToRgb);
  if (cs.length === 1) return cs[0];
  const x = Math.max(0, Math.min(1, t)) * (cs.length - 1);
  const i = Math.min(cs.length - 2, Math.floor(x));
  return lerp(cs[i], cs[i + 1], x - i);
}

export function registerBuiltinMapModes(engine: Engine): void {
  const reg = engine.ui.mapModes;
  const add = (id: string, spec: Omit<Parameters<typeof reg.register>[1], 'id'>) => {
    if (!reg.has(id)) reg.register(id, { id, ...spec } as any, 'core');
  };
  add('realms', { name: 'ui.mapmode.realms', icon: '👑', order: 10, color: realmColor });
  add('de_jure_duchy', { name: 'ui.mapmode.de_jure_duchy', icon: '🛡', order: 20, color: (g, p) => deJureAncestor(g, p, 'duchy') });
  add('de_jure_kingdom', { name: 'ui.mapmode.de_jure_kingdom', icon: '🏰', order: 21, color: (g, p) => deJureAncestor(g, p, 'kingdom') });
  add('culture', {
    name: 'ui.mapmode.culture',
    icon: '🗣',
    order: 30,
    color: (g, p) => g.content.get('cultures', g.state.provinces[p]?.culture ?? '')?.color ?? null,
    tooltip: (g, p) => g.nameOf('cultures', g.state.provinces[p]?.culture ?? ''),
  });
  add('faith', {
    name: 'ui.mapmode.faith',
    icon: '✝',
    order: 31,
    color: (g, p) => g.content.get('faiths', g.state.provinces[p]?.faith ?? '')?.color ?? null,
    tooltip: (g, p) => g.nameOf('faiths', g.state.provinces[p]?.faith ?? ''),
  });
  add('terrain', {
    name: 'ui.mapmode.terrain',
    icon: '⛰',
    order: 40,
    color: (g, p) => g.content.get('terrain', g.content.get('provinces', p)?.terrain ?? '')?.color ?? null,
    tooltip: (g, p) => g.nameOf('terrain', g.content.get('provinces', p)?.terrain ?? ''),
  });
  add('diplomacy', {
    name: 'ui.mapmode.diplomacy',
    icon: '🤝',
    order: 15,
    color: (g, p) => {
      const pl = g.player;
      const h = g.char(g.state.titles[p]?.holder);
      if (!pl || !h) return '#6a665e';
      const top = topLiege(g, h);
      if (h.id === pl.id) return '#3f8f4a';
      if (isInRealmOf(g, h, pl)) return '#7bbf6a';
      if (top.id === topLiege(g, pl).id) return '#a8b880';
      if (isAtWarWith(g, pl.id, top.id) || isAtWarWith(g, pl.id, h.id)) return '#b83a32';
      if (isAllied(g, pl.id, top.id)) return '#4a78c0';
      return '#8a857a';
    },
  });
  // Режимы из данных: map_modes { value, min, max, gradient }
  for (const mm of engine.content.all('map_modes')) {
    if (reg.has(mm.id)) continue;
    reg.register(mm.id, {
      id: mm.id,
      name: mm.name ?? `ui.mapmode.${mm.id}`,
      icon: mm.icon ?? '🗺',
      order: mm.order ?? 100,
      color: (g, p) => {
        if (!g.state.provinces[p]) return null;
        const ctx = makeContext(g, { type: 'province', id: p });
        const v = evalValue(ctx, ctx.root, mm.value ?? 0);
        const t = (v - (mm.min ?? 0)) / Math.max(1e-9, (mm.max ?? 1) - (mm.min ?? 0));
        return gradientColor(mm.gradient ?? ['#333333', '#ffffff'], t);
      },
      tooltip: (g, p) => {
        if (!g.state.provinces[p]) return null;
        const ctx = makeContext(g, { type: 'province', id: p });
        return String(Math.round(evalValue(ctx, ctx.root, mm.value ?? 0) * 10) / 10);
      },
    }, 'data');
  }
}
