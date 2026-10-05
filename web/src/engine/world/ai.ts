import type { DecisionDef, InteractionDef, TraitDef } from '../content/defs';
import type { Game } from '../game';
import { evalValue } from '../script/interpreter';
import type { Army, Character, ScopeRef, War } from '../types';
import { canMarry, isAdult, isAlive } from './characters';
import { decisionBlockers, decisionContext, domainBuildOptions, isDecisionShown, startBuilding, takeDecision } from './decisions';
import { militaryStrength } from './economy';
import {
  acceptance,
  deciderOf,
  executeInteraction,
  hookAvailable,
  interactionBlockers,
  interactionContext,
  interactionDefs,
  isInteractionShown,
  secondaryCandidates,
  targetOptions,
} from './interactions';
import { armiesOf, armyStrength, disbandArmy, hostileWarAt, moveArmy, raiseArmy } from './military';
import { canAffordWar, availableWarTargets, aiWillAcceptSurrender, aiWillAcceptWhitePeace, declareWar, endWar, participantSide, sideOf, warsOf, warscore } from './war';
import { canCreateTitle, createTitle, isInRealmOf, provinceController, realmCounties, topLiege } from './titles';

/**
 * ИИ правителей. Каждый правитель «думает» раз в месяц в свой день
 * (нагрузка размазана по месяцу). Поведение задаётся весами ai_will_do
 * в данных и личностью из черт (traits.ai). Мод может добавить своё
 * поведение через хук "ai.think" или заменить систему "ai" целиком.
 */
export function personality(game: Game, c: Character): Record<string, number> {
  const key = `ai:${c.id}`;
  const cached = game.statCache.get(key);
  if (cached) return cached;
  const out: Record<string, number> = {};
  for (const t of c.traits) {
    for (const [k, v] of Object.entries(game.content.get<TraitDef>('traits', t)?.ai ?? {})) out[k] = (out[k] ?? 0) + v;
  }
  game.statCache.set(key, out);
  return out;
}

function thinkDay(c: Character): number {
  let h = 0;
  for (let i = 0; i < c.id.length; i++) h = (h * 31 + c.id.charCodeAt(i)) | 0;
  return Math.abs(h) % 28;
}

export function dailyAI(game: Game): void {
  const day = (game.date % 365) % 28;
  for (const c of game.rulers()) {
    if (game.isPlayer(c.id) || c.death !== undefined) continue;
    if (thinkDay(c) !== day) continue;
    try {
      thinkRuler(game, c);
    } catch (e) {
      game.scriptError(`ИИ ${c.id}: ${(e as Error).message}`);
    }
  }
  for (const a of Object.values(game.state.armies)) {
    if (game.isPlayer(a.owner)) continue;
    armyAI(game, a);
  }
}

export function thinkRuler(game: Game, c: Character): void {
  if (!game.engine.hooks.veto('ai.think', { game, character: c })) return;
  const ai = game.defines.ai ?? {};
  managePeace(game, c);
  manageArmies(game, c);
  if (!warsOf(game, c.id).length && game.rng.chance(ai.war_check_chance ?? 0.35)) considerWar(game, c);
  considerInteractions(game, c);
  considerDecisions(game, c);
  considerTitles(game, c);
  considerBuilding(game, c);
}

// ------------------------------------------------------------ война

function considerWar(game: Game, c: Character) {
  const ai = game.defines.ai ?? {};
  const p = personality(game, c);
  const targets = availableWarTargets(game, c).filter((t) => canAffordWar(game, c, t));
  if (!targets.length) return;
  const myStr = militaryStrength(game, c);
  let best: { t: (typeof targets)[number]; score: number } | null = null;
  for (const t of targets) {
    const def = game.char(t.defender)!;
    if (game.isPlayer(def.id) && game.rng.chance(ai.spare_player_chance ?? 0)) continue;
    const enemyStr = militaryStrength(game, def) + warsOf(game, def.id).length * 0;
    const ratio = myStr / Math.max(1, enemyStr);
    const need = (ai.war_strength_ratio ?? 1.3) - (p.boldness ?? 0) * 0.02 - (p.aggression ?? 0) * 0.02;
    if (ratio < need) continue;
    const cb = game.content.get('casus_belli', t.cb);
    const ctx = decisionContext(game, c);
    ctx.scopes.defender = { type: 'character', id: t.defender };
    if (t.title) ctx.scopes.target = { type: 'title', id: t.title };
    const will = cb?.ai_will_do != null ? evalValue(ctx, ctx.root, cb.ai_will_do) : 50;
    const score = will * Math.min(3, ratio) * (1 + t.counties.length * 0.1);
    if (score > 0 && (!best || score > best.score)) best = { t, score };
  }
  if (!best) return;
  const chance = Math.min(0.9, (ai.base_war_chance ?? 0.25) + ((p.aggression ?? 0) + (p.greed ?? 0)) * 0.03);
  if (game.rng.chance(chance)) declareWar(game, c, best.t);
}

