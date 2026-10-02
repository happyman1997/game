import type { TerrainDef } from '../content/defs';
import type { Game } from '../game';
import type { Army, Character, War } from '../types';
import { isAdult, isAlive } from './characters';
import { realmLevy } from './economy';
import { skill, stat } from './stats';
import { capitalOf, domainCounties, provinceController, realmMembers } from './titles';
import { _setDisband, participantSide, sideOf, warsOf } from './war';
import { killCharacter } from './succession';

/**
 * Армии: сбор ополчения, передвижение по графу соседства провинций,
 * сражения и осады. Числа — в defines.military.
 */
function mil(game: Game) {
  return game.defines.military ?? {};
}

export function armiesOf(game: Game, id: string): Army[] {
  return Object.values(game.state.armies).filter((a) => a.owner === id);
}

export function armiesAt(game: Game, provId: string): Army[] {
  return Object.values(game.state.armies).filter((a) => a.location === provId);
}

export function canRaiseArmy(game: Game, c: Character): boolean {
  return c.titles.length > 0 && armiesOf(game, c.id).length === 0 && realmLevy(game, c) >= (mil(game).min_army ?? 50);
}

export function raiseArmy(game: Game, c: Character): Army | null {
  if (!canRaiseArmy(game, c)) return null;
  const size = realmLevy(game, c);
  const loc = capitalOf(game, c) ?? domainCounties(game, c)[0];
  if (!loc) return null;
  const a: Army = {
    id: game.newId('army'),
    owner: c.id,
    size,
    maxSize: size,
    location: loc,
    path: [],
    progress: 0,
  };
  game.state.armies[a.id] = a;
  game.emit('army.raised', { army: a });
  game.notify('army');
  return a;
}

export function disbandArmy(game: Game, id: string): void {
  const a = game.state.armies[id];
  if (!a) return;
  const owner = game.char(a.owner);
  if (owner && isAlive(owner)) {
    const ratio = a.maxSize > 0 ? Math.max(0, Math.min(1, a.size / a.maxSize)) : 1;
    const minR = mil(game).min_levy_ratio ?? 0.1;
    for (const m of realmMembers(game, owner)) m.levyRatio = Math.max(minR, m.levyRatio * ratio);
  }
  for (const p of Object.values(game.state.provinces)) if (p.siege?.army === id) p.siege = undefined;
  delete game.state.armies[id];
  game.emit('army.disbanded', { army: a });
  game.notify('army');
}
_setDisband(disbandArmy);

export function commanderOf(game: Game, a: Army): Character | undefined {
  const c = game.char(a.commander) ?? game.char(a.owner);
  return c && isAlive(c) && isAdult(game, c) && !c.prison ? c : undefined;
}

// ------------------------------------------------------------ путь

export function edgeCost(game: Game, from: string, to: string): number {
  const terrain = game.content.get<TerrainDef>('terrain', game.content.get('provinces', to)?.terrain ?? '');
  return game.engine.distance(from, to) * (terrain?.movement ?? 1);
}

/** Кратчайший путь по таблице путей движка. Возвращает путь без стартовой провинции. */
export function findPath(game: Game, from: string, to: string): string[] | null {
  if (from === to) return [];
  const t = game.engine.pathTable();
  const n = t.ids.length;
  let i = t.index.get(from);
  const j = t.index.get(to);
  if (i === undefined || j === undefined || !Number.isFinite(t.dist[i * n + j])) return null;
  const path: string[] = [];
  for (let guard = 0; i !== j && guard < n; guard++) {
    const nx: number = t.next[i * n + j];
    if (nx < 0) return null;
    path.push(t.ids[nx]);
    i = nx;
  }
  return path;
}

/** Число переходов по кратчайшему пути (для оценок ИИ). */
export function pathSteps(game: Game, from: string, to: string): number {
  if (from === to) return 0;
  const p = findPath(game, from, to);
  return p ? p.length : Infinity;
}

export function moveArmy(game: Game, id: string, dest: string): boolean {
  const a = game.state.armies[id];
  if (!a || a.retreating) return false;
  const path = findPath(game, a.location, dest);
  if (!path) return false;
  a.path = path;
  a.progress = 0;
  game.notify('army');
  return true;
}

