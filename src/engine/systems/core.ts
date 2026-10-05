/**
 * Встроенные системы симуляции. Каждая — независимый модуль с методами
 * onDay/onMonth/onYear. Мод может заменить любую (api.systems.replace),
 * удалить (api.systems.remove) или добавить свою.
 */
import type { TraitDef } from '../content/defs';
import { DAYS_PER_YEAR } from '../core/date';
import type { Game } from '../game';
import type { Character } from '../types';
import { dailyAI } from '../world/ai';
import { addTrait, ageOf, assignEducation, createCharacter, isAdult, isCloseFamily, removeTrait } from '../world/characters';
import { dailyConstruction } from '../world/decisions';
import { monthlyIncome, monthlyPiety, monthlyPrestige } from '../world/economy';
import { dailyMilitary, regenLevies } from '../world/military';
import { decayOpinions } from '../world/opinion';
import { monthlySchemes } from '../world/schemes';
import { fillCourt } from '../world/setup';
import { provStat, skill, stat } from '../world/stats';
import { heirsOf, killCharacter } from '../world/succession';
import { updateTicking, validateWars } from '../world/war';
import { enforceLandedTitles, primaryTier } from '../world/titles';

export interface GameSystem {
  id: string;
  /** Порядок выполнения: меньше — раньше. */
  order: number;
  onDay?(game: Game): void;
  onMonth?(game: Game): void;
  onYear?(game: Game): void;
}

export const upkeepSystem: GameSystem = {
  id: 'upkeep',
  order: 0,
  onMonth(game) {
    const now = game.date;
    for (const c of game.living()) {
      if (c.modifiers.length) c.modifiers = c.modifiers.filter((m) => m.expires === undefined || m.expires > now);
      for (const [k, v] of Object.entries(c.flags)) {
        if (k.startsWith('trait_expires:') && v <= now) {
          removeTrait(game, c, k.slice('trait_expires:'.length));
          delete c.flags[k];
        } else if (k.startsWith('tmp:') && v <= now) delete c.flags[k];
      }
      c.hooks = c.hooks.filter((h) => h.expires === undefined || h.expires > now);
    }
    for (const p of Object.values(game.state.provinces)) {
      if (p.modifiers.length) p.modifiers = p.modifiers.filter((m) => m.expires === undefined || m.expires > now);
    }
    for (const [k, v] of Object.entries(game.state.globalFlags)) if (v && v <= now) delete game.state.globalFlags[k];
    decayOpinions(game);
    enforceLandedTitles(game);
    game.statCache.clear();
  },
};

export const economySystem: GameSystem = {
  id: 'economy',
  order: 10,
  onMonth(game) {
    const decay = game.defines.character?.stress_decay ?? 2;
    const deltas = new Map<string, { gold: number; prestige: number; piety: number }>();
    for (const c of game.rulers()) {
      deltas.set(c.id, { gold: monthlyIncome(game, c), prestige: monthlyPrestige(game, c), piety: monthlyPiety(game, c) });
    }
    for (const [id, d] of deltas) {
      const c = game.char(id)!;
      c.gold += d.gold;
      c.prestige += d.prestige;
      c.piety += d.piety;
      const dyn = c.dynasty ? game.state.dynasties[c.dynasty] : undefined;
      if (dyn && d.prestige > 0) dyn.prestige += d.prestige * (game.defines.economy?.dynasty_prestige_share ?? 0.1);
    }
    for (const c of game.living()) {
      if (!c.titles.length) {
        const flat = stat(game, c, 'monthly_income');
        if (flat) c.gold += flat;
      }
      if (c.stress > 0) c.stress = Math.max(0, c.stress - decay);
      const lvl = Math.floor(c.stress / 100);
      const prev = c.vars.stress_level ?? 0;
      if (lvl > prev) {
        c.vars.stress_level = lvl;
        game.onAction('on_stress_level', { type: 'character', id: c.id });
      } else if (lvl < prev) c.vars.stress_level = lvl;
    }
  },
};

function yearlyMortality(game: Game, age: number): number {
  const table: [number, number][] = game.defines.character?.mortality ?? [
    [0, 0.03],
    [5, 0.008],
    [16, 0.006],
    [40, 0.015],
    [60, 0.05],
    [80, 0.25],
  ];
  if (age <= table[0][0]) return table[0][1];
  for (let i = 1; i < table.length; i++) {
    const [a1, p1] = table[i - 1];
    const [a2, p2] = table[i];
    if (age <= a2) return p1 + ((age - a1) / (a2 - a1)) * (p2 - p1);
  }
  return table[table.length - 1][1];
}