function managePeace(game: Game, c: Character) {
  for (const w of warsOf(game, c.id)) {
    const side = participantSide(w, c.id);
    const leader = side === 'att' ? w.attacker : w.defender;
    if (leader !== c.id) continue;
    const ws = warscore(game, w).total;
    const mine = side === 'att' ? ws : -ws;
    const enemyLeader = side === 'att' ? w.defender : w.attacker;
    if (mine >= 100) {
      endWar(game, w, side === 'att' ? 'victory' : 'defeat');
      return;
    }
    if (game.isPlayer(enemyLeader)) {
      if (mine <= -(game.defines.ai?.surrender_to_player_at ?? 90)) endWar(game, w, side === 'att' ? 'defeat' : 'victory');
      continue;
    }
    if (mine >= (game.defines.ai?.enforce_at ?? 50) && aiWillAcceptSurrender(game, w, side === 'att' ? 'def' : 'att')) {
      endWar(game, w, side === 'att' ? 'victory' : 'defeat');
      return;
    }
    if (aiWillAcceptWhitePeace(game, w, side!) && aiWillAcceptWhitePeace(game, w, side === 'att' ? 'def' : 'att')) {
      endWar(game, w, 'white_peace');
      return;
    }
  }
}

function manageArmies(game: Game, c: Character) {
  const atWar = warsOf(game, c.id).length > 0;
  const armies = armiesOf(game, c.id);
  if (atWar && !armies.length) raiseArmy(game, c);
  if (!atWar) for (const a of armies) disbandArmy(game, a.id);
}

/** Сила армии для оценок ИИ (без учёта контр), кэшируется на день. */
function cachedStrength(game: Game, a: Army): number {
  return game.cachedDaily(`army:${a.id}`, () => armyStrength(game, a));
}

/** Ежедневно: армии ИИ выбирают цель — вражескую армию послабее или осаду. */
export function armyAI(game: Game, a: Army): void {
  if (a.retreating) return;
  if (a.path.length && a.aiReplan && a.aiReplan > game.date) return;
  const wars = warsOf(game, a.owner);
  if (!wars.length) return;
  const p = game.state.provinces[a.location];
  if (!a.path.length && p?.siege?.army === a.id) return; // продолжаем осаду
  a.aiReplan = game.date + 10;

  let best: { dest: string; score: number } | null = null;
  const consider = (dest: string, score: number) => {
    if (!best || score > best.score) best = { dest, score };
  };
  for (const w of wars) {
    const side = participantSide(w, a.owner)!;
    // Вражеские армии
    for (const e of Object.values(game.state.armies)) {
      const es = participantSide(w, e.owner);
      if (!es || es === side || e.retreating) continue;
      const len = game.engine.pathLength(a.location, e.location);
      if (!Number.isFinite(len) || len > 6 * 80) continue;
      const ratio = cachedStrength(game, a) / Math.max(1, cachedStrength(game, e));
      if (ratio > 1.15) consider(e.location, 120 * Math.min(2, ratio) - (len / 80) * 8);
    }
    // Осады: цели войны в приоритете, затем любые вражеские графства
    const enemyLeaders = side === 'att' ? w.defenders : w.attackers;
    const tset = new Set(w.targetCounties);
    const cand = new Set<string>();
    for (const id of enemyLeaders) {
      const ch = game.char(id);
      if (ch) for (const cty of realmCounties(game, ch)) cand.add(cty);
    }
    // Освобождение своих земель
    const myLeader = game.char(a.owner)!;
    for (const cty of realmCounties(game, topLiege(game, myLeader))) if (game.state.provinces[cty]?.occupantWar === w.id) cand.add(cty);
    for (const cty of cand) {
      const ctrl = provinceController(game, cty);
      if (!ctrl) continue;
      const theirs = sideOf(game, w, ctrl.id);
      const occupiedByUs = game.state.provinces[cty]?.occupantWar === w.id && participantSide(w, game.state.provinces[cty].occupant!) === side;
      if (theirs === side && !game.state.provinces[cty]?.occupant) continue;
      if (occupiedByUs) continue;
      const len = game.engine.pathLength(a.location, cty);
      if (!Number.isFinite(len)) continue;
      const liberation = theirs === side;
      const isMyCapital = cty === myLeader.capital || cty === topLiege(game, myLeader).capital;
      let score = (liberation ? (isMyCapital ? 70 : 20) : tset.has(cty) ? 80 : 40) - (len / 80) * 6;
      // не лезем в провинцию, где стоит вражеская армия сильнее нас
      const danger = Object.values(game.state.armies).some(
        (e) => e.location === cty && participantSide(w, e.owner) && participantSide(w, e.owner) !== side && cachedStrength(game, e) > cachedStrength(game, a) * 0.9,
      );
      if (danger) score -= 200;
      consider(cty, score);
    }
  }
  const chosen = best as { dest: string; score: number } | null;
  if (!chosen) return;
  if (chosen.dest === a.location) {
    a.path = [];
    return;
  }
  if (a.aiTarget !== chosen.dest || !a.path.length) {
    moveArmy(game, a.id, chosen.dest);
    a.aiTarget = chosen.dest;
  }
  void hostileWarAt;
}

