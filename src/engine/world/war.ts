import type { CasusBelliDef } from '../content/defs';
import { DAYS_PER_YEAR } from '../core/date';
import type { TextValue } from '../core/localization';
import type { Game } from '../game';
import { makeContext } from '../script/context';
import { evalTrigger, evalValue, runEffect } from '../script/interpreter';
import type { Character, War } from '../types';
import { isAlive } from './characters';
import { opinion } from './opinion';
import {
  deJureCounties,
  deJureVassalTitles,
  domainCounties,
  isInRealmOf,
  primaryTier,
  realmCounties,
  tierOf,
  topLiege,
} from './titles';

/**
 * Войны. Поводы к войне (casus_belli) описываются в данных; список
 * возможных целей для каждого повода даёт «поставщик целей» из
 * registries.cbTargets — мод может добавить новый тип войны.
 */
export interface WarTarget {
  cb: string;
  defender: string;
  title?: string;
  counties: string[];
}

export interface CbTargetProvider {
  label?: TextValue;
  targets(game: Game, attacker: Character): Omit<WarTarget, 'cb'>[];
}

export function warsOf(game: Game, id: string): War[] {
  return Object.values(game.state.wars).filter((w) => w.attackers.includes(id) || w.defenders.includes(id));
}

export function isAtWar(game: Game, id: string): boolean {
  return warsOf(game, id).length > 0;
}

export function participantSide(w: War, id: string): 'att' | 'def' | null {
  if (w.attackers.includes(id)) return 'att';
  if (w.defenders.includes(id)) return 'def';
  return null;
}

/** Сторона персонажа в войне — как участника или как вассала участника. */
export function sideOf(game: Game, w: War, id: string | undefined): 'att' | 'def' | null {
  let cur = game.char(id);
  for (let i = 0; i < 30 && cur; i++) {
    const s = participantSide(w, cur.id);
    if (s) return s;
    cur = game.char(cur.liege);
  }
  return null;
}

export function countySide(game: Game, w: War, countyId: string): 'att' | 'def' | null {
  const p = game.state.provinces[countyId];
  if (p?.occupant && p.occupantWar === w.id) return participantSide(w, p.occupant) ?? sideOf(game, w, p.occupant);
  return sideOf(game, w, game.state.titles[countyId]?.holder);
}

export function isAtWarWith(game: Game, a: string, b: string): boolean {
  for (const w of warsOf(game, a)) {
    const sa = participantSide(w, a);
    const sb = participantSide(w, b);
    if (sa && sb && sa !== sb) return true;
  }
  return false;
}

export function enemiesOf(game: Game, id: string): string[] {
  const out = new Set<string>();
  for (const w of warsOf(game, id)) {
    const s = participantSide(w, id);
    for (const e of s === 'att' ? w.defenders : w.attackers) out.add(e);
  }
  return [...out];
}

export function hasTruce(game: Game, a: string, b: string): boolean {
  return game.state.truces.some((t) => t.until > game.date && ((t.a === a && t.b === b) || (t.a === b && t.b === a)));
}

export function alliesOf(game: Game, id: string): string[] {
  return game.state.alliances.flatMap((al) => (al.a === id ? [al.b] : al.b === id ? [al.a] : [])).filter((x) => game.isAlive(x));
}

export function isAllied(game: Game, a: string, b: string): boolean {
  return game.state.alliances.some((al) => (al.a === a && al.b === b) || (al.a === b && al.b === a));
}

// ------------------------------------------------------------ цели войны