/** Сколько дней до следующей провинции на пути. */
export function daysToNext(game: Game, a: Army): number {
  if (!a.path.length) return 0;
  return Math.ceil(((1 - a.progress) * edgeCost(game, a.location, a.path[0])) / (mil(game).speed ?? 12));
}

// ------------------------------------------------------------ враждебность

/** Война, в которой армия враждебна контролёру провинции. */
export function hostileWarAt(game: Game, a: Army, provId: string): War | undefined {
  const ctrl = provinceController(game, provId);
  if (!ctrl) return undefined;
  for (const w of warsOf(game, a.owner)) {
    const mine = participantSide(w, a.owner);
    const p = game.state.provinces[provId];
    const theirs = p.occupant && p.occupantWar === w.id ? participantSide(w, p.occupant) : sideOf(game, w, ctrl.id);
    if (mine && theirs && mine !== theirs) return w;
  }
  return undefined;
}

/** Своя провинция, захваченная врагом в войне, где армия участвует. */
function liberationWarAt(game: Game, a: Army, provId: string): War | undefined {
  const p = game.state.provinces[provId];
  if (!p?.occupant || !p.occupantWar) return undefined;
  const w = game.state.wars[p.occupantWar];
  if (!w) return undefined;
  const mine = participantSide(w, a.owner);
  const holderSide = sideOf(game, w, game.state.titles[provId]?.holder);
  const occSide = participantSide(w, p.occupant);
  return mine && holderSide === mine && occSide !== mine ? w : undefined;
}

function enemyArmiesInWar(game: Game, w: War, side: 'att' | 'def', loc: string): Army[] {
  return armiesAt(game, loc).filter((x) => participantSide(w, x.owner) && participantSide(w, x.owner) !== side && !x.retreating);
}

// ------------------------------------------------------------ ежедневный цикл

export function dailyMilitary(game: Game): void {
  const speed = mil(game).speed ?? 12;
  for (const a of Object.values(game.state.armies)) {
    if (!game.isAlive(a.owner)) {
      delete game.state.armies[a.id];
      continue;
    }
    if (!a.path.length) continue;
    const cost = Math.max(1, edgeCost(game, a.location, a.path[0]));
    a.progress += speed / cost;
    if (a.progress >= 1) {
      a.location = a.path.shift()!;
      a.progress = 0;
      if (!a.path.length) a.retreating = false;
      const p = game.state.provinces[a.location];
      if (p?.siege && p.siege.army !== a.id && !game.state.armies[p.siege.army]) p.siege = undefined;
    }
  }
  resolveBattles(game);
  progressSieges(game);
}

function resolveBattles(game: Game) {
  const byLoc = new Map<string, Army[]>();
  for (const a of Object.values(game.state.armies)) {
    if (a.retreating) continue;
    const l = byLoc.get(a.location) ?? [];
    l.push(a);
    byLoc.set(a.location, l);
  }
  for (const [loc, armies] of byLoc) {
    if (armies.length < 2) continue;
    for (const w of Object.values(game.state.wars)) {
      const att = armies.filter((a) => game.state.armies[a.id] && participantSide(w, a.owner) === 'att' && !a.retreating);
      const def = armies.filter((a) => game.state.armies[a.id] && participantSide(w, a.owner) === 'def' && !a.retreating);
      if (att.length && def.length) battle(game, w, loc, att, def);
    }
  }
}

/** Сила армии с учётом бонусов механик (отряды и т.п.); enemies — армии противника в бою. */
export function armyStrength(game: Game, a: Army, enemies: Army[] = [], location?: string): number {
  let v = a.size;
  for (const b of game.engine.hooks.collect<number>('army.power_bonus', { game, army: a, enemies, location: location ?? a.location })) v += b;
  return Math.max(0, v);
}

