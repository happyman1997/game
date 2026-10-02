/**
 * Фракции вассалов. Недовольные вассалы объединяются против сюзерена
 * (за независимость, за претендента на трон). Когда сила фракции
 * превышает порог, растёт недовольство; на 100% фракция предъявляет
 * ультиматум: сюзерен либо выполняет требования, либо получает мятеж —
 * войну, в которой все члены фракции выступают вместе.
 *
 * Данные:
 *   factions: { icon, cb, claimant, can_join, ai_join, ai_accept_demands,
 *               on_demands_accepted, ultimatum_event }
 *   defines.factions: { power_threshold, discontent_gain, discontent_decay,
 *                       ai_join_chance, ai_create_threshold, ai_create_chance,
 *                       ai_leave_below, cooldown_years }
 * Скоупы: root — вассал (для can_join/ai_join) или лидер фракции (для
 * on_demands_accepted), scope:liege, scope:faction, scope:faction_leader,
 * scope:claimant.
 */
import type { TextValue } from '../core/localization';
import type { Engine } from '../engine';
import type { Game } from '../game';
import { type ScriptContext, makeContext } from '../script/context';
import { evalTrigger, evalValue, resolveScope, runEffect } from '../script/interpreter';
import type { Character, Faction, ScopeRef } from '../types';
import { isAdult, isAlive } from '../world/characters';
import { realmLevy } from '../world/economy';
import { domainCounties, primaryTier, realmCounties, transferTitle } from '../world/titles';
import { setLiege } from '../world/characters';
import { declareWar, isAtWar, isAtWarWith } from '../world/war';
import type { EngineFeature } from './feature';

export interface FactionDef {
  id: string;
  name?: TextValue;
  icon?: string;
  /** Повод к войне для мятежа (casus_belli с manual: yes). */
  cb: string;
  /** Фракции нужен претендент с претензией на основной титул сюзерена. */
  claimant?: boolean;
  can_join?: unknown;
  ai_join?: unknown;
  ai_accept_demands?: unknown;
  on_demands_accepted?: unknown;
  /** Событие для сюзерена-игрока при ультиматуме. */
  ultimatum_event?: string;
}

function defs(game: Game) {
  return game.defines.factions ?? {};
}

const fref = (f: Faction): ScopeRef => ({ type: 'faction', id: f.id });

export function factionsAgainst(game: Game, liegeId: string): Faction[] {
  return Object.values(game.state.factions).filter((f) => f.target === liegeId);
}

export function factionOf(game: Game, c: Character): Faction | undefined {
  return Object.values(game.state.factions).find((f) => f.members.includes(c.id));
}

export function factionContext(game: Game, root: Character, liege: Character, f?: Faction, claimant?: string): ScriptContext {
  const scopes: Record<string, ScopeRef> = {
    liege: { type: 'character', id: liege.id },
    vassal: { type: 'character', id: root.id },
  };
  if (f) {
    scopes.faction = fref(f);
    scopes.faction_leader = { type: 'character', id: f.leader };
  }
  const cl = claimant ?? f?.claimant;
  if (cl) scopes.claimant = { type: 'character', id: cl };
  return makeContext(game, { type: 'character', id: root.id }, scopes);
}

/** Кандидаты в претенденты: у кого есть претензия на основной титул сюзерена. */
export function claimantCandidates(game: Game, liege: Character): Character[] {
  const t = liege.titles[0];
  if (!t) return [];
  return game.living().filter((c) => c.id !== liege.id && c.claims.includes(t) && isAdult(game, c) && !c.prison && !game.isPlayer(c.id));
}

function bestClaimant(game: Game, liege: Character, vassal: Character): string | undefined {
  const cands = claimantCandidates(game, liege);
  if (cands.some((c) => c.id === vassal.id)) return vassal.id;
  return cands.sort((a, b) => b.titles.length - a.titles.length || b.prestige - a.prestige)[0]?.id;
}

export function canJoinFaction(game: Game, c: Character, def: FactionDef, liege: Character, claimant?: string): boolean {
  if (!isAlive(c) || c.liege !== liege.id || !c.titles.length || c.prison) return false;
  const cd = c.flags.faction_cooldown;
  if (cd !== undefined && cd > game.date) return false;
  if (def.claimant && !claimant) return false;
  if (claimant === c.id && def.claimant) {
    // претендент сам может вести фракцию
  }
  const ctx = factionContext(game, c, liege, undefined, claimant);
  return evalTrigger(ctx, ctx.root, def.can_join);
}

