import type { BookmarkDef, CharacterDef, DynastyDef, ProvinceDef, TitleDef } from '../content/defs';
import { DAYS_PER_YEAR, parseDate } from '../core/date';
import type { Engine } from '../engine';
import { Game } from '../game';
import type { Character, GameState } from '../types';
import { addTrait, assignEducation, assignPersonality, createCharacter, isAdult, setLiege, skillIds, traitDef } from './characters';
import { deJureCounties, deJureLiegeHolder, fixLiegeConsistency, primaryTier, transferTitle } from './titles';

export const SAVE_VERSION = 1;

export function emptyState(engine: Engine, bookmark: string, date: number, seed: number): GameState {
  return {
    version: SAVE_VERSION,
    bookmark,
    date,
    startDate: date,
    rng: { s: seed | 0 },
    nextId: 1,
    characters: {},
    dynasties: {},
    titles: {},
    provinces: {},
    wars: {},
    armies: {},
    schemes: {},
    alliances: [],
    truces: [],
    scheduled: [],
    pendingEvents: [],
    pendingRequests: [],
    globalFlags: {},
    globalVars: {},
    messages: [],
    modData: {},
    mods: engine.mods.map((m) => ({ id: m.manifest.id, version: m.manifest.version })),
  };
}

/**
 * Создаёт новую партию по «закладке» (bookmarks): исторические персонажи
 * и владельцы титулов из данных, недостающие правители и дворы
 * генерируются.
 */