export const builtinCbTargets: Record<string, CbTargetProvider> = {
  claim: {
    targets(game, attacker) {
      const out: Omit<WarTarget, 'cb'>[] = [];
      const myTop = topLiege(game, attacker);
      for (const t of attacker.claims) {
        const h = game.char(game.state.titles[t]?.holder);
        if (!h || !isAlive(h) || h.id === attacker.id) continue;
        if (topLiege(game, h).id === myTop.id) continue;
        const realm = new Set(realmCounties(game, h));
        const counties = deJureCounties(game, t).filter((c) => realm.has(c));
        out.push({ defender: h.id, title: t, counties: counties.length ? counties : domainCounties(game, h) });
      }
      return out;
    },
  },
  de_jure: {
    targets(game, attacker) {
      const out: Omit<WarTarget, 'cb'>[] = [];
      const mine = new Set(realmCounties(game, attacker));
      const myTop = topLiege(game, attacker);
      const duchies = new Set<string>();
      for (const t of attacker.titles) {
        const tr = tierOf(game, t);
        if (tr === 2) duchies.add(t);
        if (tr >= 3) {
          const stack = [t];
          while (stack.length) {
            const x = stack.pop()!;
            for (const ch of deJureVassalTitles(game, x)) {
              const r = tierOf(game, ch);
              if (r === 2) duchies.add(ch);
              else if (r > 2) stack.push(ch);
            }
          }
        }
      }
      for (const d of duchies) {
        const byDefender = new Map<string, string[]>();
        for (const c of deJureCounties(game, d)) {
          if (mine.has(c)) continue;
          const h = game.char(game.state.titles[c]?.holder);
          if (!h) continue;
          const def = topLiege(game, h);
          if (def.id === myTop.id || def.id === attacker.id) continue;
          const l = byDefender.get(def.id) ?? [];
          l.push(c);
          byDefender.set(def.id, l);
        }
        for (const [defender, counties] of byDefender) out.push({ defender, title: d, counties });
      }
      return out;
    },
  },
  independence: {
    targets(game, attacker) {
      if (!attacker.liege || !attacker.titles.length) return [];
      const l = game.char(attacker.liege);
      if (!l || !isAlive(l)) return [];
      return [{ defender: l.id, title: attacker.titles[0], counties: realmCounties(game, attacker) }];
    },
  },
  adjacent_county: {
    targets(game, attacker) {
      if (attacker.liege) return [];
      const mine = new Set(realmCounties(game, attacker));
      const out: Omit<WarTarget, 'cb'>[] = [];
      const seen = new Set<string>();
      for (const c of mine) {
        for (const n of game.engine.neighbors(c)) {
          if (mine.has(n) || seen.has(n)) continue;
          seen.add(n);
          const h = game.char(game.state.titles[n]?.holder);
          if (!h) continue;
          const def = topLiege(game, h);
          if (def.id === attacker.id) continue;
          out.push({ defender: def.id, title: n, counties: [n] });
        }
      }
      return out;
    },
  },
  holy_war: {
    targets(game, attacker) {
      if (attacker.liege) return [];
      const out: Omit<WarTarget, 'cb'>[] = [];
      const mine = realmCounties(game, attacker);
      const mineSet = new Set(mine);
      const border = new Set<string>();
      for (const c of mine) for (const n of game.engine.neighbors(c)) if (!mineSet.has(n)) border.add(n);
      const seen = new Set<string>();
      for (const c of border) {
        const h = game.char(game.state.titles[c]?.holder);
        if (!h) continue;
        const def = topLiege(game, h);
        if (def.faith === attacker.faith || def.id === attacker.id) continue;
        const duchy = game.content.get('titles', c)?.liege;
        const key = `${def.id}:${duchy ?? c}`;
        if (seen.has(key)) continue;
        seen.add(key);
        const realm = new Set(realmCounties(game, def));
        const counties = (duchy ? deJureCounties(game, duchy) : [c]).filter((x) => realm.has(x));
        out.push({ defender: def.id, title: duchy ?? c, counties });
      }
      return out;
    },
  },
};

function cbContext(game: Game, attacker: string, t: Omit<WarTarget, 'cb'>, warId?: string) {
  const scopes: Record<string, any> = {
    attacker: { type: 'character', id: attacker },
    defender: { type: 'character', id: t.defender },
  };
  if (t.title) scopes.target = { type: 'title', id: t.title };
  if (warId) scopes.war = { type: 'war', id: warId };
  return makeContext(game, { type: 'character', id: attacker }, scopes);
}

/** Все доступные персонажу поводы к войне (опционально — только против defender). */
export function availableWarTargets(game: Game, attacker: Character, defender?: string): WarTarget[] {
  if (!attacker.titles.length) return [];
  const out: WarTarget[] = [];
  for (const cb of game.content.all<CasusBelliDef>('casus_belli')) {
    const prov = game.engine.registries.cbTargets.get(cb.targets);
    if (!prov) {
      game.scriptError(`Нет поставщика целей войны "${cb.targets}"`);
      continue;
    }
    for (const t of prov.targets(game, attacker)) {
      if (defender && t.defender !== defender) continue;
      if (t.defender === attacker.id) continue;
      if (hasTruce(game, attacker.id, t.defender) || isAtWarWith(game, attacker.id, t.defender)) continue;
      if (Object.values(game.state.wars).some((w) => w.attacker === attacker.id && w.defender === t.defender)) continue;
      const ctx = cbContext(game, attacker.id, t);
      if (!evalTrigger(ctx, ctx.root, cb.is_valid)) continue;
      out.push({ ...t, cb: cb.id });
    }
  }
  return out;
}