export function aiJoinScore(game: Game, c: Character, def: FactionDef, liege: Character, f?: Faction, claimant?: string): number {
  const ctx = factionContext(game, c, liege, f, claimant);
  return def.ai_join != null ? evalValue(ctx, ctx.root, def.ai_join) : 0;
}

/** Сила фракции в процентах от силы сюзерена (без её членов). */
export function factionPower(game: Game, f: Faction): number {
  const liege = game.char(f.target);
  if (!liege) return 0;
  const share = game.defines.economy?.vassal_levy_share ?? 0.35;
  let members = 0;
  for (const id of f.members) {
    const m = game.char(id);
    if (m) members += realmLevy(game, m);
  }
  const liegeStr = Math.max(1, realmLevy(game, liege) - members * share);
  return Math.round((members / liegeStr) * 100);
}

export function createFaction(game: Game, type: string, founder: Character, claimant?: string): Faction | null {
  const def = game.content.get<FactionDef>('factions', type);
  const liege = game.char(founder.liege);
  if (!def || !liege || factionOf(game, founder)) return null;
  if (def.claimant) claimant ??= bestClaimant(game, liege, founder);
  if (!canJoinFaction(game, founder, def, liege, claimant)) return null;
  if (factionsAgainst(game, liege.id).some((f) => f.type === type)) return null;
  const f: Faction = { id: game.newId('fac'), type, target: liege.id, leader: founder.id, members: [founder.id], claimant, discontent: 0, created: game.date };
  game.state.factions[f.id] = f;
  game.emit('faction.created', { faction: f });
  game.message(
    game.loc.t('msg.faction_created', { faction: game.nameOf('factions', type), who: game.scopeName({ type: 'character', id: founder.id }), liege: game.scopeName({ type: 'character', id: liege.id }) }),
    'bad',
    { type: 'character', id: founder.id },
    [liege.id, founder.id],
  );
  return f;
}

export function joinFaction(game: Game, c: Character, f: Faction): boolean {
  const def = game.content.get<FactionDef>('factions', f.type);
  const liege = game.char(f.target);
  if (!def || !liege || factionOf(game, c) || !canJoinFaction(game, c, def, liege, f.claimant)) return false;
  f.members.push(c.id);
  updateLeader(game, f);
  game.emit('faction.joined', { faction: f, character: c });
  return true;
}

export function leaveFaction(game: Game, c: Character): void {
  const f = factionOf(game, c);
  if (!f) return;
  f.members = f.members.filter((x) => x !== c.id);
  if (!f.members.length) delete game.state.factions[f.id];
  else updateLeader(game, f);
  game.emit('faction.left', { faction: f, character: c });
}

function updateLeader(game: Game, f: Faction) {
  // Лидер — претендент, если он член фракции, иначе самый сильный член.
  if (f.claimant && f.members.includes(f.claimant)) {
    f.leader = f.claimant;
    return;
  }
  let best: { id: string; v: number } | undefined;
  for (const id of f.members) {
    const m = game.char(id);
    if (!m) continue;
    const v = realmLevy(game, m) + (game.isPlayer(id) ? 1e6 : 0) * 0;
    if (!best || v > best.v) best = { id, v };
  }
  if (best) f.leader = best.id;
}

export function dissolveFaction(game: Game, f: Faction, cooldown = true): void {
  if (!game.state.factions[f.id]) return;
  delete game.state.factions[f.id];
  if (cooldown) {
    const until = game.date + Math.round((defs(game).cooldown_years ?? 5) * 365);
    for (const id of f.members) {
      const m = game.char(id);
      if (m) m.flags.faction_cooldown = until;
    }
  }
  game.emit('faction.dissolved', { faction: f });
}