export function monthlyDeathChance(game: Game, c: Character): number {
  const ch = game.defines.character ?? {};
  const age = ageOf(game, c);
  const health = stat(game, c, 'health');
  const y = yearlyMortality(game, age) * Math.exp(-(ch.health_mortality_factor ?? 0.35) * (health - (ch.base_health ?? 5)));
  return 1 - Math.pow(1 - Math.min(0.95, y), 1 / 12);
}

export const demographySystem: GameSystem = {
  id: 'demography',
  order: 20,
  onMonth(game) {
    const ch = game.defines.character ?? {};
    const adult = ch.adult_age ?? 16;
    for (const c of [...game.living()]) {
      if (c.death !== undefined) continue;
      // Черты-болезни: шанс смерти и излечения
      let traitDeath = 0;
      for (const t of [...c.traits]) {
        const d = game.content.get<TraitDef>('traits', t);
        if (!d) continue;
        traitDeath += d.monthly_death_chance ?? 0;
        if (d.monthly_cure_chance && game.rng.chance(d.monthly_cure_chance)) removeTrait(game, c, t);
      }
      if (game.rng.chance(monthlyDeathChance(game, c) + traitDeath)) {
        const illness = c.traits.find((t) => game.content.get<TraitDef>('traits', t)?.monthly_death_chance);
        killCharacter(game, c, illness ? 'illness' : ageOf(game, c) < adult ? 'childhood' : 'natural');
        continue;
      }
      // Совершеннолетие
      if (!c.flags.adult && ageOf(game, c) >= adult) {
        c.flags.adult = 0;
        assignEducation(game, c);
        game.onAction('on_coming_of_age', { type: 'character', id: c.id });
      }
      if (c.female) monthlyFertility(game, c);
    }
  },
  onYear(game) {
    for (const r of game.rulers()) {
      fillCourt(game, r);
      trimCourt(game, r);
    }
    pruneDead(game);
  },
};

function monthlyFertility(game: Game, mother: Character) {
  const ch = game.defines.character ?? {};
  if (mother.pregnancy) {
    if (mother.pregnancy.due <= game.date) giveBirth(game, mother);
    return;
  }
  const age = ageOf(game, mother);
  if (age < (ch.min_fertile_age ?? 16) || age > (ch.max_fertile_age ?? 45)) return;
  const husband = mother.spouses.map((id) => game.char(id)).find((s) => s && s.death === undefined && !s.female);
  if (!husband) return;
  const alive = mother.children.filter((id) => game.isAlive(id)).length;
  // Мягкий предел численности мира: при перенаселении рожают реже (держит симуляцию быстрой).
  const pop = game.living().length;
  const soft = ch.population_soft_cap ?? 900;
  const crowd = pop > soft ? Math.max(0.1, (soft / pop) ** 3) : 1;
  const p = crowd *
    (ch.base_conception ?? 0.05) *
    Math.max(0, stat(game, mother, 'fertility')) *
    Math.max(0, stat(game, husband, 'fertility')) *
    4 *
    Math.pow(ch.conception_child_decay ?? 0.85, alive);
  if (game.rng.chance(p)) {
    mother.pregnancy = { father: husband.id, due: game.date + (ch.pregnancy_days ?? 270) };
    game.onAction('on_pregnancy', { type: 'character', id: mother.id }, { father: { type: 'character', id: husband.id } });
  }
}

function giveBirth(game: Game, mother: Character) {
  const father = game.char(mother.pregnancy!.father);
  mother.pregnancy = undefined;
  const court = mother.titles.length ? mother.id : father?.titles.length ? father.id : (mother.liege ?? father?.liege);
  const base = father && !mother.titles.length ? father : mother;
  const child = createCharacter(game, {
    culture: base.culture,
    faith: base.faith,
    father: father?.id,
    mother: mother.id,
    birth: game.date,
    liege: court,
  });
  game.onAction('on_birth', { type: 'character', id: child.id }, {
    mother: { type: 'character', id: mother.id },
    ...(father ? { father: { type: 'character', id: father.id } } : {}),
  });
  game.emit('character.birth', { character: child, mother, father });
  game.message(
    game.loc.t('msg.birth', { child: game.scopeName({ type: 'character', id: child.id }), mother: game.scopeName({ type: 'character', id: mother.id }) }),
    'birth',
    { type: 'character', id: child.id },
    [mother.id, father?.id],
  );
  if (game.rng.chance(game.defines.character?.childbirth_death_chance ?? 0.02)) killCharacter(game, mother, 'childbirth');
}

