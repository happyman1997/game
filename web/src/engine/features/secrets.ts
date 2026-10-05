/**
 * Секреты. Персонажи совершают постыдное (убийство, измена, казнокрадство),
 * и это становится секретом. Секрет могут узнать другие — тайный советник,
 * родня, случайные свидетели. Знающий может шантажировать владельца секрета
 * (получить крюк) или разоблачить его (эффект on_expose, секрет исчезает).
 *
 * Данные:
 *   secret_types: { icon, hook: strong|weak, severity, discovered_by, discovery_chance, on_expose }
 *     discovered_by — список (spouse, close_family, liege…), чьи члены могут
 *     случайно узнать секрет; discovery_chance — шанс в месяц (в %).
 *     on_expose: root — владелец, scope:exposer, scope:secret_target.
 *   defines.secrets: { max_known_per_secret }
 */
import type { TextValue } from '../core/localization';
import type { Engine } from '../engine';
import type { Game } from '../game';
import { type ScriptContext, makeContext } from '../script/context';
import { evalValue, resolveScope, runEffect } from '../script/interpreter';
import type { Character, ScopeRef, Secret } from '../types';
import { isAlive } from '../world/characters';
import { addHook } from '../world/hooks';
import { realmMembers, topLiege } from '../world/titles';
import { type EngineFeature, asList } from './feature';

export interface SecretTypeDef {
  id: string;
  name?: TextValue;
  icon?: string;
  hook?: 'strong' | 'weak';
  severity?: number;
  discovered_by?: string | string[];
  discovery_chance?: unknown;
  on_expose?: unknown;
}

function defs(game: Game) {
  return game.defines.secrets ?? {};
}

export function secretsOf(c: Character): Secret[] {
  return c.secrets ?? [];
}

export function knownSecretsOf(game: Game, owner: Character, knower: string): Secret[] {
  return secretsOf(owner).filter((s) => s.known.includes(knower));
}

export function addSecret(game: Game, owner: Character, type: string, target?: string, knownBy: string[] = []): Secret | null {
  if (!game.content.get('secret_types', type)) {
    game.scriptError(`Нет типа секрета "${type}"`);
    return null;
  }
  const dup = secretsOf(owner).find((s) => s.type === type && s.target === target);
  if (dup) {
    for (const k of knownBy) if (!dup.known.includes(k) && k !== owner.id) dup.known.push(k);
    return dup;
  }
  const s: Secret = { id: game.newId('sec'), type, target, known: knownBy.filter((k) => k !== owner.id), since: game.date };
  (owner.secrets ??= []).push(s);
  game.emit('secret.added', { owner, secret: s });
  return s;
}

/** Персонаж узнаёт секрет. */
export function learnSecret(game: Game, knower: Character, owner: Character, s: Secret): boolean {
  if (knower.id === owner.id || s.known.includes(knower.id)) return false;
  s.known.push(knower.id);
  const max = defs(game).max_known_per_secret ?? 12;
  if (s.known.length > max) s.known = s.known.filter((id) => game.isAlive(id)).slice(-max);
  game.emit('secret.learned', { knower, owner, secret: s });
  if (game.isPlayer(knower.id)) {
    game.message(
      game.loc.t('msg.secret_learned', { who: game.scopeName({ type: 'character', id: owner.id }), secret: game.nameOf('secret_types', s.type) }),
      'good',
      { type: 'character', id: owner.id },
    );
  }
  if (game.isPlayer(owner.id)) {
    game.message(game.loc.t('msg.secret_known_by', { who: game.scopeName({ type: 'character', id: knower.id }), secret: game.nameOf('secret_types', s.type) }), 'bad', { type: 'character', id: knower.id });
  }
  return true;
}

function secretDef(game: Game, s: Secret) {
  return game.content.get<SecretTypeDef>('secret_types', s.type);
}

/** Самый тяжёлый секрет owner, известный knower. */
export function worstKnownSecret(game: Game, owner: Character, knower: string): Secret | undefined {
  return knownSecretsOf(game, owner, knower).sort((a, b) => (secretDef(game, b)?.severity ?? 0) - (secretDef(game, a)?.severity ?? 0))[0];
}

export function blackmail(game: Game, knower: Character, owner: Character, s?: Secret): boolean {
  const sec = s ?? worstKnownSecret(game, owner, knower.id);
  if (!sec) return false;
  const strong = secretDef(game, sec)?.hook === 'strong';
  addHook(game, knower, owner, { strong });
  game.emit('secret.blackmailed', { knower, owner, secret: sec });
  return true;
}