/** Требования выполнены без войны. */
export function enforceDemands(game: Game, f: Faction): void {
  const def = game.content.get<FactionDef>('factions', f.type);
  const leader = game.char(f.leader);
  const liege = game.char(f.target);
  if (!def || !leader || !liege) return;
  const ctx = factionContext(game, leader, liege, f);
  game.emit('faction.ultimatum', { faction: f, accepted: true });
  game.message(game.loc.t('msg.faction_demands_accepted', { faction: game.nameOf('factions', f.type), liege: game.scopeName({ type: 'character', id: liege.id }) }), 'war', undefined, [liege.id, ...f.members]);
  runEffect(ctx, ctx.root, def.on_demands_accepted);
  dissolveFaction(game, f);
  game.markDirty();
}

/** Ультиматум отвергнут — мятеж. */
export function factionRevolt(game: Game, f: Faction): boolean {
  const def = game.content.get<FactionDef>('factions', f.type);
  const leader = game.char(f.leader);
  const liege = game.char(f.target);
  if (!def || !leader || !liege) return false;
  game.emit('faction.ultimatum', { faction: f, accepted: false });
  const members = f.members.filter((id) => game.isAlive(id) && game.char(id)!.liege === liege.id && !game.char(id)!.prison);
  if (!members.includes(leader.id)) return false;
  const counties = def.claimant ? domainCounties(game, liege) : members.flatMap((id) => realmCounties(game, game.char(id)!));
  const scopes: Record<string, ScopeRef> = { faction_leader: { type: 'character', id: leader.id } };
  if (f.claimant && game.isAlive(f.claimant)) scopes.claimant = { type: 'character', id: f.claimant };
  // Претендент-придворный идёт в войну вместе с лидером (без земель он не участник).
  const w = declareWar(game, leader, { cb: def.cb, defender: liege.id, title: liege.titles[0], counties }, {
    free: true,
    attackers: members,
    scopes,
    faction: f.id,
  });
  if (!w) return false;
  f.ultimatum = false;
  return true;
}

function issueUltimatum(game: Game, f: Faction) {
  const def = game.content.get<FactionDef>('factions', f.type)!;
  const liege = game.char(f.target)!;
  const leader = game.char(f.leader)!;
  if (game.isPlayer(liege.id)) {
    if (f.ultimatum) return;
    f.ultimatum = true;
    const ev = def.ultimatum_event ?? defs(game).ultimatum_event ?? 'faction.0001';
    if (game.content.get('events', ev)) {
      game.events.fire(ev, { type: 'character', id: liege.id }, {
        faction: fref(f),
        faction_leader: { type: 'character', id: leader.id },
        ...(f.claimant ? { claimant: { type: 'character', id: f.claimant } } : {}),
      });
    } else factionRevolt(game, f);
    return;
  }
  const ctx = factionContext(game, liege, liege, f);
  const accept = def.ai_accept_demands != null ? evalValue(ctx, ctx.root, def.ai_accept_demands) : -1;
  if (accept > 0) enforceDemands(game, f);
  else factionRevolt(game, f);
}

