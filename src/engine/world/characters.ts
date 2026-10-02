import type { CultureDef, TraitDef } from '../content/defs';
import { DAYS_PER_YEAR } from '../core/date';
import type { Game } from '../game';
import type { Character, Dynasty } from '../types';
import { primaryTier, rankName } from './titles';

export function isAlive(c: Character | undefined | null): c is Character {
  return !!c && c.death === undefined;
}

export function ageOf(game: Game, c: Character): number {
  const end = c.death ?? game.date;
  return Math.floor((end - c.birth) / DAYS_PER_YEAR);
}

export function isAdult(game: Game, c: Character): boolean {
  return ageOf(game, c) >= (game.defines.character?.adult_age ?? 16);
}

export function charName(game: Game, c: Character): string {
  return game.loc.rawExact(`name.${c.name}`) ?? c.name;
}

/** «Король Гарольд Годвинсон» (withRank) или «Гарольд Годвинсон». */
export function charFullName(game: Game, c: Character, withRank: boolean): string {
  const parts: string[] = [];
  if (withRank && c.titles.length) parts.push(rankName(game, c));
  parts.push(charName(game, c));
  if (c.nickname) parts.push(game.loc.resolve(c.nickname));
  else if (c.dynasty) parts.push(game.nameOf('dynasties', c.dynasty));
  return parts.join(' ');
}

export function hasTrait(c: Character, t: string): boolean {
  return c.traits.includes(t);
}

export function traitDef(game: Game, t: string): TraitDef | undefined {
  return game.content.get<TraitDef>('traits', t);
}

export function addTrait(game: Game, c: Character, t: string): boolean {
  const def = traitDef(game, t);
  if (!def) {
    game.scriptError(`Нет черты "${t}"`);
    return false;
  }
  if (c.traits.includes(t)) return false;
  // Убираем противоположные черты и другие уровни того же образования.
  const opp = new Set(def.opposites ?? []);
  c.traits = c.traits.filter((x) => {
    if (opp.has(x)) return false;
    const xd = traitDef(game, x);
    if (xd?.opposites?.includes(t)) return false;
    if (def.education && xd?.education) return false;
    if (def.group && xd?.group === def.group) return false;
    return true;
  });
  c.traits.push(t);
  if (def.duration_days) c.flags[`trait_expires:${t}`] = game.date + def.duration_days;
  game.statCache.delete(c.id);
  game.emit('character.trait_added', { character: c, trait: t });
  return true;
}

export function removeTrait(game: Game, c: Character, t: string): boolean {
  const i = c.traits.indexOf(t);
  if (i < 0) return false;
  c.traits.splice(i, 1);
  delete c.flags[`trait_expires:${t}`];
  game.statCache.delete(c.id);
  game.emit('character.trait_removed', { character: c, trait: t });
  return true;
}

// ------------------------------------------------------------ родство

export function parentsOf(game: Game, c: Character): Character[] {
  return [game.char(c.father), game.char(c.mother)].filter((x): x is Character => !!x);
}

export function siblingsOf(game: Game, c: Character): Character[] {
  const ids = new Set<string>();
  for (const p of parentsOf(game, c)) for (const ch of p.children) if (ch !== c.id) ids.add(ch);
  return [...ids].map((id) => game.char(id)!).filter(Boolean);
}

export function isParentOf(a: Character, b: Character): boolean {
  return b.father === a.id || b.mother === a.id;
}

export function isSibling(a: Character, b: Character): boolean {
  if (a.id === b.id) return false;
  return (!!a.father && a.father === b.father) || (!!a.mother && a.mother === b.mother);
}

/** Близкие родственники: родители, дети, братья/сёстры, деды, внуки. */
export function isCloseFamily(game: Game, a: Character, b: Character): boolean {
  if (a.id === b.id) return false;
  if (isParentOf(a, b) || isParentOf(b, a) || isSibling(a, b)) return true;
  for (const p of parentsOf(game, a)) if (isParentOf(b, p)) return true;
  for (const p of parentsOf(game, b)) if (isParentOf(a, p)) return true;
  return false;
}

/** Слишком близкие для брака: близкие + дяди/тёти/племянники. */
export function isTooCloseToMarry(game: Game, a: Character, b: Character): boolean {
  if (isCloseFamily(game, a, b)) return true;
  for (const p of parentsOf(game, a)) if (isSibling(p, b)) return true;
  for (const p of parentsOf(game, b)) if (isSibling(p, a)) return true;
  return false;
}

export function isMarried(c: Character): boolean {
  return c.spouses.length > 0;
}