// ------------------------------------------------------------ взаимодействия

function aiTargets(game: Game, c: Character, def: InteractionDef, cache: Map<string, ScopeRef[]>): Character[] {
  const lists = def.ai_targets ? (Array.isArray(def.ai_targets) ? def.ai_targets : [def.ai_targets]) : [];
  const out = new Map<string, Character>();
  const ctx = interactionContext(game, def, c, c);
  for (const name of lists) {
    const list = game.engine.script.lists.get(name);
    if (!list) continue;
    // Один и тот же список (соседи, вассалы…) за ход правителя считаем один раз.
    let refs = cache.get(name);
    if (!refs) {
      refs = list.list(ctx, ctx.root);
      cache.set(name, refs);
    }
    for (const r of refs) {
      if (r.type !== 'character') continue;
      const x = game.char(r.id);
      if (x && isAlive(x) && x.id !== c.id) out.set(x.id, x);
    }
  }
  if (def.self) out.set(c.id, c);
  const arr = [...out.values()];
  game.rng.shuffle(arr);
  return arr.slice(0, game.defines.ai?.max_targets_per_interaction ?? 12);
}

function considerInteractions(game: Game, c: Character) {
  const ai = game.defines.ai ?? {};
  const defs = interactionDefs(game).filter((d) => d.ai_will_do != null && (d.ai_targets || d.self));
  const listCache = new Map<string, ScopeRef[]>();
  for (const def of defs) {
    const freq = def.ai_frequency_months ?? 6;
    if (!game.rng.chance(1 / freq)) continue;
    let best: { r: Character; sec?: string; target?: any; score: number; useHook?: boolean } | null = null;
    for (const r of aiTargets(game, c, def, listCache)) {
      if (!isInteractionShown(game, def, c, r)) continue;
      const secs = def.secondary_actor ? secondaryCandidates(game, def, c, r).slice(0, 4).map((x) => x.id) : [undefined];
      const targs = def.target ? targetOptions(game, def, c, r).slice(0, 4) : [undefined];
      for (const sec of secs) {
        for (const t of targs) {
          const args: { secondary?: string; target?: any; useHook?: boolean } = { secondary: sec, target: t?.ref };
          if (interactionBlockers(game, def, c, r, args).length) continue;
          const ctx = interactionContext(game, def, c, r, args);
          const will = evalValue(ctx, ctx.root, def.ai_will_do);
          if (will <= 0) continue;
          // Не предлагаем то, на что заведомо откажут (кроме игрока — тот решает сам),
          // если только нет крюка, которым можно заставить согласиться.
          const decider = deciderOf(game, def, r);
          if (!game.isPlayer(decider.id)) {
            const acc = acceptance(game, def, c, r, args);
            if (!acc.auto && acc.total <= 0) {
              if (!hookAvailable(game, def, c, r) || will < (game.defines.ai?.use_hook_min_will ?? 30)) continue;
              args.useHook = true;
            }
          } else if (hookAvailable(game, def, c, r) && will >= (game.defines.ai?.use_hook_on_player_min_will ?? 60)) args.useHook = true;
          if (!best || will > best.score) best = { r, sec, target: t?.ref, score: will, useHook: args.useHook };
        }
      }
    }
    if (best && game.rng.next() * 100 < Math.min(ai.max_interaction_chance ?? 90, best.score)) {
      executeInteraction(game, def, c, best.r, { secondary: best.sec, target: best.target, useHook: best.useHook });
    }
  }
  arrangeMarriages(game, c);
}