function sidePower(game: Game, armies: Army[], defending: boolean, loc: string, enemies: Army[] = []): { power: number; men: number; commander?: Character } {
  const m = mil(game);
  let men = 0;
  let eff = 0;
  let best: Character | undefined;
  for (const a of armies) {
    men += a.size;
    eff += armyStrength(game, a, enemies, loc);
    const c = commanderOf(game, a);
    if (c && (!best || skill(game, c, 'martial') > skill(game, best, 'martial'))) best = c;
  }
  const martial = best ? skill(game, best, 'martial') : 0;
  const adv = best ? stat(game, best, 'commander_advantage') : 0;
  const terrain = game.content.get<TerrainDef>('terrain', game.content.get('provinces', loc)?.terrain ?? '');
  let power = eff * (1 + martial * (m.martial_bonus ?? 0.04) + adv / 100) * game.rng.float(m.battle_luck_min ?? 0.85, m.battle_luck_max ?? 1.15);
  if (defending) power *= 1 + (terrain?.defense ?? 0);
  return { power, men, commander: best };
}

function battle(game: Game, w: War, loc: string, att: Army[], def: Army[]) {
  const m = mil(game);
  const ctrlSide = sideOf(game, w, provinceController(game, loc)?.id);
  const A = sidePower(game, att, ctrlSide === 'att', loc, def);
  const D = sidePower(game, def, ctrlSide === 'def', loc, att);
  const attWins = A.power >= D.power;
  const [win, lose, winArmies, loseArmies] = attWins ? [A, D, att, def] : [D, A, def, att];
  const ratio = Math.min(1, lose.power / Math.max(1, win.power));
  const loseLoss = Math.round(lose.men * ((m.loser_loss_base ?? 0.25) + (m.loser_loss_scale ?? 0.4) * (1 - ratio)));
  const winLoss = Math.round(win.men * ((m.winner_loss_base ?? 0.05) + (m.winner_loss_scale ?? 0.2) * ratio));
  const distribute = (armies: Army[], total: number, men: number) => {
    for (const a of armies) {
      const before = a.size;
      a.size = Math.max(0, a.size - Math.round((total * a.size) / Math.max(1, men)));
      // профессиональные отряды несут потери в той же доле
      if (a.regiments?.length && before > 0) for (const r of a.regiments) r.size = Math.round((r.size * a.size) / before);
    }
  };
  distribute(winArmies, winLoss, win.men);
  distribute(loseArmies, loseLoss, lose.men);

  const loserMax = loseArmies.reduce((s, a) => s + a.maxSize, 0);
  const delta = Math.max(m.battle_score_min ?? 5, Math.min(m.battle_score_max ?? 25, Math.round(5 + (30 * loseLoss) / Math.max(1, loserMax))));
  w.battleScore += attWins ? delta : -delta;

  const winOwner = game.char(winArmies[0].owner)!;
  const loseOwner = game.char(loseArmies[0].owner)!;
  winOwner.prestige += m.battle_prestige ?? 20;
  loseOwner.prestige -= (m.battle_prestige ?? 20) / 2;

  const provName = game.nameOf('provinces', loc);
  game.message(
    game.loc.t('msg.battle', {
      place: provName,
      winner: game.scopeName({ type: 'character', id: winOwner.id }),
      loser: game.scopeName({ type: 'character', id: loseOwner.id }),
      wl: winLoss,
      ll: loseLoss,
    }),
    'war',
    { type: 'province', id: loc },
    [...w.attackers, ...w.defenders],
  );
  game.emit('battle', { war: w, location: loc, winner: winOwner.id, loser: loseOwner.id, winLoss, loseLoss });
  game.onAction('on_battle_won', { type: 'character', id: winOwner.id }, { enemy: { type: 'character', id: loseOwner.id } });
  game.onAction('on_battle_lost', { type: 'character', id: loseOwner.id }, { enemy: { type: 'character', id: winOwner.id } });

  // Гибель полководцев
  if (lose.commander && game.rng.chance(m.loser_commander_death ?? 0.04)) {
    killCharacter(game, lose.commander, 'battle', win.commander?.id);
  } else {
    if (win.commander && game.rng.chance(m.winner_commander_death ?? 0.01)) killCharacter(game, win.commander, 'battle', lose.commander?.id);
    if (lose.commander && lose.commander.death === undefined) game.emit('battle.commander_survived', { war: w, commander: lose.commander.id, captor: winOwner.id });
  }

  // Отступление проигравших
  const loserSide = attWins ? 'def' : 'att';
  for (const a of loseArmies) {
    if (!game.state.armies[a.id]) continue;
    if (a.size < (m.min_army ?? 50)) {
      delete game.state.armies[a.id];
      continue;
    }
    const dest = retreatTarget(game, w, loserSide, a.location);
    if (!dest) {
      delete game.state.armies[a.id];
      continue;
    }
    a.path = findPath(game, a.location, dest) ?? [];
    a.progress = 0;
    a.retreating = a.path.length > 0;
    if (!a.retreating) delete game.state.armies[a.id];
  }
  for (const a of winArmies) if (game.state.armies[a.id] && a.size < (m.min_army ?? 50)) delete game.state.armies[a.id];
  game.notify('army');
}