export function monthlyFactions(game: Game): void {
  const d = defs(game);
  // 1. чистка
  for (const f of Object.values(game.state.factions)) {
    const liege = game.char(f.target);
    if (!isAlive(liege) || !liege.titles.length) {
      dissolveFaction(game, f, false);
      continue;
    }
    if (Object.values(game.state.wars).some((w) => w.faction === f.id)) continue;
    f.members = f.members.filter((id) => {
      const m = game.char(id);
      return isAlive(m) && m.liege === f.target && m.titles.length > 0;
    });
    if (f.claimant && (!game.isAlive(f.claimant) || !game.char(f.claimant)!.claims.includes(liege.titles[0] ?? ''))) {
      dissolveFaction(game, f, false);
      continue;
    }
    if (!f.members.length) {
      dissolveFaction(game, f, false);
      continue;
    }
    if (!f.members.includes(f.leader)) updateLeader(game, f);
  }

  // 2. ИИ-вассалы вступают, создают и покидают фракции
  const types = game.content.all<FactionDef>('factions');
  if (types.length) {
    for (const v of game.rulers()) {
      if (!v.liege || game.isPlayer(v.id) || v.prison || v.death !== undefined) continue;
      const liege = game.char(v.liege);
      if (!liege || !isAlive(liege)) continue;
      if (isAtWarWith(game, v.id, liege.id)) continue;
      const cur = factionOf(game, v);
      if (cur) {
        if (cur.leader !== v.id || cur.members.length > 1) {
          const def = game.content.get<FactionDef>('factions', cur.type);
          if (def && aiJoinScore(game, v, def, liege, cur) < (d.ai_leave_below ?? -10) && game.rng.chance(0.3)) leaveFaction(game, v);
        }
        continue;
      }
      if (!game.rng.chance(d.ai_consider_chance ?? 0.35)) continue;
      const existing = factionsAgainst(game, liege.id);
      for (const def of types) {
        const f = existing.find((x) => x.type === def.id);
        const claimant = f?.claimant ?? (def.claimant ? bestClaimant(game, liege, v) : undefined);
        if (!canJoinFaction(game, v, def, liege, claimant)) continue;
        const score = aiJoinScore(game, v, def, liege, f, claimant);
        if (f) {
          if (score > 0 && game.rng.chance(d.ai_join_chance ?? 0.5)) {
            joinFaction(game, v, f);
            break;
          }
        } else if (score > (d.ai_create_threshold ?? 20) && game.rng.chance(d.ai_create_chance ?? 0.25)) {
          createFaction(game, def.id, v, claimant);
          break;
        }
      }
    }
  }

  // 3. недовольство и ультиматумы
  for (const f of Object.values(game.state.factions)) {
    if (Object.values(game.state.wars).some((w) => w.faction === f.id)) continue;
    const liege = game.char(f.target);
    if (!liege || isAtWar(game, liege.id) && Object.values(game.state.wars).some((w) => w.defenders.includes(liege.id) && w.faction)) continue;
    const power = factionPower(game, f);
    if (power >= (d.power_threshold ?? 80)) f.discontent = Math.min(100, f.discontent + (d.discontent_gain ?? 6));
    else f.discontent = Math.max(0, f.discontent - (d.discontent_decay ?? 4));
    if (f.discontent >= 100) {
      if (game.isPlayer(f.leader)) {
        if (!f.ultimatum) {
          f.ultimatum = true;
          game.message(game.loc.t('msg.faction_ready'), 'war');
        }
        continue;
      }
      if (game.isAlive(f.leader) && !game.char(f.leader)!.prison) issueUltimatum(game, f);
    }
  }
}

/**
 * Претендент забирает основной титул проигравшего: получает его (и столичное
 * графство, если своих земель нет), прежний владелец становится вассалом,
 * вассалы его ранга и выше переходят к победителю.
 */
export function seizePrimaryTitle(game: Game, winner: Character, loser: Character): void {
  const t = loser.titles[0];
  if (!t || winner.id === loser.id) return;
  const vassals = game.vassalsOf(loser.id);
  const loserLiege = loser.liege;
  transferTitle(game, t, winner.id, { court: winner.id });
  if (!domainCounties(game, winner).length) {
    const cap = (loser.capital && loser.titles.includes(loser.capital) ? loser.capital : undefined) ?? domainCounties(game, loser)[0];
    if (cap) transferTitle(game, cap, winner.id, { court: winner.id });
  }
  if (winner.liege === loser.id || winner.liege === winner.id) setLiege(game, winner, loserLiege !== winner.id ? loserLiege : undefined);
  if (loser.death === undefined && loser.titles.length) setLiege(game, loser, winner.id);
  for (const v of vassals) {
    if (!isAlive(v) || v.id === winner.id || v.liege !== loser.id) continue;
    if (primaryTier(game, v) >= primaryTier(game, loser)) setLiege(game, v, winner.id);
  }
  game.markDirty();
}

/** Игрок-лидер предъявляет ультиматум. */
export function playerUltimatum(game: Game, f: Faction): void {
  if (f.discontent < 100) return;
  f.ultimatum = false;
  issueUltimatum(game, f);
}

