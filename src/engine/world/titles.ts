import type { TitleDef } from '../content/defs';
import type { Game } from '../game';
import { type Character, type Tier, tierRank } from '../types';
import { setLiege } from './characters';

export function tierOf(game: Game, titleId: string): number {
  const d = game.content.get<TitleDef>('titles', titleId);
  return d ? tierRank(d.tier) : 0;
}

export function primaryTier(game: Game, c: Character): number {
  return c.titles.length ? tierOf(game, c.titles[0]) : 0;
}

export function deJureLiege(game: Game, titleId: string): string | undefined {
  return game.content.get<TitleDef>('titles', titleId)?.liege;
}

/** Все графства, входящие де-юре в титул (для графства — оно само). */
export function deJureCounties(game: Game, titleId: string): string[] {
  const cache = game.engine.cache as Map<string, any>;
  const key = `dejure:${titleId}`;
  let v = cache.get(key) as string[] | undefined;
  if (!v) {
    const children = game.engine.deJureChildren();
    const out: string[] = [];
    const walk = (id: string) => {
      const d = game.content.get<TitleDef>('titles', id);
      if (!d) return;
      if (d.tier === 'county') out.push(id);
      for (const ch of children.get(id) ?? []) walk(ch);
    };
    walk(titleId);
    v = out;
    cache.set(key, v);
  }
  return v;
}

/** Непосредственные де-юре вассальные титулы. */
export function deJureVassalTitles(game: Game, titleId: string): string[] {
  return game.engine.deJureChildren().get(titleId) ?? [];
}

export function domainCounties(game: Game, c: Character): string[] {
  return c.titles.filter((t) => tierOf(game, t) === 1);
}

export function topLiege(game: Game, c: Character): Character {
  let cur = c;
  for (let i = 0; i < 30 && cur.liege; i++) {
    const l = game.char(cur.liege);
    if (!l || l.death !== undefined) break;
    cur = l;
  }
  return cur;
}

export function isIndependent(c: Character): boolean {
  return c.titles.length > 0 && !c.liege;
}

/** Правитель и все его вассалы рекурсивно. */
export function realmMembers(game: Game, c: Character): Character[] {
  const out: Character[] = [];
  const stack = [c];
  const seen = new Set<string>();
  while (stack.length) {
    const x = stack.pop()!;
    if (seen.has(x.id)) continue;
    seen.add(x.id);
    out.push(x);
    for (const v of game.vassalsOf(x.id)) stack.push(v);
  }
  return out;
}

export function realmCounties(game: Game, c: Character): string[] {
  return realmMembers(game, c).flatMap((m) => domainCounties(game, m));
}

/** Состоит ли x в державе ruler (x == ruler или ruler — сюзерен x по цепочке). */
export function isInRealmOf(game: Game, x: Character, ruler: Character): boolean {
  let cur: Character | undefined = x;
  for (let i = 0; i < 30 && cur; i++) {
    if (cur.id === ruler.id) return true;
    cur = game.char(cur.liege);
  }
  return false;
}

export function countyHolder(game: Game, countyId: string): Character | undefined {
  return game.char(game.state.titles[countyId]?.holder);
}

/** Кто контролирует провинцию: оккупант или владелец графства. */
export function provinceController(game: Game, provId: string): Character | undefined {
  const p = game.state.provinces[provId];
  if (!p) return undefined;
  return game.char(p.occupant) ?? countyHolder(game, provId);
}

export function capitalOf(game: Game, c: Character): string | undefined {
  const dom = domainCounties(game, c);
  if (c.capital && dom.includes(c.capital)) return c.capital;
  return dom[0];
}

// ------------------------------------------------------------ имена

export function tierName(game: Game, tier: Tier): string {
  return game.loc.t(`tier.${tier}`);
}

export function titleShortName(game: Game, id: string): string {
  return game.nameOf('titles', id);
}

export function titleFullName(game: Game, id: string): string {
  const full = game.loc.raw(`${id}_full`);
  if (full) return full;
  const d = game.content.get<TitleDef>('titles', id);
  if (!d) return id;
  return `${tierName(game, d.tier)} ${titleShortName(game, id)}`;
}

export function rankName(game: Game, c: Character): string {
  const t = c.titles[0];
  if (!t) return '';
  const d = game.content.get<TitleDef>('titles', t);
  if (!d) return '';
  const g = c.female ? 'f' : 'm';
  return (
    game.loc.raw(`${t}_rank_${g}`) ??
    game.loc.raw(`rank.${c.culture}.${d.tier}.${g}`) ??
    game.loc.raw(`rank.${d.tier}.${g}`) ??
    d.tier
  );
}

// ------------------------------------------------------------ передача титулов

function sortTitles(game: Game, c: Character) {
  const prevPrimary = c.titles[0];
  c.titles.sort((a, b) => {
    const d = tierOf(game, b) - tierOf(game, a);
    if (d) return d;
    if (a === prevPrimary) return -1;
    if (b === prevPrimary) return 1;
    return 0;
  });
}