export function canMarry(game: Game, a: Character, b: Character): boolean {
  if (!isAlive(a) || !isAlive(b) || a.id === b.id) return false;
  if (a.female === b.female || a.prison || b.prison) return false;
  const polygamy = (c: Character) => !!game.content.get('faiths', c.faith)?.doctrines?.polygamy;
  if (isMarried(a) && !polygamy(a)) return false;
  if (isMarried(b) && !polygamy(b)) return false;
  if (a.spouses.includes(b.id)) return false;
  const minAge = game.defines.character?.marriage_age ?? 16;
  if (ageOf(game, a) < minAge || ageOf(game, b) < minAge) return false;
  return !isTooCloseToMarry(game, a, b);
}

export function marry(game: Game, a: Character, b: Character): void {
  if (!a.spouses.includes(b.id)) a.spouses.push(b.id);
  if (!b.spouses.includes(a.id)) b.spouses.push(a.id);
  // Жена переезжает ко двору мужа (или наоборот, если муж безземельный, а жена правит).
  const [host, guest] = b.titles.length && !a.titles.length ? [b, a] : a.female && !b.female ? [b, a] : [a, b];
  if (!guest.titles.length) {
    setLiege(game, guest, host.titles.length ? host.id : host.liege);
  }
  game.markDirty();
  game.onAction('on_marriage', { type: 'character', id: a.id }, { spouse: { type: 'character', id: b.id } });
  game.emit('character.marriage', { a, b });
}

export function divorce(game: Game, a: Character, b: Character): void {
  a.spouses = a.spouses.filter((s) => s !== b.id);
  b.spouses = b.spouses.filter((s) => s !== a.id);
  if (!a.formerSpouses.includes(b.id)) a.formerSpouses.push(b.id);
  if (!b.formerSpouses.includes(a.id)) b.formerSpouses.push(a.id);
  game.markDirty();
}

export function setLiege(game: Game, c: Character, liege: string | undefined): void {
  if (liege === c.id) liege = undefined;
  if (c.liege === liege) return;
  const old = c.liege;
  c.liege = liege;
  game.markDirty();
  game.emit('character.liege_changed', { character: c, old, liege });
}

// ------------------------------------------------------------ создание

export function createDynasty(game: Game, culture: string, founder?: string, name?: string): Dynasty {
  const cul = game.content.get<CultureDef>('cultures', culture);
  const used = new Set(Object.values(game.state.dynasties).map((d) => d.name));
  let n = name;
  for (let i = 0; !n && i < 8; i++) {
    let key: string | undefined;
    if (cul?.dynasty_pattern === 'place') {
      const provs = Object.values(game.state.provinces).filter((p) => p.culture === culture).map((p) => p.id);
      key = game.rng.pick(provs.length ? provs : Object.keys(game.state.provinces));
    } else key = game.rng.pick(cul?.male_names ?? []);
    const cand = `gen:${culture}:${key ?? 'Nameless'}`;
    if (!used.has(cand) || i === 7) n = cand;
  }
  const d: Dynasty = { id: game.newId('dyn'), name: n!, culture, prestige: 0, founder };
  game.state.dynasties[d.id] = d;
  return d;
}

export interface NewCharacterOpts {
  id?: string;
  culture: string;
  faith: string;
  female?: boolean;
  birth?: number;
  age?: number;
  name?: string;
  dynasty?: string | 'new' | null;
  father?: string;
  mother?: string;
  liege?: string;
  traits?: string[];
  skills?: Record<string, number>;
  gold?: number;
  /** Не генерировать личность и образование. */
  bare?: boolean;
}

function clamp01(x: number) {
  return Math.max(0, Math.min(1, x));
}

export function pickName(game: Game, culture: string, female: boolean, father?: Character, mother?: Character): string {
  const cul = game.content.get<CultureDef>('cultures', culture);
  const list = (female ? cul?.female_names : cul?.male_names) ?? [];
  // Иногда ребёнка называют в честь деда/бабки.
  const elders = [father, mother]
    .flatMap((p) => (p ? [game.char(p.father), game.char(p.mother)] : []))
    .filter((x): x is Character => !!x && x.female === female);
  if (elders.length && game.rng.chance(game.defines.character?.name_after_relative_chance ?? 0.25)) {
    return game.rng.pick(elders)!.name;
  }
  return game.rng.pick(list) ?? (female ? 'Anna' : 'John');
}

export function skillIds(game: Game): string[] {
  return game.content
    .all('skills')
    .sort((a: any, b: any) => (a.order ?? 0) - (b.order ?? 0))
    .map((s: any) => s.id);
}

