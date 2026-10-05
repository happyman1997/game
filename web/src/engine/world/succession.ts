import type { ProvinceDef, SuccessionLawDef } from '../content/defs';
import type { TextValue } from '../core/localization';
import type { Game } from '../game';
import type { Character } from '../types';
import { createCharacter, isAdult, isAlive, setLiege, siblingsOf } from './characters';
import { capitalOf, deJureLiege, domainCounties, primaryTier, tierOf, transferTitle } from './titles';

/**
 * Наследование. Закон наследования ссылается на «алгоритм» из реестра
 * registries.successionAlgorithms — мод может добавить свой (например,
 * выборную монархию), не трогая движок.
 */
export interface SuccessionAlgorithm {
  label?: TextValue;
  /** Линия наследования (id персонажей), первый — основной наследник. */
  heirs(game: Game, c: Character, law: SuccessionLawDef): string[];
  /** Распределение титулов: титул → наследник. По умолчанию всё основному. */
  distribute?(game: Game, c: Character, law: SuccessionLawDef, heirs: string[]): Record<string, string>;
}

export function lawOf(game: Game, c: Character): SuccessionLawDef | undefined {
  const id = c.successionLaw ?? game.content.get('cultures', c.culture)?.succession_law ?? game.defines.succession?.default_law;
  return game.content.get<SuccessionLawDef>('succession_laws', id ?? '') ?? game.content.all<SuccessionLawDef>('succession_laws')[0];
}

export function genderSort(game: Game, list: Character[], gender: SuccessionLawDef['gender']): Character[] {
  const byAge = [...list].sort((a, b) => a.birth - b.birth);
  switch (gender) {
    case 'male_only':
      return byAge.filter((c) => !c.female);
    case 'female_only':
      return byAge.filter((c) => c.female);
    case 'male_preference':
      return [...byAge.filter((c) => !c.female), ...byAge.filter((c) => c.female)];
    case 'female_preference':
      return [...byAge.filter((c) => c.female), ...byAge.filter((c) => !c.female)];
    default:
      return byAge;
  }
}

function aliveChildren(game: Game, c: Character): Character[] {
  return c.children.map((id) => game.char(id)).filter(isAlive);
}

/** Линия наследования по крови: дети → внуки → братья/сёстры → племянники → династия. */
export function bloodLine(game: Game, c: Character, gender: SuccessionLawDef['gender']): string[] {
  const out: string[] = [];
  const push = (list: Character[]) => {
    for (const x of genderSort(game, list, gender)) if (!out.includes(x.id) && x.id !== c.id) out.push(x.id);
  };
  push(aliveChildren(game, c));
  const grand = c.children.flatMap((id) => {
    const ch = game.char(id);
    return ch ? aliveChildren(game, ch) : [];
  });
  push(grand);
  const sibs = siblingsOf(game, c);
  push(sibs.filter(isAlive));
  push(sibs.flatMap((s) => aliveChildren(game, s)));
  if (c.dynasty) {
    const dyn = game.living().filter((x) => x.dynasty === c.dynasty && x.id !== c.id);
    push(dyn.filter((x) => isAdult(game, x)));
    push(dyn);
  }
  return out;
}

export const builtinSuccessionAlgorithms: Record<string, SuccessionAlgorithm> = {
  primogeniture: {
    heirs: (game, c, law) => bloodLine(game, c, law.gender),
  },
  partition: {
    heirs: (game, c, law) => bloodLine(game, c, law.gender),
    distribute: (game, c, law, heirs) => {
      const out: Record<string, string> = {};
      if (!heirs.length) return out;
      const children = genderSort(game, aliveChildren(game, c), law.gender).map((x) => x.id);
      const sharers = children.length ? children.slice(0, game.defines.succession?.max_partition_heirs ?? 4) : [heirs[0]];
      const primary = c.titles[0];
      out[primary] = sharers[0];
      const cap = capitalOf(game, c);
      if (cap) out[cap] = sharers[0];
      const rest = c.titles.filter((t) => !(t in out)).sort((a, b) => tierOf(game, b) - tierOf(game, a));
      let i = 1;
      for (const t of rest) {
        // Графство идёт тому, кто получил его де-юре герцогство (не дробим герцогства).
        let owner: string | undefined;
        let up = deJureLiege(game, t);
        while (up && !owner) {
          owner = out[up];
          up = deJureLiege(game, up);
        }
        out[t] = owner ?? sharers[i++ % sharers.length];
      }
      return out;
    },
  },
  seniority: {
    heirs: (game, c, law) => {
      const dyn = c.dynasty ? game.living().filter((x) => x.dynasty === c.dynasty && x.id !== c.id && isAdult(game, x)) : [];
      const sorted = genderSort(game, dyn, law.gender).sort((a, b) => a.birth - b.birth);
      const fallback = bloodLine(game, c, law.gender);
      return [...sorted.map((x) => x.id), ...fallback.filter((id) => !sorted.some((s) => s.id === id))];
    },
  },
};