export function exposeSecret(game: Game, exposer: Character | undefined, owner: Character, s?: Secret): boolean {
  const sec = s ?? (exposer ? worstKnownSecret(game, owner, exposer.id) : secretsOf(owner)[0]);
  if (!sec) return false;
  owner.secrets = secretsOf(owner).filter((x) => x.id !== sec.id);
  const def = secretDef(game, sec);
  const scopes: Record<string, ScopeRef> = { secret_owner: { type: 'character', id: owner.id } };
  if (exposer) scopes.exposer = { type: 'character', id: exposer.id };
  if (sec.target && game.char(sec.target)) scopes.secret_target = { type: 'character', id: sec.target };
  const ctx = makeContext(game, { type: 'character', id: owner.id }, scopes);
  runEffect(ctx, ctx.root, def?.on_expose);
  game.message(
    game.loc.t('msg.secret_exposed', { who: game.scopeName({ type: 'character', id: owner.id }), secret: game.nameOf('secret_types', sec.type), by: exposer ? game.scopeName({ type: 'character', id: exposer.id }) : '—' }),
    'event',
    { type: 'character', id: owner.id },
    [owner.id, exposer?.id, owner.liege, sec.target],
  );
  game.emit('secret.exposed', { exposer, owner, secret: sec });
  return true;
}

/** Узнать случайный секрет кого-то из державы (или двора) персонажа. */
export function discoverSecret(game: Game, c: Character): boolean {
  const top = topLiege(game, c);
  const pool = new Set<Character>([...realmMembers(game, top), ...game.courtiersOf(c.id), ...game.vassalsOf(c.id)]);
  const cands: { owner: Character; s: Secret }[] = [];
  for (const o of pool) {
    if (o.id === c.id || !isAlive(o)) continue;
    for (const s of secretsOf(o)) if (!s.known.includes(c.id)) cands.push({ owner: o, s });
  }
  // и секреты придворных вассалов
  for (const o of game.living()) {
    if (o.titles.length || !o.secrets?.length || o.id === c.id || pool.has(o)) continue;
    const l = game.char(o.liege);
    if (l && pool.has(l)) for (const s of o.secrets) if (!s.known.includes(c.id)) cands.push({ owner: o, s });
  }
  const pick = game.rng.pick(cands);
  if (!pick) return false;
  return learnSecret(game, c, pick.owner, pick.s);
}

export function monthlySecrets(game: Game): void {
  for (const owner of game.living()) {
    if (!owner.secrets?.length) continue;
    for (const s of [...owner.secrets]) {
      // секреты об умерших сообщниках не исчезают, а знающие умирают
      s.known = s.known.filter((id) => game.isAlive(id));
      const def = secretDef(game, s);
      if (!def?.discovered_by) continue;
      const ctx = makeContext(game, { type: 'character', id: owner.id }, s.target ? { secret_target: { type: 'character', id: s.target } } : {});
      const chance = evalValue(ctx, ctx.root, def.discovery_chance ?? 1);
      if (game.rng.next() * 100 >= chance) continue;
      const lists = asList(def.discovered_by);
      const name = game.rng.pick(lists);
      const list = name ? game.engine.script.lists.get(name) : undefined;
      if (!list) continue;
      const who = game.rng.pick(list.list(ctx, ctx.root).filter((r) => r.type === 'character' && r.id !== owner.id && !s.known.includes(r.id)));
      const knower = game.char(who?.id);
      if (knower && isAlive(knower)) learnSecret(game, knower, owner, s);
    }
  }
}