export function warCost(game: Game, attacker: Character, t: WarTarget): { gold: number; prestige: number; piety: number } {
  const cb = game.content.require<CasusBelliDef>('casus_belli', t.cb);
  const ctx = cbContext(game, attacker.id, t);
  return {
    gold: Math.round(evalValue(ctx, ctx.root, cb.cost?.gold ?? 0)),
    prestige: Math.round(evalValue(ctx, ctx.root, cb.cost?.prestige ?? 0)),
    piety: Math.round(evalValue(ctx, ctx.root, cb.cost?.piety ?? 0)),
  };
}

export function canAffordWar(game: Game, attacker: Character, t: WarTarget): boolean {
  const c = warCost(game, attacker, t);
  return attacker.gold >= c.gold && attacker.prestige >= c.prestige && attacker.piety >= c.piety;
}

/** ИИ-союзник решает, вступать ли в войну. */
export function allyWillJoin(game: Game, ally: Character, leader: Character, enemy: string): boolean {
  if (!isAlive(ally) || !ally.titles.length) return false;
  if (isAtWarWith(game, ally.id, leader.id) || ally.id === enemy) return false;
  if (game.isPlayer(ally.id)) return true;
  if (isAllied(game, ally.id, enemy)) return false;
  return opinion(game, ally, leader) >= (game.defines.war?.ally_min_opinion ?? -10);
}

export function declareWar(game: Game, attacker: Character, t: WarTarget): War | null {
  const cb = game.content.get<CasusBelliDef>('casus_belli', t.cb);
  const defender = game.char(t.defender);
  if (!cb || !defender || !isAlive(defender)) return null;
  if (!game.engine.hooks.veto('war.before_declare', { game, attacker, target: t })) return null;
  const cost = warCost(game, attacker, t);
  attacker.gold -= cost.gold;
  attacker.prestige -= cost.prestige;
  attacker.piety -= cost.piety;
  const w: War = {
    id: game.newId('war'),
    cb: t.cb,
    attacker: attacker.id,
    defender: defender.id,
    attackers: [attacker.id],
    defenders: [defender.id],
    target: t.title,
    targetCounties: [...t.counties],
    start: game.date,
    battleScore: 0,
    ticking: 0,
  };
  game.state.wars[w.id] = w;
  const ctx = cbContext(game, attacker.id, t, w.id);
  w.name = game.text(cb.war_name ?? 'ui.war_name_default', ctx, {
    attacker: game.scopeName({ type: 'character', id: attacker.id }),
    defender: game.scopeName({ type: 'character', id: defender.id }),
    target: t.title ? game.scopeName({ type: 'title', id: t.title }) : '',
  });
  for (const al of alliesOf(game, attacker.id)) {
    const a = game.char(al)!;
    if (allyWillJoin(game, a, attacker, defender.id) && !w.defenders.includes(al)) w.attackers.push(al);
  }
  for (const al of alliesOf(game, defender.id)) {
    const a = game.char(al)!;
    if (allyWillJoin(game, a, defender, attacker.id) && !w.attackers.includes(al)) w.defenders.push(al);
  }
  runEffect(ctx, ctx.root, cb.on_declare);
  game.markDirty();
  game.message(game.loc.t('msg.war_declared', { name: w.name }), 'war', { type: 'war', id: w.id }, [...w.attackers, ...w.defenders]);
  game.onAction('on_war_started', { type: 'character', id: attacker.id }, ctx.scopes);
  game.emit('war.declared', { war: w });
  return w;
}

// ------------------------------------------------------------ счёт войны

export interface WarscoreInfo {
  total: number;
  battle: number;
  occupation: number;
  ticking: number;
}