export function heirsOf(game: Game, c: Character): string[] {
  const law = lawOf(game, c);
  if (!law) return bloodLine(game, c, 'male_preference');
  const algo = game.engine.registries.successionAlgorithms.get(law.algorithm);
  if (!algo) {
    game.scriptError(`Нет алгоритма наследования "${law.algorithm}"`);
    return bloodLine(game, c, law.gender);
  }
  return algo.heirs(game, c, law);
}

export function primaryHeir(game: Game, c: Character): Character | undefined {
  return game.char(heirsOf(game, c)[0]);
}

// ------------------------------------------------------------ смерть

export function killCharacter(game: Game, c: Character, reason = 'natural', killer?: string): void {
  if (c.death !== undefined) return;
  if (!game.engine.hooks.veto('character.before_death', { game, character: c, reason, killer })) return;
  c.death = game.date;
  c.deathReason = reason;
  c.killer = killer;
  game.markDirty();
  game.onAction('on_death', { type: 'character', id: c.id }, killer ? { killer: { type: 'character', id: killer } } : {});

  for (const sid of c.spouses) {
    const s = game.char(sid);
    if (!s) continue;
    s.spouses = s.spouses.filter((x) => x !== c.id);
    if (!s.formerSpouses.includes(c.id)) s.formerSpouses.push(c.id);
  }
  c.formerSpouses.push(...c.spouses.filter((x) => !c.formerSpouses.includes(x)));
  c.spouses = [];
  c.pregnancy = undefined;
  for (const [id, s] of Object.entries(game.state.schemes)) if (s.owner === c.id || s.target === c.id) delete game.state.schemes[id];
  game.state.alliances = game.state.alliances.filter((a) => a.a !== c.id && a.b !== c.id);

  const wasPlayer = game.isPlayer(c.id);
  const heir = c.titles.length ? inherit(game, c) : undefined;
  game.markDirty();

  const name = game.scopeName({ type: 'character', id: c.id }, 'full_name');
  game.message(
    game.loc.tOr(`death.${reason}`, game.loc.t('death.generic', { who: name }), { who: name }),
    'death',
    { type: 'character', id: c.id },
    [c.id, c.liege],
  );
  game.emit('character.death', { character: c, reason, killer, heir: heir?.id });

  if (wasPlayer) {
    if (heir) {
      game.state.player = heir.id;
      game.message(game.loc.t('msg.you_now_play', { who: game.scopeName({ type: 'character', id: heir.id }, 'full_name') }), 'event', { type: 'character', id: heir.id });
      game.emit('player.succession', { from: c.id, to: heir.id });
      game.onAction('on_player_succession', { type: 'character', id: heir.id }, { predecessor: { type: 'character', id: c.id } });
    } else {
      game.state.gameOver = { reason: 'no_heir', date: game.date };
      game.emit('game.over', { reason: 'no_heir' });
    }
  }
}