export const secretsFeature: EngineFeature = {
  id: 'secrets',
  doc: 'Секреты: раскрытие, шантаж (крюки) и разоблачение',
  install(engine: Engine) {
    engine.systems.register('secrets', { id: 'secrets', order: 42, onMonth: monthlySecrets }, 'core/secrets');
  },
  script(engine: Engine) {
    const { triggers, effects, values, lists } = engine.script;
    const ch = (ctx: ScriptContext, s: ScopeRef | null | undefined) => (s?.type === 'character' ? ctx.game.char(s.id) : undefined);
    const target = (ctx: ScriptContext, s: ScopeRef, arg: unknown) => ch(ctx, resolveScope(ctx, s, arg));
    triggers.register('has_secret', {
      scopes: ['character'],
      doc: 'Есть секрет (yes или тип)',
      eval: (ctx, s, arg) => {
        const secs = secretsOf(ch(ctx, s) ?? ({} as Character));
        if (arg === 'no' || arg === false) return !secs.length;
        return arg === 'yes' || arg === true || arg == null ? secs.length > 0 : secs.some((x) => asList(arg).includes(x.type as any));
      },
    }, 'core/secrets');
    triggers.register('knows_secret_of', {
      scopes: ['character'],
      doc: 'Знает какой-то секрет персонажа',
      eval: (ctx, s, arg) => {
        const o = target(ctx, s, arg);
        return !!o && knownSecretsOf(ctx.game, o, s.id).length > 0;
      },
      describe: (ctx) => ctx.game.loc.t('tr.knows_secret_of'),
    }, 'core/secrets');
    values.register('num_secrets', { scopes: ['character'], doc: 'Число секретов персонажа', get: (ctx, s) => secretsOf(ch(ctx, s) ?? ({} as Character)).length }, 'core/secrets');
    values.register('num_known_secrets', {
      scopes: ['character'],
      doc: 'Сколько чужих секретов знает персонаж',
      get: (ctx, s) => ctx.game.living().reduce((n, o) => n + knownSecretsOf(ctx.game, o, s.id).length, 0),
    }, 'core/secrets');
    lists.register('known_secret_owner', {
      from: ['character'],
      doc: 'Персонажи, чьи секреты известны этому персонажу',
      list: (ctx, s) => ctx.game.living().filter((o) => knownSecretsOf(ctx.game, o, s.id).length).map((o) => ({ type: 'character' as const, id: o.id })),
    }, 'core/secrets');
    effects.register('add_secret', {
      scopes: ['character'],
      doc: 'Персонаж получает секрет: add_secret: тип или { type, target, known_by }',
      apply: (ctx, s, arg) => {
        const c = ch(ctx, s);
        if (!c) return;
        const type = typeof arg === 'string' ? arg : arg?.type;
        const t = arg?.target ? target(ctx, s, arg.target) : undefined;
        const known = asList(arg?.known_by).map((p) => target(ctx, s, p)?.id).filter((x): x is string => !!x);
        addSecret(ctx.game, c, String(type), t?.id, known);
      },
      describe: () => null,
    }, 'core/secrets');
    effects.register('discover_secret', {
      scopes: ['character'],
      doc: 'Узнать случайный секрет кого-то из своей державы',
      apply: (ctx, s) => { const c = ch(ctx, s); if (c) discoverSecret(ctx.game, c); },
      describe: (ctx) => ctx.game.loc.t('fx.discover_secret'),
    }, 'core/secrets');
    effects.register('blackmail', {
      scopes: ['character'],
      doc: 'Шантажировать персонажа его самым тяжёлым известным секретом (получить крюк)',
      apply: (ctx, s, arg) => { const c = ch(ctx, s); const o = target(ctx, s, arg); if (c && o) blackmail(ctx.game, c, o); },
      describe: (ctx, s, arg) => {
        const o = target(ctx, s, arg);
        const sec = o ? worstKnownSecret(ctx.game, o, s.id) : undefined;
        if (!o || !sec) return null;
        const strong = ctx.game.content.get<SecretTypeDef>('secret_types', sec.type)?.hook === 'strong';
        return ctx.game.loc.t(strong ? 'fx.add_strong_hook' : 'fx.add_hook', { value: ctx.game.scopeName({ type: 'character', id: o.id }) });
      },
    }, 'core/secrets');
    effects.register('expose_secret', {
      scopes: ['character'],
      doc: 'Разоблачить самый тяжёлый известный секрет персонажа',
      apply: (ctx, s, arg) => { const c = ch(ctx, s); const o = target(ctx, s, arg); if (c && o) exposeSecret(ctx.game, c, o); },
      describe: (ctx, s, arg) => {
        const o = target(ctx, s, arg);
        const sec = o ? worstKnownSecret(ctx.game, o, s.id) : undefined;
        return o && sec ? ctx.game.loc.t('fx.expose_secret', { who: ctx.game.scopeName({ type: 'character', id: o.id }), secret: ctx.game.nameOf('secret_types', sec.type) }) : null;
      },
    }, 'core/secrets');

    engine.registries.contentValidators.register('secrets', (e, v) => {
      for (const d of e.content.all<SecretTypeDef>('secret_types')) {
        for (const l of asList(d.discovered_by)) if (!e.script.lists.has(l)) v.issue(`secret_types/${d.id}: нет списка "${l}"`);
        v.effect(d.on_expose, `secret_types/${d.id} on_expose`);
      }
    }, 'core/secrets');
  },
};