/**
 * Передаёт титул новому владельцу (или делает его вакантным при undefined).
 * Следит за согласованностью: основной титул, столица, сюзеренитет.
 */
export function transferTitle(game: Game, titleId: string, newHolderId: string | undefined, opts: { court?: string } = {}): void {
  const t = game.state.titles[titleId];
  if (!t) return;
  const old = game.char(t.holder);
  const neo = game.char(newHolderId);
  if (old?.id === neo?.id) return;
  const oldPrimaryTier = neo ? primaryTier(game, neo) : 0;

  if (old) {
    old.titles = old.titles.filter((x) => x !== titleId);
    if (old.capital === titleId) old.capital = domainCounties(game, old)[0];
    if (!old.titles.length && old.death === undefined) becomeUnlanded(game, old, opts.court ?? neo?.id);
  }
  t.holder = neo?.id;
  if (neo) {
    t.history.push({ holder: neo.id, from: game.date });
    if (t.history.length > 30) t.history.splice(0, t.history.length - 30);
    const wasLandless = neo.titles.length === 0;
    neo.titles.push(titleId);
    sortTitles(game, neo);
    neo.claims = neo.claims.filter((x) => x !== titleId);
    if (!neo.capital || !neo.titles.includes(neo.capital)) {
      const cap = game.content.get<TitleDef>('titles', neo.titles[0])?.capital;
      neo.capital = cap && neo.titles.includes(cap) ? cap : domainCounties(game, neo)[0];
    }
    if (wasLandless && neo.liege) {
      // Бывший придворный стал правителем — остаётся вассалом своего покровителя.
    }
    fixLiegeConsistency(game, neo);
    if (primaryTier(game, neo) > oldPrimaryTier) {
      for (const v of game.vassalsOf(neo.id)) fixLiegeConsistency(game, v);
    }
  }
  game.markDirty();
  game.emit('title.transferred', { title: titleId, from: old?.id, to: neo?.id });
  if (neo) game.onAction('on_title_gained', { type: 'character', id: neo.id }, { title: { type: 'title', id: titleId } });
}

/** Персонаж потерял все земли: его вассалы уходят к его сюзерену, сам он — ко двору. */
export function becomeUnlanded(game: Game, c: Character, court?: string) {
  const newLiege = c.liege ?? court;
  for (const v of game.vassalsOf(c.id)) setLiege(game, v, newLiege && newLiege !== v.id ? newLiege : undefined);
  const target = newLiege && newLiege !== c.id ? newLiege : undefined;
  for (const ct of game.courtiersOf(c.id)) setLiege(game, ct, target);
  setLiege(game, c, target);
  c.capital = undefined;
}

/** Вассал не может быть рангом выше или равным сюзерену; нет циклов. */
export function fixLiegeConsistency(game: Game, c: Character) {
  if (!c.liege || !c.titles.length) return;
  const l = game.char(c.liege);
  if (!l || l.death !== undefined || !l.titles.length) {
    setLiege(game, c, l?.liege);
    return;
  }
  if (primaryTier(game, c) >= primaryTier(game, l)) {
    setLiege(game, c, undefined);
    return;
  }
  // защита от циклов
  let cur: Character | undefined = l;
  for (let i = 0; i < 30 && cur; i++) {
    if (cur.liege === c.id) {
      setLiege(game, c, undefined);
      return;
    }
    cur = game.char(cur.liege);
  }
}

/**
 * Определяет «естественного» сюзерена правителя по де-юре иерархии:
 * владелец ближайшего вышестоящего де-юре титула.
 */
export function deJureLiegeHolder(game: Game, c: Character): Character | undefined {
  if (!c.titles.length) return undefined;
  const myTier = primaryTier(game, c);
  let t = deJureLiege(game, c.titles[0]);
  while (t) {
    const h = game.char(game.state.titles[t]?.holder);
    if (h && h.id !== c.id && primaryTier(game, h) > myTier) return h;
    t = deJureLiege(game, t);
  }
  return undefined;
}

// ------------------------------------------------------------ создание и узурпация

export function controlledShare(game: Game, c: Character, titleId: string): { have: number; total: number } {
  const counties = deJureCounties(game, titleId);
  const mine = new Set(realmCounties(game, c));
  return { have: counties.filter((x) => mine.has(x)).length, total: counties.length };
}

export function titleActionCost(game: Game, titleId: string, kind: 'create' | 'usurp'): { gold: number; prestige: number } {
  const d = game.titleDef(titleId);
  const table = game.defines.titles?.[`${kind}_cost`]?.[d.tier] ?? { gold: 0, prestige: 0 };
  return { gold: table.gold ?? 0, prestige: table.prestige ?? 0 };
}