/** Отдельная эвристика для браков членов семьи и двора — самая частая задача ИИ. */
function arrangeMarriages(game: Game, c: Character) {
  const def = game.content.get<InteractionDef>('interactions', 'arrange_marriage');
  if (!def || !game.rng.chance(game.defines.ai?.marriage_chance ?? 0.5)) return;
  const family = [...game.courtiersOf(c.id), c].filter(
    (x) => isAlive(x) && isAdult(game, x) && !x.spouses.length && (x.id === c.id || x.dynasty === c.dynasty || x.father === c.id),
  );
  if (!family.length) return;
  const single = game.rng.pick(family)!;
  const pool = game.rulers().flatMap((r) => (r.id === c.id ? [] : [r, ...game.courtiersOf(r.id)]));
  const candidates = pool.filter((x) => isAlive(x) && canMarry(game, single, x) && !game.isPlayer(x.id));
  game.rng.shuffle(candidates);
  for (const cand of candidates.slice(0, 15)) {
    const recipient = cand;
    if (!isInteractionShown(game, def, c, recipient)) continue;
    const args = { secondary: single.id };
    if (interactionBlockers(game, def, c, recipient, args).length) continue;
    const acc = acceptance(game, def, c, recipient, args);
    if (acc.auto || acc.total > 0) {
      executeInteraction(game, def, c, recipient, args);
      return;
    }
  }
}

function considerDecisions(game: Game, c: Character) {
  for (const def of game.content.all<DecisionDef>('decisions')) {
    if (def.ai_will_do == null) continue;
    if (!game.rng.chance(1 / (def.ai_check_months ?? 6))) continue;
    if (!isDecisionShown(game, def, c) || decisionBlockers(game, def, c).length) continue;
    const ctx = decisionContext(game, c);
    if (game.rng.next() * 100 < evalValue(ctx, ctx.root, def.ai_will_do)) takeDecision(game, def, c);
  }
}

function considerTitles(game: Game, c: Character) {
  if (!game.rng.chance(0.25)) return;
  const candidates = new Set<string>();
  for (const cty of realmCounties(game, c).slice(0, 40)) {
    let t = game.content.get('titles', cty)?.liege;
    while (t) {
      if (!game.state.titles[t]?.holder) candidates.add(t);
      t = game.content.get('titles', t)?.liege;
    }
  }
  for (const t of candidates) if (canCreateTitle(game, c, t).ok) createTitle(game, c, t);
}

function considerBuilding(game: Game, c: Character) {
  const reserve = game.defines.ai?.gold_reserve ?? 60;
  if (c.gold < reserve) return;
  if (!game.rng.chance(game.defines.ai?.build_chance ?? 0.3)) return;
  const opts = domainBuildOptions(game, c).filter((o) => (o.def.cost.gold as number ?? 0) + reserve <= c.gold);
  const pick = game.rng.pick(opts);
  if (pick) startBuilding(game, c, pick.province, pick.def.id);
}

/** ИИ игрока-вассала: держит ли он сторону сюзерена (используется модами). */
export function isLoyal(game: Game, c: Character): boolean {
  const l = game.char(c.liege);
  return !!l && isInRealmOf(game, c, l);
}

export function warForAI(game: Game, id: string): War | undefined {
  return warsOf(game, id)[0];
}