export function setupNewGame(engine: Engine, bookmarkId: string, seed = Date.now() % 2147483647): Game {
  const content = engine.content;
  const bm = content.get<BookmarkDef>('bookmarks', bookmarkId);
  if (!bm) throw new Error(`Нет закладки "${bookmarkId}"`);
  const date = parseDate(bm.date);
  const state = emptyState(engine, bookmarkId, date, seed);
  const game = new Game(engine, state);
  game.quiet = true;

  for (const d of content.all<ProvinceDef>('provinces')) {
    if (d.impassable) continue;
    state.provinces[d.id] = {
      id: d.id,
      culture: d.culture,
      faith: d.faith,
      development: d.development ?? 5,
      buildings: [...(d.buildings ?? [])],
      modifiers: [],
      flags: {},
      vars: {},
    };
  }
  for (const t of content.all<TitleDef>('titles')) state.titles[t.id] = { id: t.id, history: [] };
  for (const d of content.all<DynastyDef>('dynasties')) {
    state.dynasties[d.id] = { id: d.id, name: '', culture: d.culture, prestige: d.prestige ?? 0, coa: d.coa };
  }

  // Исторические персонажи
  const defs = content.all<CharacterDef>('characters');
  const born = defs.filter((d) => parseDate(d.birth) <= date);
  for (const d of born) {
    const skills: Record<string, number> = {};
    for (const s of skillIds(game)) skills[s] = d.skills?.[s] ?? Math.max(0, Math.round(game.rng.gauss(7, 4)));
    const c: Character = {
      id: d.id,
      name: d.name,
      nickname: d.nickname,
      female: !!d.female,
      birth: parseDate(d.birth),
      death: d.death && parseDate(d.death) <= date ? parseDate(d.death) : undefined,
      dynasty: d.dynasty,
      culture: d.culture,
      faith: d.faith,
      traits: [],
      skills,
      gold: d.gold ?? 0,
      prestige: d.prestige ?? 0,
      piety: d.piety ?? 0,
      stress: 0,
      health: d.health ?? 5,
      father: d.father,
      mother: d.mother,
      spouses: [],
      formerSpouses: [],
      children: [],
      titles: [],
      claims: [...(d.claims ?? [])],
      opinions: {},
      modifiers: (d.modifiers ?? []).map((m: any) => (typeof m === 'string' ? { id: m } : { id: m.id, expires: m.years ? date + m.years * DAYS_PER_YEAR : undefined })),
      hooks: [],
      flags: {},
      vars: {},
      dna: {
        skin: d.dna?.skin ?? game.rng.next(),
        hair: d.dna?.hair ?? game.rng.next(),
        eyes: d.dna?.eyes ?? game.rng.next(),
        face: d.dna?.face ?? game.rng.next(),
      },
      levyRatio: 1,
    };
    state.characters[c.id] = c;
    for (const t of d.traits ?? []) {
      if (traitDef(game, t)) addTrait(game, c, t);
      else game.scriptError(`Персонаж ${d.id}: нет черты "${t}"`);
    }
  }
  for (const d of born) {
    const c = state.characters[d.id];
    for (const p of [d.father, d.mother]) {
      const parent = p ? state.characters[p] : undefined;
      if (parent && !parent.children.includes(c.id)) parent.children.push(c.id);
      else if (p && !parent) {
        if (p === d.father) c.father = undefined;
        else c.mother = undefined;
      }
    }
    const spouses = Array.isArray(d.spouse) ? d.spouse : d.spouse ? [d.spouse] : [];
    for (const sid of spouses) {
      const s = state.characters[sid];
      if (!s) continue;
      const bothAlive = c.death === undefined && s.death === undefined;
      const [la, lb] = bothAlive ? ['spouses', 'spouses'] : ['formerSpouses', 'formerSpouses'];
      if (!(c as any)[la].includes(s.id)) (c as any)[la].push(s.id);
      if (!(s as any)[lb].includes(c.id)) (s as any)[lb].push(c.id);
    }
  }
  game.markDirty();
  for (const c of game.living()) {
    assignPersonality(game, c);
    if (isAdult(game, c)) assignEducation(game, c);
  }

  // Владельцы титулов
  const holderOrder = Object.entries(bm.holders ?? {}).sort(
    (a, b) => tierOrder(engine, b[0]) - tierOrder(engine, a[0]),
  );
  for (const [title, cid] of holderOrder) {
    const c = state.characters[cid];
    if (!c || c.death !== undefined || !state.titles[title]) {
      game.scriptError(`Закладка ${bookmarkId}: не удалось выдать ${title} персонажу ${cid}`);
      continue;
    }
    transferTitle(game, title, cid);
  }
  for (const [cid, titles] of Object.entries(bm.claims ?? {})) {
    const c = state.characters[cid];
    if (c) for (const t of titles) if (!c.claims.includes(t)) c.claims.push(t);
  }

  const generated = new Set<string>();
  if (bm.generate_missing !== false) generateMissingHolders(game, generated);

  // Сюзерены правителей
  const rulers = [...game.rulers()].sort((a, b) => primaryTier(game, a) - primaryTier(game, b));
  for (const c of rulers) {
    if (bm.vassal_of && c.id in bm.vassal_of) setLiege(game, c, bm.vassal_of[c.id] ?? undefined);
    else setLiege(game, c, deJureLiegeHolder(game, c)?.id);
  }
  for (const c of game.rulers()) fixLiegeConsistency(game, c);

  // Дворы безземельных
  const courtOf = (c: Character, depth = 0): string | undefined => {
    if (depth > 6) return undefined;
    const def = content.get<CharacterDef>('characters', c.id);
    if (def?.court && state.characters[def.court]) return def.court;
    const rel = [...c.spouses, c.father, c.mother].map((id) => game.char(id)).filter((x): x is Character => !!x && x.death === undefined);
    const landed = rel.find((x) => x.titles.length);
    if (landed) return landed.id;
    for (const r of rel) {
      const ct = courtOf(r, depth + 1);
      if (ct) return ct;
    }
    return undefined;
  };
  for (const c of game.living()) {
    if (c.titles.length || c.liege) continue;
    let court = courtOf(c);
    if (!court) {
      const same = game.rulers().filter((r) => r.culture === c.culture);
      court = (same.sort((a, b) => primaryTier(game, b) - primaryTier(game, a))[0] ?? game.rulers()[0])?.id;
    }
    setLiege(game, c, court);
  }

  // Семьи и дворы сгенерированных правителей
  for (const id of generated) generateFamily(game, state.characters[id]);
  for (const r of game.rulers()) fillCourt(game, r);

  for (const [a, b] of (bm.alliances ?? []) as [string, string][]) {
    if (game.isAlive(a) && game.isAlive(b)) state.alliances.push({ a, b, since: date });
  }

  // Стартовые казна и престиж
  const startGold = engine.content.singleton('defines').start_gold_by_tier ?? [0, 30, 80, 200, 400];
  const startPrestige = engine.content.singleton('defines').start_prestige_by_tier ?? [0, 50, 150, 400, 800];
  for (const r of game.rulers()) {
    const d = content.get<CharacterDef>('characters', r.id);
    const tier = primaryTier(game, r);
    if (d?.gold == null) r.gold = startGold[tier] ?? 0;
    if (d?.prestige == null) r.prestige = startPrestige[tier] ?? 0;
  }
  game.markDirty();
  game.quiet = false;
  engine.hooks.emit('game.setup', { game, bookmark: bm });
  for (const r of game.rulers()) game.onAction('on_game_start', { type: 'character', id: r.id });
  return game;
}