export function warscore(game: Game, w: War): WarscoreInfo {
  const g = game.defines.war ?? {};
  const attSide = new Set(w.attackers.flatMap((id) => (game.char(id) ? realmCounties(game, game.char(id)!) : [])));
  const defSide = new Set(w.defenders.flatMap((id) => (game.char(id) ? realmCounties(game, game.char(id)!) : [])));
  const targets = w.targetCounties.filter((c) => game.state.provinces[c]);
  const targetsOnAtt = targets.length > 0 && targets.filter((c) => attSide.has(c)).length > targets.filter((c) => defSide.has(c)).length;
  const occBy = (c: string, side: 'att' | 'def') => {
    const p = game.state.provinces[c];
    return !!p?.occupant && p.occupantWar === w.id && participantSide(w, p.occupant) === side;
  };
  const occScore = (enemyCounties: Set<string>, side: 'att' | 'def', tgts: string[]) => {
    const tset = new Set(tgts.filter((c) => enemyCounties.has(c)));
    const others = [...enemyCounties].filter((c) => !tset.has(c));
    const tf = tset.size ? [...tset].filter((c) => occBy(c, side)).length / tset.size : 0;
    const of = others.length ? others.filter((c) => occBy(c, side)).length / others.length : tf;
    if (!tset.size) return 100 * of;
    return (g.target_weight ?? 70) * tf + (100 - (g.target_weight ?? 70)) * of;
  };
  const capBonus = g.capital_bonus ?? 15;
  const capOcc = (leader: string, side: 'att' | 'def') => {
    const cap = game.char(leader)?.capital;
    return cap && occBy(cap, side) ? capBonus : 0;
  };
  const occAtt = Math.min(100, occScore(defSide, 'att', targetsOnAtt ? [] : targets) + capOcc(w.defender, 'att'));
  const occDef = Math.min(100, occScore(attSide, 'def', targetsOnAtt ? targets : []) + capOcc(w.attacker, 'def'));
  const battle = Math.max(-(g.max_battle_score ?? 40), Math.min(g.max_battle_score ?? 40, w.battleScore));
  const ticking = Math.max(-(g.max_ticking ?? 25), Math.min(g.max_ticking ?? 25, w.ticking));
  const occupation = occAtt - occDef;
  const total = Math.max(-100, Math.min(100, Math.round(occupation + battle + ticking)));
  return { total, battle: Math.round(battle), occupation: Math.round(occupation), ticking: Math.round(ticking) };
}

/** Ежемесячно: «тикающий» счёт за удержание целей войны. */
export function updateTicking(game: Game, w: War): void {
  const g = game.defines.war ?? {};
  const targets = w.targetCounties.filter((c) => game.state.provinces[c]);
  if (!targets.length) return;
  const months = (game.date - w.start) / 30;
  const occ = (side: 'att' | 'def') =>
    targets.filter((c) => {
      const p = game.state.provinces[c];
      return p?.occupant && p.occupantWar === w.id && participantSide(w, p.occupant) === side;
    }).length;
  const attSide = sideOf(game, w, game.state.titles[targets[0]]?.holder) === 'att';
  if (!attSide) {
    const o = occ('att');
    if (o === targets.length) w.ticking += g.ticking_gain ?? 2;
    else if (o === 0 && months > (g.defender_ticking_after_months ?? 12)) w.ticking -= g.ticking_loss ?? 1;
  } else {
    const o = occ('def');
    if (o === targets.length) w.ticking -= g.ticking_gain ?? 2;
    else if (o === 0 && months > (g.defender_ticking_after_months ?? 12)) w.ticking += g.ticking_loss ?? 1;
  }
  w.ticking = Math.max(-(g.max_ticking ?? 25), Math.min(g.max_ticking ?? 25, w.ticking));
}

// ------------------------------------------------------------ мир

export type WarOutcome = 'victory' | 'white_peace' | 'defeat';