export function canCreateTitle(game: Game, c: Character, titleId: string): { ok: boolean; reasons: string[] } {
  const reasons: string[] = [];
  const d = game.content.get<TitleDef>('titles', titleId);
  const st = game.state.titles[titleId];
  if (!d || !st) return { ok: false, reasons: ['?'] };
  if (d.tier === 'county' || d.no_create) reasons.push(game.loc.t('ui.cannot_create_tier'));
  if (st.holder) reasons.push(game.loc.t('ui.title_already_held'));
  if (c.liege && tierRank(d.tier) >= primaryTier(game, game.char(c.liege)!)) reasons.push(game.loc.t('ui.would_outrank_liege'));
  const { have, total } = controlledShare(game, c, titleId);
  const need = Math.ceil(total * (game.defines.titles?.create_fraction ?? 0.51));
  if (have < need) reasons.push(game.loc.t('ui.need_counties', { have, need }));
  const cost = titleActionCost(game, titleId, 'create');
  if (cost.gold > 0 && c.gold < cost.gold) reasons.push(game.loc.t('ui.need_gold', { value: cost.gold }));
  if (cost.prestige > 0 && c.prestige < cost.prestige) reasons.push(game.loc.t('ui.need_prestige', { value: cost.prestige }));
  return { ok: reasons.length === 0, reasons };
}

export function createTitle(game: Game, c: Character, titleId: string): boolean {
  if (!canCreateTitle(game, c, titleId).ok) return false;
  if (!game.engine.hooks.veto('title.create', { game, character: c, title: titleId })) return false;
  const cost = titleActionCost(game, titleId, 'create');
  c.gold -= cost.gold;
  c.prestige -= cost.prestige;
  transferTitle(game, titleId, c.id);
  game.message(game.loc.t('msg.title_created', { who: game.scopeName({ type: 'character', id: c.id }), title: titleFullName(game, titleId) }), 'good', { type: 'title', id: titleId });
  return true;
}

export function canUsurpTitle(game: Game, c: Character, titleId: string): { ok: boolean; reasons: string[] } {
  const reasons: string[] = [];
  const d = game.content.get<TitleDef>('titles', titleId);
  const st = game.state.titles[titleId];
  if (!d || !st) return { ok: false, reasons: ['?'] };
  if (d.tier === 'county') reasons.push(game.loc.t('ui.cannot_create_tier'));
  if (!st.holder || st.holder === c.id) reasons.push(game.loc.t('ui.title_not_held_by_other'));
  if (c.liege && tierRank(d.tier) >= primaryTier(game, game.char(c.liege)!)) reasons.push(game.loc.t('ui.would_outrank_liege'));
  const { have, total } = controlledShare(game, c, titleId);
  const need = Math.ceil(total * (game.defines.titles?.create_fraction ?? 0.51));
  if (have < need) reasons.push(game.loc.t('ui.need_counties', { have, need }));
  const cost = titleActionCost(game, titleId, 'usurp');
  if (cost.gold > 0 && c.gold < cost.gold) reasons.push(game.loc.t('ui.need_gold', { value: cost.gold }));
  if (cost.prestige > 0 && c.prestige < cost.prestige) reasons.push(game.loc.t('ui.need_prestige', { value: cost.prestige }));
  return { ok: reasons.length === 0, reasons };
}

export function usurpTitle(game: Game, c: Character, titleId: string): boolean {
  if (!canUsurpTitle(game, c, titleId).ok) return false;
  if (!game.engine.hooks.veto('title.usurp', { game, character: c, title: titleId })) return false;
  const old = game.char(game.state.titles[titleId].holder)!;
  const cost = titleActionCost(game, titleId, 'usurp');
  c.gold -= cost.gold;
  c.prestige -= cost.prestige;
  transferTitle(game, titleId, c.id);
  game.message(
    game.loc.t('msg.title_usurped', { who: game.scopeName({ type: 'character', id: c.id }), title: titleFullName(game, titleId), from: game.scopeName({ type: 'character', id: old.id }) }),
    'bad',
    { type: 'title', id: titleId },
    [c.id, old.id],
  );
  return true;
}

/**
 * Титул без земли не держится: правитель без единого графства передаёт
 * титулы сюзерену, а независимый — сильнейшему вассалу (или титулы пустеют).
 */
export function enforceLandedTitles(game: Game): void {
  for (const c of [...game.rulers()]) {
    if (c.death !== undefined || !c.titles.length || domainCounties(game, c).length) continue;
    const titles = [...c.titles];
    const liege = game.char(c.liege);
    let heir: Character | undefined = liege && liege.death === undefined ? liege : undefined;
    if (!heir) {
      const vassals = game.vassalsOf(c.id).sort((a, b) => domainCounties(game, b).length - domainCounties(game, a).length);
      heir = vassals[0];
    }
    for (const t of titles.sort((a, b) => tierOf(game, b) - tierOf(game, a))) transferTitle(game, t, heir?.id, { court: heir?.id });
    if (heir && !heir.liege) for (const v of game.vassalsOf(c.id)) setLiege(game, v, heir.id);
  }
}