/**
 * Двор не растёт бесконечно: лишние безродные одинокие придворные
 * (не родня правителю) покидают мир. Это держит численность персонажей
 * в разумных пределах и симуляцию быстрой.
 */
function trimCourt(game: Game, r: Character) {
  const max = (game.defines.court?.max_courtiers_by_tier ?? [0, 8, 12, 16, 20])[primaryTier(game, r)] ?? 10;
  const courtiers = game.courtiersOf(r.id);
  if (courtiers.length <= max) return;
  // Уходят одинокие взрослые без детей: чужаки, а затем и дальняя родня
  // (близкие правителя и ближайшие наследники остаются).
  const keep = new Set(heirsOf(game, r).slice(0, 3));
  const removable = courtiers.filter(
    (c) =>
      !game.isPlayer(c.id) &&
      !c.spouses.length &&
      !c.children.some((x) => game.isAlive(x)) &&
      !keep.has(c.id) &&
      !isCloseFamily(game, c, r) &&
      !r.spouses.includes(c.id) &&
      !c.prison &&
      isAdult(game, c),
  );
  // сначала чужие, потом родня
  removable.sort((a, b) => Number(a.dynasty === r.dynasty) - Number(b.dynasty === r.dynasty));
  for (const c of removable.slice(0, courtiers.length - max)) {
    for (const pid of [c.father, c.mother]) {
      const p = game.char(pid);
      if (p) p.children = p.children.filter((x) => x !== c.id);
    }
    for (const s of Object.values(game.state.schemes)) if (s.owner === c.id || s.target === c.id) delete game.state.schemes[s.id];
    delete game.state.characters[c.id];
  }
  game.markIndexDirty();
  game.monthCache.clear(); // рыцари, советы и т. п. могли ссылаться на ушедших
}

function pruneDead(game: Game) {
  const limit = game.date - (game.defines.character?.prune_after_years ?? 60) * DAYS_PER_YEAR;
  const player = game.state.player;
  for (const c of Object.values(game.state.characters)) {
    if (c.death === undefined || c.death > limit || c.id === player) continue;
    if (c.children.some((id) => game.isAlive(id))) continue;
    if (Object.values(game.state.dynasties).some((d) => d.founder === c.id)) continue;
    delete game.state.characters[c.id];
  }
  game.markIndexDirty();
}

export const eventSystem: GameSystem = {
  id: 'events',
  order: 30,
  onDay(game) {
    game.events.processScheduled();
  },
  onMonth(game) {
    for (const c of [...game.rulers()]) if (c.death === undefined) game.onAction('on_monthly_pulse', { type: 'character', id: c.id });
  },
  onYear(game) {
    for (const c of [...game.rulers()]) if (c.death === undefined) game.onAction('on_yearly_pulse', { type: 'character', id: c.id });
  },
};

export const schemeSystem: GameSystem = {
  id: 'schemes',
  order: 40,
  onMonth: monthlySchemes,
};

export const militarySystem: GameSystem = {
  id: 'military',
  order: 50,
  onDay: dailyMilitary,
  onMonth: regenLevies,
};

export const warSystem: GameSystem = {
  id: 'war',
  order: 55,
  onMonth(game) {
    validateWars(game);
    for (const w of Object.values(game.state.wars)) updateTicking(game, w);
  },
};

export const constructionSystem: GameSystem = {
  id: 'construction',
  order: 60,
  onDay: dailyConstruction,
};

export const aiSystem: GameSystem = {
  id: 'ai',
  order: 70,
  onDay: dailyAI,
};

export const developmentSystem: GameSystem = {
  id: 'development',
  order: 80,
  onYear(game) {
    const d = game.defines.development ?? {};
    for (const p of Object.values(game.state.provinces)) {
      const holder = game.char(game.state.titles[p.id]?.holder);
      const chance =
        (d.base_growth ?? 0.12) +
        provStat(game, p.id, 'development_growth') +
        (holder ? skill(game, holder, 'stewardship') * (d.growth_per_stewardship ?? 0.01) + stat(game, holder, 'development_growth') : 0);
      if (!p.occupant && game.rng.chance(Math.max(0, chance))) p.development = Math.min(d.max ?? 100, p.development + 1);
    }
  },
};

export const builtinSystems: GameSystem[] = [
  upkeepSystem,
  economySystem,
  demographySystem,
  eventSystem,
  schemeSystem,
  militarySystem,
  warSystem,
  constructionSystem,
  aiSystem,
  developmentSystem,
];

export function isAdultChar(game: Game, c: Character) {
  return isAdult(game, c);
}
export { addTrait };