function tierOrder(engine: Engine, title: string): number {
  const t = engine.content.get<TitleDef>('titles', title)?.tier;
  return ['county', 'duchy', 'kingdom', 'empire'].indexOf(t ?? 'county');
}

function provinceCulture(game: Game, county: string): { culture: string; faith: string } {
  const p = game.state.provinces[county];
  return { culture: p?.culture ?? 'unknown', faith: p?.faith ?? 'unknown' };
}

function newRuler(game: Game, county: string, generated: Set<string>): Character {
  const { culture, faith } = provinceCulture(game, county);
  const c = createCharacter(game, {
    culture,
    faith,
    female: game.rng.chance(game.defines.setup?.female_ruler_chance ?? 0.04),
    age: game.rng.int(20, 55),
    dynasty: 'new',
  });
  generated.add(c.id);
  return c;
}

export function generateMissingHolders(game: Game, generated: Set<string>): void {
  const content = game.content;
  for (const d of content.all<TitleDef>('titles').filter((t) => t.tier === 'duchy')) {
    if (game.state.titles[d.id]?.holder || d.no_generate) continue;
    const counties = deJureCounties(game, d.id).filter((c) => game.state.titles[c]);
    if (counties.length < 2 || counties.some((c) => game.state.titles[c].holder)) continue;
    const cap = d.capital && counties.includes(d.capital) ? d.capital : counties[0];
    const duke = newRuler(game, cap, generated);
    transferTitle(game, d.id, duke.id);
    transferTitle(game, cap, duke.id);
    if (counties.length >= 4) {
      const second = counties.find((c) => c !== cap)!;
      transferTitle(game, second, duke.id);
    }
  }
  for (const d of content.all<TitleDef>('titles').filter((t) => t.tier === 'county')) {
    if (game.state.titles[d.id]?.holder || !game.state.provinces[d.id]) continue;
    const count = newRuler(game, d.id, generated);
    transferTitle(game, d.id, count.id);
  }
}

export function generateFamily(game: Game, r: Character): void {
  const age = Math.floor((game.date - r.birth) / DAYS_PER_YEAR);
  if (age < 18 || r.spouses.length) return;
  if (!game.rng.chance(game.defines.setup?.married_chance ?? 0.75)) return;
  const spouse = createCharacter(game, {
    culture: r.culture,
    faith: r.faith,
    female: !r.female,
    age: Math.max(16, age + game.rng.int(-8, 3)),
    dynasty: game.rng.chance(0.6) ? 'new' : null,
    liege: r.id,
  });
  r.spouses.push(spouse.id);
  spouse.spouses.push(r.id);
  const [father, mother] = r.female ? [spouse, r] : [r, spouse];
  const motherAge = Math.floor((game.date - mother.birth) / DAYS_PER_YEAR);
  const fertileYears = Math.max(0, Math.min(motherAge, 45) - 17);
  const n = Math.min(5, game.rng.int(0, Math.ceil(fertileYears / 4)));
  for (let i = 0; i < n; i++) {
    const yearsAgo = game.rng.int(0, Math.max(0, fertileYears - 1));
    createCharacter(game, {
      culture: father.culture,
      faith: father.faith,
      father: father.id,
      mother: mother.id,
      birth: game.date - yearsAgo * DAYS_PER_YEAR - game.rng.int(0, 300),
      liege: r.id,
    });
  }
}

export function fillCourt(game: Game, r: Character): void {
  const min = (game.defines.court?.min_courtiers_by_tier ?? [0, 2, 3, 5, 6])[primaryTier(game, r)] ?? 2;
  let have = game.courtiersOf(r.id).length;
  while (have < min) {
    createCharacter(game, {
      culture: r.culture,
      faith: r.faith,
      age: game.rng.int(16, 45),
      dynasty: game.rng.chance(game.defines.court?.noble_courtier_chance ?? 0.5) ? 'new' : null,
      liege: r.id,
    });
    have++;
  }
}