/** Распределяет титулы умершего. Возвращает основного наследника. */
export function inherit(game: Game, c: Character): Character | undefined {
  const law = lawOf(game, c);
  const algo = law ? game.engine.registries.successionAlgorithms.get(law.algorithm) : undefined;
  let heirs = law && algo ? algo.heirs(game, c, law) : bloodLine(game, c, 'male_preference');
  heirs = heirs.filter((id) => isAlive(game.char(id)));
  const oldLiege = game.char(c.liege);
  const vassals = game.vassalsOf(c.id);
  const courtiers = game.courtiersOf(c.id);
  const titles = [...c.titles];

  let primary = game.char(heirs[0]);
  let distribution: Record<string, string>;
  if (!primary) {
    if (oldLiege && isAlive(oldLiege)) {
      // Выморочные титулы возвращаются сюзерену.
      primary = oldLiege;
      distribution = Object.fromEntries(titles.map((t) => [t, oldLiege.id]));
    } else {
      // Независимый правитель без наследников: появляется новый род.
      const cap = capitalOf(game, c);
      const pdef = cap ? game.content.get<ProvinceDef>('provinces', cap) : undefined;
      primary = createCharacter(game, {
        culture: game.state.provinces[cap ?? '']?.culture ?? pdef?.culture ?? c.culture,
        faith: game.state.provinces[cap ?? '']?.faith ?? pdef?.faith ?? c.faith,
        female: false,
        age: game.rng.int(20, 40),
        dynasty: 'new',
      });
      distribution = Object.fromEntries(titles.map((t) => [t, primary!.id]));
    }
  } else {
    distribution = law && algo?.distribute ? algo.distribute(game, c, law, heirs) : Object.fromEntries(titles.map((t) => [t, primary!.id]));
    for (const t of titles) if (!distribution[t]) distribution[t] = primary.id;
  }

  const primaryWasLanded = primary.titles.length > 0;
  // Передаём титулы (в порядке убывания ранга, чтобы основной титул был первым).
  const order = [...titles].sort((a, b) => tierOf(game, b) - tierOf(game, a));
  for (const t of order) transferTitle(game, t, distribution[t], { court: primary.id });
  primary.gold += c.gold;
  c.gold = 0;

  // Сюзеренитет наследников.
  const heirChars = [...new Set(Object.values(distribution))].map((id) => game.char(id)!).filter(Boolean);
  for (const h of heirChars) {
    if (h.id === primary.id) {
      if (!primaryWasLanded || h.liege === c.id) setLiege(game, h, oldLiege?.id !== h.id ? oldLiege?.id : undefined);
      continue;
    }
    if (h.liege === c.id || h.liege === undefined || h.liege === primary.liege) {
      setLiege(game, h, primaryTier(game, h) < primaryTier(game, primary) ? primary.id : oldLiege?.id);
    }
  }
  // Вассалы умершего уходят к наследнику, держащему их де-юре сюзеренный титул.
  for (const v of vassals) {
    if (!isAlive(v) || heirChars.some((h) => h.id === v.id)) continue;
    let target: string | undefined;
    let up = deJureLiege(game, v.titles[0] ?? '');
    while (up && !target) {
      const holder = distribution[up];
      if (holder && primaryTier(game, game.char(holder)!) > primaryTier(game, v)) target = holder;
      up = deJureLiege(game, up);
    }
    setLiege(game, v, target ?? primary.id);
  }
  // Придворные: к наследнику-родственнику или к основному наследнику.
  for (const ct of courtiers) {
    if (!isAlive(ct) || ct.titles.length) continue;
    const kinHeir = heirChars.find((h) => h.titles.length && (h.spouses.includes(ct.id) || ct.father === h.id || ct.mother === h.id));
    setLiege(game, ct, kinHeir?.id ?? (primary.titles.length ? primary.id : primary.liege));
  }
  // Войны и армии переходят к основному наследнику.
  for (const w of Object.values(game.state.wars)) {
    const replace = (list: string[]) => list.map((x) => (x === c.id ? primary!.id : x));
    if (w.attackers.includes(c.id) || w.defenders.includes(c.id)) {
      w.attackers = [...new Set(replace(w.attackers))];
      w.defenders = [...new Set(replace(w.defenders))];
      if (w.attacker === c.id) w.attacker = primary.id;
      if (w.defender === c.id) w.defender = primary.id;
    }
  }
  for (const a of Object.values(game.state.armies)) {
    if (a.owner === c.id) {
      a.owner = primary.id;
      a.commander = undefined;
    }
    if (a.commander === c.id) a.commander = undefined;
  }
  c.titles = [];
  game.markDirty();
  for (const h of heirChars) {
    game.onAction('on_inheritance', { type: 'character', id: h.id }, { predecessor: { type: 'character', id: c.id } });
  }
  game.emit('succession', { deceased: c, heirs: heirChars.map((h) => h.id), primary: primary.id, distribution });
  if (domainCounties(game, primary).length === 0 && primary.titles.length) primary.capital = undefined;
  return primary;
}