export function createCharacter(game: Game, o: NewCharacterOpts): Character {
  const rng = game.rng;
  const father = game.char(o.father);
  const mother = game.char(o.mother);
  const female = o.female ?? rng.chance(0.5);
  const birth = o.birth ?? game.date - Math.round(((o.age ?? 20) + rng.next()) * DAYS_PER_YEAR);
  const cul = game.content.get<CultureDef>('cultures', o.culture);

  let dynasty: string | undefined;
  if (o.dynasty === 'new') dynasty = createDynasty(game, o.culture).id;
  else if (o.dynasty === null) dynasty = undefined;
  else dynasty = o.dynasty ?? father?.dynasty ?? mother?.dynasty;

  const skills: Record<string, number> = {};
  for (const s of skillIds(game)) {
    const inherited = father && mother ? (father.skills[s] + mother.skills[s]) / 2 : undefined;
    const base = inherited !== undefined ? inherited + rng.gauss(0, 3) : rng.gauss(6, 5);
    skills[s] = Math.max(0, Math.round(o.skills?.[s] ?? base));
  }

  const dnaFrom = (k: 'skin' | 'hair' | 'eyes' | 'face', range?: [number, number]) => {
    if (father && mother) return clamp01((father.dna[k] + mother.dna[k]) / 2 + rng.gauss(0, 0.12));
    const [a, b] = range ?? [0, 1];
    return clamp01(rng.float(a, b));
  };

  const c: Character = {
    id: o.id ?? game.newId('ch'),
    name: o.name ?? pickName(game, o.culture, female, father, mother),
    female,
    birth,
    dynasty,
    culture: o.culture,
    faith: o.faith,
    traits: [],
    skills,
    gold: o.gold ?? 0,
    prestige: 0,
    piety: 0,
    stress: 0,
    health: Math.round(rng.gauss(game.defines.character?.base_health ?? 5, 1.5) * 10) / 10,
    father: father?.id,
    mother: mother?.id,
    spouses: [],
    formerSpouses: [],
    children: [],
    liege: o.liege,
    titles: [],
    claims: [],
    opinions: {},
    modifiers: [],
    hooks: [],
    flags: {},
    vars: {},
    dna: {
      skin: dnaFrom('skin', cul?.skin),
      hair: dnaFrom('hair', cul?.hair),
      eyes: dnaFrom('eyes'),
      face: dnaFrom('face'),
    },
    levyRatio: 1,
  };
  game.state.characters[c.id] = c;
  father?.children.push(c.id);
  mother?.children.push(c.id);

  for (const t of o.traits ?? []) addTrait(game, c, t);
  if (!o.bare) {
    assignCongenital(game, c, father, mother);
    assignPersonality(game, c);
    if (isAdult(game, c)) assignEducation(game, c);
  }
  game.markDirty();
  return c;
}

export function assignCongenital(game: Game, c: Character, father?: Character, mother?: Character) {
  for (const t of game.content.all<TraitDef>('traits')) {
    if (!t.genetic) continue;
    const inParents = [father, mother].filter((p) => p?.traits.includes(t.id)).length;
    const chance = inParents ? (t.inherit_chance ?? 0.25) * inParents : (t.birth_chance ?? 0);
    if (chance > 0 && game.rng.chance(chance)) addTrait(game, c, t.id);
  }
}

export function assignPersonality(game: Game, c: Character, count?: number) {
  const n = count ?? game.defines.character?.personality_traits ?? 3;
  const pool = game.content.all<TraitDef>('traits').filter((t) => t.category === 'personality');
  let have = c.traits.filter((t) => traitDef(game, t)?.category === 'personality').length;
  let guard = 0;
  while (have < n && guard++ < 50) {
    const blocked = new Set<string>();
    for (const t of c.traits) {
      blocked.add(t);
      for (const o of traitDef(game, t)?.opposites ?? []) blocked.add(o);
    }
    const options = pool.filter((t) => !blocked.has(t.id) && !(t.opposites ?? []).some((o) => c.traits.includes(o)));
    const pick = game.rng.weighted(options, (t) => t.weight ?? 1);
    if (!pick) break;
    addTrait(game, c, pick.id);
    have++;
  }
}

export function assignEducation(game: Game, c: Character) {
  if (c.traits.some((t) => traitDef(game, t)?.education)) return;
  const edu = game.content.all<TraitDef>('traits').filter((t) => t.education);
  if (!edu.length) return;
  const skills = [...new Set(edu.map((t) => t.education!.skill))];
  const skill = game.rng.weighted(skills, (s) => Math.max(1, (c.skills[s] ?? 0) + 1) ** 2)!;
  const levels = game.defines.character?.education_level_weights ?? [30, 40, 22, 8];
  const opts = edu.filter((t) => t.education!.skill === skill);
  const pick = game.rng.weighted(opts, (t) => levels[t.education!.level - 1] ?? 1);
  if (pick) addTrait(game, c, pick.id);
}

export function primaryTierOf(game: Game, c: Character): number {
  return primaryTier(game, c);
}