function retreatTarget(game: Game, w: War, side: 'att' | 'def', from: string): string | undefined {
  const seen = new Set([from]);
  let frontier = [from];
  for (let depth = 0; depth < 8; depth++) {
    const next: string[] = [];
    for (const p of frontier) {
      for (const n of game.engine.neighbors(p)) {
        if (seen.has(n)) continue;
        seen.add(n);
        const ctrlSide = sideOf(game, w, provinceController(game, n)?.id);
        if (ctrlSide === side && !enemyArmiesInWar(game, w, side, n).length) return n;
        next.push(n);
      }
    }
    frontier = next;
  }
  return undefined;
}

function progressSieges(game: Game) {
  const m = mil(game);
  for (const a of Object.values(game.state.armies)) {
    if (a.path.length || a.retreating) continue;
    const p = game.state.provinces[a.location];
    if (!p) continue;
    const war = hostileWarAt(game, a, a.location) ?? liberationWarAt(game, a, a.location);
    if (!war) {
      if (p.siege?.army === a.id) p.siege = undefined;
      continue;
    }
    const side = participantSide(war, a.owner)!;
    if (enemyArmiesInWar(game, war, side, a.location).length) continue;
    if (p.siege && p.siege.army !== a.id && game.state.armies[p.siege.army]) continue;
    if (!p.siege) p.siege = { army: a.id, progress: 0 };
    const fort = Math.max(1, provinceFort(game, a.location));
    const liberation = !!p.occupant && participantSide(war, p.occupant) !== side;
    const daily =
      ((a.size / (fort * (m.siege_per_fort ?? 800) + (m.siege_base ?? 400))) * (m.siege_speed ?? 3) * (liberation ? 2 : 1)) +
      0;
    p.siege.progress += Math.min(m.siege_max_daily ?? 12, daily);
    if (p.siege.progress >= 100) {
      p.siege = undefined;
      if (liberation && sideOf(game, war, game.state.titles[a.location]?.holder) === side) {
        p.occupant = undefined;
        p.occupantWar = undefined;
      } else {
        p.occupant = a.owner;
        p.occupantWar = war.id;
      }
      game.message(
        game.loc.t('msg.siege_won', { place: game.nameOf('provinces', a.location), who: game.scopeName({ type: 'character', id: a.owner }) }),
        'war',
        { type: 'province', id: a.location },
        [...war.attackers, ...war.defenders],
      );
      game.emit('siege.won', { war, army: a, province: a.location });
      game.notify('map');
    }
  }
}

export function provinceFort(game: Game, provId: string): number {
  const def = game.content.get('provinces', provId);
  let fort = 0;
  for (const h of def?.holdings ?? []) fort = Math.max(fort, game.content.get('holdings', h)?.fort ?? 0);
  for (const b of game.state.provinces[provId]?.buildings ?? []) fort += game.content.get('buildings', b)?.modifiers?.fort ?? 0;
  return fort;
}

/** Ежемесячно: восстановление ополчений. */
export function regenLevies(game: Game) {
  const r = mil(game).levy_regen ?? 0.05;
  const raised = new Set(Object.values(game.state.armies).map((a) => a.owner));
  for (const c of game.rulers()) if (!raised.has(c.id) && c.levyRatio < 1) c.levyRatio = Math.min(1, c.levyRatio + r);
}