export function endWar(game: Game, w: War, outcome: WarOutcome): void {
  if (!game.state.wars[w.id]) return;
  const cb = game.content.get<CasusBelliDef>('casus_belli', w.cb);
  const scopes: Record<string, any> = {
    attacker: { type: 'character', id: w.attacker },
    defender: { type: 'character', id: w.defender },
    war: { type: 'war', id: w.id },
  };
  if (w.target) scopes.target = { type: 'title', id: w.target };
  const ctx = makeContext(game, { type: 'character', id: w.attacker }, scopes);
  if (game.isAlive(w.attacker) && game.isAlive(w.defender)) {
    const block = outcome === 'victory' ? cb?.on_victory : outcome === 'defeat' ? cb?.on_defeat : cb?.on_white_peace;
    runEffect(ctx, ctx.root, block);
  }
  const years = cb?.truce_years ?? game.defines.war?.truce_years ?? 5;
  game.state.truces.push({ a: w.attacker, b: w.defender, until: game.date + years * DAYS_PER_YEAR });
  game.state.truces = game.state.truces.filter((t) => t.until > game.date);
  for (const p of Object.values(game.state.provinces)) {
    if (p.occupantWar === w.id) {
      p.occupant = undefined;
      p.occupantWar = undefined;
    }
    if (p.siege && game.state.armies[p.siege.army]?.war === w.id) p.siege = undefined;
  }
  delete game.state.wars[w.id];
  game.markDirty();
  // ИИ распускает войска, если больше ни с кем не воюет.
  for (const id of [...w.attackers, ...w.defenders]) {
    if (game.isPlayer(id) || isAtWar(game, id)) continue;
    for (const a of Object.values(game.state.armies)) if (a.owner === id) disbandArmyRef(game, a.id);
  }
  const key = outcome === 'victory' ? 'msg.war_won_att' : outcome === 'defeat' ? 'msg.war_won_def' : 'msg.war_white_peace';
  game.message(game.loc.t(key, { name: w.name ?? '' }), 'war', undefined, [...w.attackers, ...w.defenders]);
  const { war: _war, ...endScopes } = scopes;
  if (game.isAlive(w.attacker)) game.onAction('on_war_ended', { type: 'character', id: w.attacker }, endScopes);
  game.emit('war.ended', { war: w, outcome });
}

// Разрываем циклическую зависимость с military.ts через позднее связывание.
let disbandArmyRef: (game: Game, id: string) => void = () => {};
export function _setDisband(fn: (game: Game, id: string) => void) {
  disbandArmyRef = fn;
}

/** Ежемесячная проверка: война теряет смысл, если лидеры умерли или цель утрачена. */
export function validateWars(game: Game): void {
  for (const w of Object.values(game.state.wars)) {
    w.attackers = w.attackers.filter((id) => game.isAlive(id) && game.char(id)!.titles.length);
    w.defenders = w.defenders.filter((id) => game.isAlive(id) && game.char(id)!.titles.length);
    if (!game.isAlive(w.attacker) || !game.isAlive(w.defender) || !w.attackers.includes(w.attacker) || !w.defenders.includes(w.defender)) {
      endWar(game, w, 'white_peace');
      continue;
    }
    if (w.cb === 'independence' || game.content.get<CasusBelliDef>('casus_belli', w.cb)?.targets === 'independence') {
      if (game.char(w.attacker)!.liege !== w.defender) endWar(game, w, 'white_peace');
      continue;
    }
    // Цели больше не во владении стороны защитника
    const def = game.char(w.defender)!;
    const stillHeld = w.targetCounties.some((c) => {
      const h = game.char(game.state.titles[c]?.holder);
      return h && isInRealmOf(game, h, def);
    });
    if (w.targetCounties.length && !stillHeld) endWar(game, w, 'white_peace');
  }
}

/** Насколько сторона готова сдаться (для ИИ). */
export function aiWillAcceptSurrender(game: Game, w: War, loserSide: 'att' | 'def'): boolean {
  const ws = warscore(game, w).total;
  const score = loserSide === 'def' ? ws : -ws;
  const g = game.defines.war ?? {};
  if (score >= 100) return true;
  // «Военная усталость»: чем дольше война, тем охотнее проигрывающий сдаётся.
  const years = (game.date - w.start) / DAYS_PER_YEAR;
  const fatigue = Math.max(0, years - (g.fatigue_after_years ?? 2)) * (g.fatigue_per_year ?? 6);
  return score >= Math.max(g.min_surrender_threshold ?? 40, (g.ai_surrender_threshold ?? 75) - fatigue);
}

export function aiWillAcceptWhitePeace(game: Game, w: War, side: 'att' | 'def'): boolean {
  const ws = warscore(game, w).total;
  const mine = side === 'att' ? ws : -ws;
  const years = (game.date - w.start) / DAYS_PER_YEAR;
  const g = game.defines.war ?? {};
  if (mine <= -(g.white_peace_losing ?? 25)) return true;
  return years >= (g.white_peace_years ?? 3) && Math.abs(ws) <= (g.white_peace_max_score ?? 30);
}

export function primaryWarTier(game: Game, id: string): number {
  const c = game.char(id);
  return c ? primaryTier(game, c) : 0;
}