export const factionsFeature: EngineFeature = {
  id: 'factions',
  doc: 'Фракции вассалов: независимость, претендент; ультиматумы и мятежи',
  install(engine: Engine) {
    engine.systems.register('factions', { id: 'factions', order: 58, onMonth: monthlyFactions }, 'core/factions');

    // Поставщик целей для мятежей: в обычных объявлениях войны не участвует.
    engine.registries.cbTargets.register('faction', { targets: () => [] }, 'core/factions');

    // Конец войны фракции — фракция распадается.
    engine.hooks.on('war.ended', ({ game, war }) => {
      if (!war.faction) return;
      const f = game.state.factions[war.faction];
      if (f) dissolveFaction(game, f);
    }, { owner: 'core/factions' });

    // Дети, не унаследовавшие основной титул родителя, получают на него претензию — будущие претенденты.
    engine.hooks.on('succession', ({ game, deceased, primary }) => {
      const t = game.char(primary)?.titles[0];
      if (!t || game.state.titles[t]?.holder !== primary) return;
      if (!deceased.children.includes(primary) && !deceased.spouses.includes(primary)) return;
      for (const id of deceased.children) {
        const ch = game.char(id);
        if (!ch || ch.id === primary || !isAlive(ch) || ch.claims.includes(t)) continue;
        if (game.rng.chance(defs(game).sibling_claim_chance ?? 0.5)) ch.claims.push(t);
      }
    }, { owner: 'core/factions' });

  },
  script(engine: Engine) {
    const { triggers, effects, values, links, lists } = engine.script;
    const ch = (ctx: ScriptContext, s: ScopeRef | null | undefined) => (s?.type === 'character' ? ctx.game.char(s.id) : undefined);
    const fac = (ctx: ScriptContext, s: ScopeRef | null | undefined) => (s?.type === 'faction' ? ctx.game.state.factions[s.id] : undefined);
    triggers.register('is_in_faction', {
      scopes: ['character'],
      doc: 'Состоит во фракции (yes/no или тип)',
      eval: (ctx, s, arg) => {
        const c = ch(ctx, s);
        const f = c ? factionOf(ctx.game, c) : undefined;
        if (arg === 'no' || arg === false) return !f;
        return !!f && (arg === 'yes' || arg === true || arg == null || f.type === arg);
      },
      describe: (ctx, _s, arg) => ctx.game.loc.t(arg === 'no' || arg === false ? 'tr.is_in_faction.not' : 'tr.is_in_faction'),
    }, 'core/factions');
    triggers.register('is_faction_leader', {
      scopes: ['character'],
      doc: 'Возглавляет фракцию',
      eval: (ctx, s, arg) => !!Object.values(ctx.game.state.factions).find((f) => f.leader === s.id) === (arg == null || arg === 'yes' || arg === true),
    }, 'core/factions');
    triggers.register('faction_type', { scopes: ['faction'], doc: 'Тип фракции', eval: (ctx, s, arg) => fac(ctx, s)?.type === arg }, 'core/factions');
    values.register('faction_power', { scopes: ['faction'], doc: 'Сила фракции в % от силы сюзерена', get: (ctx, s) => { const f = fac(ctx, s); return f ? factionPower(ctx.game, f) : 0; } }, 'core/factions');
    values.register('faction_discontent', { scopes: ['faction'], doc: 'Недовольство фракции (0–100)', get: (ctx, s) => fac(ctx, s)?.discontent ?? 0 }, 'core/factions');
    values.register('num_faction_members', { scopes: ['faction'], doc: 'Число членов фракции', get: (ctx, s) => fac(ctx, s)?.members.length ?? 0 }, 'core/factions');
    links.register('faction_leader', { from: ['faction'], doc: 'Лидер фракции', resolve: (ctx, s) => { const f = fac(ctx, s); return f ? { type: 'character', id: f.leader } : null; } }, 'core/factions');
    links.register('faction_target', { from: ['faction'], doc: 'Сюзерен, против которого фракция', resolve: (ctx, s) => { const f = fac(ctx, s); return f ? { type: 'character', id: f.target } : null; } }, 'core/factions');
    links.register('faction_claimant', { from: ['faction'], doc: 'Претендент фракции', resolve: (ctx, s) => { const f = fac(ctx, s); return f?.claimant ? { type: 'character', id: f.claimant } : null; } }, 'core/factions');
    links.register('joined_faction', { from: ['character'], doc: 'Фракция, в которой состоит персонаж', resolve: (ctx, s) => { const c = ch(ctx, s); const f = c ? factionOf(ctx.game, c) : undefined; return f ? fref(f) : null; } }, 'core/factions');
    lists.register('faction_member', { from: ['faction'], doc: 'Члены фракции', list: (ctx, s) => (fac(ctx, s)?.members ?? []).map((id) => ({ type: 'character' as const, id })) }, 'core/factions');
    lists.register('faction_against', { from: ['character'], doc: 'Фракции против персонажа', list: (ctx, s) => factionsAgainst(ctx.game, s.id).map(fref) }, 'core/factions');
    lists.register('war_attacker', { from: ['war'], doc: 'Участники войны на стороне нападения', list: (ctx, s) => (ctx.game.state.wars[s.id]?.attackers ?? []).filter((id) => ctx.game.isAlive(id)).map((id) => ({ type: 'character' as const, id })) }, 'core/factions');
    lists.register('war_defender', { from: ['war'], doc: 'Участники войны на стороне защиты', list: (ctx, s) => (ctx.game.state.wars[s.id]?.defenders ?? []).filter((id) => ctx.game.isAlive(id)).map((id) => ({ type: 'character' as const, id })) }, 'core/factions');
    effects.register('faction_enforce_demands', {
      scopes: ['faction'],
      doc: 'Сюзерен выполняет требования фракции',
      apply: (ctx, s) => { const f = fac(ctx, s); if (f) enforceDemands(ctx.game, f); },
      describe: (ctx, s) => { const f = fac(ctx, s); return f ? ctx.game.loc.t('fx.faction_enforce_demands', { faction: ctx.game.nameOf('factions', f.type) }) : null; },
    }, 'core/factions');
    effects.register('faction_start_war', {
      scopes: ['faction'],
      doc: 'Фракция поднимает мятеж',
      apply: (ctx, s) => { const f = fac(ctx, s); if (f) factionRevolt(ctx.game, f); },
      describe: (ctx, s) => { const f = fac(ctx, s); return f ? ctx.game.loc.t('fx.faction_start_war', { faction: ctx.game.nameOf('factions', f.type) }) : null; },
    }, 'core/factions');
    effects.register('join_faction', {
      scopes: ['character'],
      doc: 'Вступить во фракцию против сюзерена (или создать): join_faction: <тип>',
      apply: (ctx, s, arg) => {
        const c = ch(ctx, s);
        if (!c?.liege) return;
        const f = factionsAgainst(ctx.game, c.liege).find((x) => x.type === arg);
        if (f) joinFaction(ctx.game, c, f);
        else createFaction(ctx.game, String(arg), c);
      },
    }, 'core/factions');
    effects.register('seize_primary_title', {
      scopes: ['character'],
      doc: 'Забрать основной титул персонажа (претендент): прежний владелец становится вассалом',
      apply: (ctx, s, arg) => {
        const c = ch(ctx, s);
        const o = ch(ctx, resolveScope(ctx, s, arg));
        if (c && o) seizePrimaryTitle(ctx.game, c, o);
      },
      describe: (ctx, s, arg) => {
        const o = ch(ctx, resolveScope(ctx, s, arg));
        return o?.titles[0] ? ctx.game.loc.t('fx.gain_title', { who: ctx.game.scopeName(s), value: ctx.game.scopeName({ type: 'title', id: o.titles[0] }) }) : null;
      },
    }, 'core/factions');
    effects.register('leave_faction', { scopes: ['character'], doc: 'Выйти из фракции', apply: (ctx, s) => { const c = ch(ctx, s); if (c) leaveFaction(ctx.game, c); } }, 'core/factions');
    effects.register('add_faction_discontent', {
      scopes: ['faction'],
      doc: 'Изменить недовольство фракции',
      apply: (ctx, s, arg) => { const f = fac(ctx, s); if (f) f.discontent = Math.max(0, Math.min(100, f.discontent + evalValue(ctx, s, arg))); },
    }, 'core/factions');

    engine.registries.contentValidators.register('factions', (e, v) => {
      for (const f of e.content.all<FactionDef>('factions')) {
        const w = `factions/${f.id}`;
        v.ref('casus_belli', f.cb, w);
        if (f.ultimatum_event) v.ref('events', f.ultimatum_event, w);
        v.trigger(f.can_join, `${w} can_join`);
        v.effect(f.on_demands_accepted, `${w} on_demands_accepted`);
      }
    }, 'core/factions');
  },
};
