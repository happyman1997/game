/**
 * Интерпретатор скриптового языка данных.
 *
 * Триггер — словарь условий (все должны выполняться):
 *   { is_adult: yes, gold: ">= 100", liege: { has_trait: brave }, OR: [...] }
 * Эффект — словарь или список команд:
 *   [ { add_gold: 50 }, { if: { limit: {...}, then: {...}, else: {...} } } ]
 * Значение — число, путь ("scope:actor.diplomacy") или объект
 *   { value: 10, add: [...], multiply: 2, if: { limit: ..., add: 5 }, min: 0 }
 */
import { durationDays } from '../core/date';
import { isPlainObject } from '../core/merge';
import type { ScopeRef } from '../types';
import { type ScriptContext, isYes, sameScope } from './context';

const MAX_DEPTH = 60;

/** Тело именованного блока (scripted_trigger/effect/script_value): поле field или вся запись без id. */
export function bodyOf(def: any, field: string): unknown {
  if (!isPlainObject(def)) return def;
  if (field in def) return def[field];
  const { id: _id, desc: _d, ...rest } = def;
  return rest;
}

// ---------------------------------------------------------------- пути

/** Разбивает "scope:a.liege.opinion(scope:b.father)" по точкам вне скобок. */
export function splitPath(path: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let cur = '';
  for (const c of path) {
    if (c === '(') depth++;
    if (c === ')') depth--;
    if (c === '.' && depth === 0) {
      out.push(cur);
      cur = '';
    } else cur += c;
  }
  out.push(cur);
  return out.map((s) => s.trim()).filter(Boolean);
}

const PREFIXED: Record<string, ScopeRef['type']> = {
  'character:': 'character',
  'title:': 'title',
  'province:': 'province',
  'dynasty:': 'dynasty',
  'war:': 'war',
  'scheme:': 'scheme',
};

function stepScope(ctx: ScriptContext, cur: ScopeRef | null | undefined, seg: string, first: boolean): ScopeRef | null {
  const game = ctx.game;
  if (seg === 'root') return ctx.root;
  if (seg === 'this') return cur ?? null;
  if (seg === 'prev') return ctx.prev ?? null;
  if (seg.startsWith('scope:')) return ctx.scopes[seg.slice(6)] ?? null;
  for (const [p, type] of Object.entries(PREFIXED)) {
    if (seg.startsWith(p)) {
      const id = seg.slice(p.length);
      return game.exists({ type, id }) ? { type, id } : null;
    }
  }
  const link = game.engine.script.links.get(seg);
  if (link) {
    if (!cur) return null;
    if (link.from && !link.from.includes(cur.type)) return null;
    return link.resolve(ctx, cur) ?? null;
  }
  if (first && game.state.titles[seg]) return { type: 'title', id: seg };
  if (first && game.state.characters[seg]) return { type: 'character', id: seg };
  return null;
}

function isScopeStart(ctx: ScriptContext, seg: string): boolean {
  return (
    seg === 'root' ||
    seg === 'this' ||
    seg === 'prev' ||
    seg.startsWith('scope:') ||
    Object.keys(PREFIXED).some((p) => seg.startsWith(p)) ||
    ctx.game.engine.script.links.has(seg)
  );
}

/** Разрешает путь к скоупу: "scope:actor.liege", "root.primary_title", "title:k_england". */
export function resolveScope(ctx: ScriptContext, scope: ScopeRef | null | undefined, path: unknown): ScopeRef | null {
  if (path == null) return null;
  if (isPlainObject(path) && typeof (path as any).type === 'string' && typeof (path as any).id === 'string') {
    return path as unknown as ScopeRef;
  }
  if (typeof path !== 'string') return null;
  const segs = splitPath(path);
  let cur: ScopeRef | null = scope ?? null;
  for (let i = 0; i < segs.length; i++) {
    cur = stepScope(ctx, cur, segs[i], i === 0);
    if (!cur) return null;
  }
  return cur;
}

// ---------------------------------------------------------------- значения

const CMP_RE = /^\s*(>=|<=|==|!=|>|<|=)\s*(.+)$/;

export function evalValue(ctx: ScriptContext, scope: ScopeRef, expr: unknown, parts?: { label: string; value: number }[]): number {
  if (expr == null) return 0;
  if (typeof expr === 'number') return expr;
  if (typeof expr === 'boolean') return expr ? 1 : 0;
  if (typeof expr === 'string') return evalValuePath(ctx, scope, expr);
  if (Array.isArray(expr)) return expr.reduce((s, e) => s + evalValue(ctx, scope, e), 0);
  if (isPlainObject(expr)) return applyValueOps(ctx, scope, 0, expr, parts);
  return 0;
}

function applyValueOps(
  ctx: ScriptContext,
  scope: ScopeRef,
  start: number,
  ops: Record<string, any>,
  parts?: { label: string; value: number }[],
): number {
  let v = start;
  const game = ctx.game;
  for (const [k, arg] of Object.entries(ops)) {
    switch (k) {
      case 'value':
      case 'base':
        v = evalValue(ctx, scope, arg);
        if (parts && ops.desc == null && v !== 0) parts.push({ label: game.text(ops.base_desc ?? 'ui.base_value'), value: v });
        break;
      case 'add':
      case 'subtract': {
        const items = Array.isArray(arg) ? arg : [arg];
        for (const it of items) {
          let x: number;
          if (isPlainObject(it) && ('limit' in it || 'trigger' in it)) {
            if (!evalTrigger(ctx, scope, it.limit ?? it.trigger)) continue;
            x = evalValue(ctx, scope, it.value ?? 0);
          } else x = evalValue(ctx, scope, isPlainObject(it) && 'value' in it && 'desc' in it ? it.value : it);
          if (k === 'subtract') x = -x;
          v += x;
          if (parts && isPlainObject(it) && it.desc != null && x !== 0) parts.push({ label: game.text(it.desc), value: x });
        }
        break;
      }
      case 'multiply':
        v *= evalValue(ctx, scope, arg);
        break;
      case 'divide': {
        const d = evalValue(ctx, scope, arg);
        v = d === 0 ? 0 : v / d;
        break;
      }
      case 'min':
        v = Math.max(v, evalValue(ctx, scope, arg));
        break;
      case 'max':
        v = Math.min(v, evalValue(ctx, scope, arg));
        break;
      case 'round':
        if (isYes(arg)) v = Math.round(v);
        break;
      case 'floor':
        if (isYes(arg)) v = Math.floor(v);
        break;
      case 'ceil':
        if (isYes(arg)) v = Math.ceil(v);
        break;
      case 'abs':
        if (isYes(arg)) v = Math.abs(v);
        break;
      case 'if': {
        const blocks = Array.isArray(arg) ? arg : [arg];
        for (const b of blocks) {
          if (!isPlainObject(b)) continue;
          if (!evalTrigger(ctx, scope, b.limit)) continue;
          const { limit: _l, desc, ...rest } = b;
          const before = v;
          v = applyValueOps(ctx, scope, v, rest);
          if (parts && desc != null && v !== before) parts.push({ label: game.text(desc), value: v - before });
        }
        break;
      }
      case 'desc':
      case 'base_desc':
        break;
      default:
        game.scriptError(`Неизвестная операция значения "${k}"`);
    }
  }
  return v;
}

function evalValuePath(ctx: ScriptContext, scope: ScopeRef, s: string): number {
  const trimmed = s.trim();
  if (trimmed === '') return 0;
  const n = Number(trimmed);
  if (!Number.isNaN(n)) return n;
  const game = ctx.game;
  const constant = game.engine.script.constants.get(trimmed);
  if (constant !== undefined) return constant;
  if (trimmed.startsWith('scope:') && !trimmed.includes('.') && trimmed.slice(6) in ctx.values) {
    return ctx.values[trimmed.slice(6)];
  }
  if (trimmed.startsWith('defines.')) {
    let cur: any = game.defines;
    for (const p of trimmed.slice(8).split('.')) cur = cur?.[p];
    return typeof cur === 'number' ? cur : 0;
  }
  if (trimmed.startsWith('-')) return -evalValuePath(ctx, scope, trimmed.slice(1));
  const segs = splitPath(trimmed);
  let cur: ScopeRef | null = scope;
  for (let i = 0; i < segs.length - 1; i++) {
    cur = stepScope(ctx, cur, segs[i], i === 0);
    if (!cur) return 0;
  }
  const last = segs[segs.length - 1];
  if (last.startsWith('scope:') && last.slice(6) in ctx.values) return ctx.values[last.slice(6)];
  return getNamedValue(ctx, cur, last);
}

function getNamedValue(ctx: ScriptContext, scope: ScopeRef | null, nameWithArg: string): number {
  const game = ctx.game;
  const m = /^([\w:]+)(?:\((.*)\))?$/.exec(nameWithArg);
  if (!m) {
    game.scriptError(`Некорректное имя значения "${nameWithArg}"`);
    return 0;
  }
  const [, name, argPath] = m;
  if (name.startsWith('var:')) {
    const holder =
      scope?.type === 'character' ? game.char(scope.id)?.vars : scope?.type === 'province' ? game.state.provinces[scope.id]?.vars : game.state.globalVars;
    return Number(holder?.[name.slice(4)] ?? 0) || 0;
  }
  if (name.startsWith('global_var:')) return Number(game.state.globalVars[name.slice(11)] ?? 0) || 0;
  const def = game.engine.script.values.get(name);
  if (def) {
    if (!scope) return 0;
    if (def.scopes && !def.scopes.includes(scope.type)) return 0;
    const arg = argPath ? resolveScope(ctx, scope, argPath) : undefined;
    return def.get(ctx, scope, arg);
  }
  const sv = game.content.get('script_values', name);
  if (sv !== undefined) {
    if (!scope) return 0;
    if (!isPlainObject(sv)) return evalValue(ctx, scope, sv);
    const { id: _id, ...expr } = sv as Record<string, unknown>;
    return evalValue(ctx, scope, expr);
  }
  game.scriptError(`Неизвестное значение "${name}"`);
  return 0;
}

export function hasNamedValue(ctx: ScriptContext, name: string): boolean {
  return (
    ctx.game.engine.script.values.has(name) ||
    ctx.game.content.has('script_values', name) ||
    name.startsWith('var:') ||
    name.startsWith('global_var:')
  );
}

/** Сравнивает число с условием: 5 (≥5), ">= 3", "< scope:x.gold", { gte: 1, lt: 10 }, yes/no. */
export function compare(ctx: ScriptContext, scope: ScopeRef, actual: number, cond: unknown): boolean {
  if (typeof cond === 'number') return actual >= cond;
  if (typeof cond === 'boolean' || cond === 'yes' || cond === 'no') return (actual !== 0) === isYes(cond);
  if (typeof cond === 'string') {
    const m = CMP_RE.exec(cond);
    if (!m) return actual >= evalValue(ctx, scope, cond);
    return cmpOp(m[1], actual, evalValue(ctx, scope, m[2]));
  }
  if (isPlainObject(cond)) {
    for (const [op, rhs] of Object.entries(cond)) {
      const opNorm = OP_ALIASES[op];
      if (!opNorm) continue;
      if (!cmpOp(opNorm, actual, evalValue(ctx, scope, rhs))) return false;
    }
    return true;
  }
  return false;
}

const OP_ALIASES: Record<string, string> = {
  gte: '>=', gt: '>', lte: '<=', lt: '<', eq: '==', ne: '!=',
  '>=': '>=', '>': '>', '<=': '<=', '<': '<', '==': '==', '=': '==', '!=': '!=',
  min: '>=', max: '<=',
};

function cmpOp(op: string, a: number, b: number): boolean {
  switch (op) {
    case '>=': return a >= b;
    case '>': return a > b;
    case '<=': return a <= b;
    case '<': return a < b;
    case '=':
    case '==': return Math.abs(a - b) < 1e-9;
    case '!=': return Math.abs(a - b) >= 1e-9;
  }
  return false;
}

// ---------------------------------------------------------------- триггеры

export function evalTrigger(ctx: ScriptContext, scope: ScopeRef, block: unknown): boolean {
  if (block == null) return true;
  if (typeof block === 'boolean') return block;
  if (typeof block === 'string') {
    if (block === 'yes' || block === 'no') return block === 'yes';
    const st = ctx.game.content.get('scripted_triggers', block);
    if (st) return evalTrigger(ctx, scope, bodyOf(st, 'trigger'));
    ctx.game.scriptError(`Неизвестный триггер "${block}"`);
    return false;
  }
  if (Array.isArray(block)) return block.every((b) => evalTrigger(ctx, scope, b));
  if (!isPlainObject(block)) return false;
  if (ctx.depth > MAX_DEPTH) {
    ctx.game.scriptError('Слишком глубокая рекурсия в триггере');
    return false;
  }
  for (const [key, arg] of Object.entries(block)) {
    if (!evalTriggerKey(ctx, scope, key, arg)) return false;
  }
  return true;
}

function orBlock(ctx: ScriptContext, scope: ScopeRef, arg: unknown): boolean {
  if (Array.isArray(arg)) return arg.some((b) => evalTrigger(ctx, scope, b));
  if (isPlainObject(arg)) return Object.entries(arg).some(([k, v]) => evalTriggerKey(ctx, scope, k, v));
  return evalTrigger(ctx, scope, arg);
}

function withScope<T>(ctx: ScriptContext, from: ScopeRef, fn: () => T): T {
  const prev = ctx.prev;
  ctx.prev = from;
  ctx.depth++;
  try {
    return fn();
  } finally {
    ctx.prev = prev;
    ctx.depth--;
  }
}

export function evalTriggerKey(ctx: ScriptContext, scope: ScopeRef, key: string, arg: any): boolean {
  const game = ctx.game;
  const reg = game.engine.script;
  switch (key) {
    case 'AND':
    case 'and':
      return evalTrigger(ctx, scope, arg);
    case 'OR':
    case 'or':
      return orBlock(ctx, scope, arg);
    case 'NOT':
    case 'not':
    case 'NAND':
      return !evalTrigger(ctx, scope, arg);
    case 'NOR':
    case 'nor':
      return !orBlock(ctx, scope, arg);
    case 'always':
      return isYes(arg);
    case 'exists':
      if (arg === 'yes' || arg === true) return game.exists(scope);
      return resolveScope(ctx, scope, arg) != null;
    case 'is':
    case 'this':
      return sameScope(scope, resolveScope(ctx, scope, arg));
    case 'custom_tooltip':
    case 'custom_description':
      return isPlainObject(arg) ? evalTrigger(ctx, scope, arg.trigger) : true;
    case 'desc':
    case 'text':
      return true;
  }
  if (key.startsWith('scope:') && !key.includes('.')) {
    const name = key.slice(6);
    if (name in ctx.values) return compare(ctx, scope, ctx.values[name], arg);
    const sub = ctx.scopes[name];
    if (!sub) return false;
    return withScope(ctx, scope, () => evalTrigger(ctx, sub, arg));
  }
  if (key.startsWith('any_')) {
    const list = reg.lists.get(key.slice(4));
    if (list) return evalAny(ctx, scope, list.list(ctx, scope), arg);
  }
  const trig = reg.triggers.get(key);
  if (trig) {
    if (trig.scopes && !trig.scopes.includes(scope.type)) return false;
    return trig.eval(ctx, scope, arg);
  }
  const st = game.content.get('scripted_triggers', key);
  if (st) {
    const r = evalTrigger(ctx, scope, bodyOf(st, 'trigger'));
    return isYes(arg) || arg == null ? r : !r;
  }
  const link = reg.links.get(key);
  if (link) {
    if (link.from && !link.from.includes(scope.type)) return false;
    const sub = link.resolve(ctx, scope);
    if (!sub) return false;
    return withScope(ctx, scope, () => evalTrigger(ctx, sub, arg));
  }
  if (hasNamedValue(ctx, key.replace(/\(.*$/, ''))) {
    // Параметризованное значение: opinion: { target: scope:actor, value: ">= 10" }
    if (isPlainObject(arg) && 'target' in arg) {
      const t = resolveScope(ctx, scope, arg.target);
      if (!t) return false;
      const def = reg.values.get(key);
      const actual = def ? def.get(ctx, scope, t) : 0;
      return compare(ctx, scope, actual, arg.value ?? '>= 0');
    }
    return compare(ctx, scope, getNamedValue(ctx, scope, key), arg);
  }
  if (key.includes('.') || isScopeStart(ctx, key)) {
    const segs = splitPath(key);
    const last = segs[segs.length - 1];
    if (hasNamedValue(ctx, last.replace(/\(.*$/, ''))) {
      return compare(ctx, scope, evalValuePath(ctx, scope, key), arg);
    }
    const sub = resolveScope(ctx, scope, key);
    if (!sub) return false;
    return withScope(ctx, scope, () => evalTrigger(ctx, sub, arg));
  }
  game.scriptError(`Неизвестный триггер "${key}"`);
  return false;
}

function evalAny(ctx: ScriptContext, scope: ScopeRef, items: ScopeRef[], arg: any): boolean {
  let cond: any = arg;
  let count: unknown = '>= 1';
  let percent: unknown;
  if (isPlainObject(arg)) {
    const { count: c, percent: p, ...rest } = arg;
    cond = rest;
    if (c !== undefined) count = c;
    percent = p;
  } else if (isYes(arg)) cond = {};
  let n = 0;
  for (const it of items) {
    if (withScope(ctx, scope, () => evalTrigger(ctx, it, cond))) n++;
  }
  if (count === 'all') return n === items.length;
  if (percent !== undefined) return compare(ctx, scope, items.length ? n / items.length : 0, percent);
  return compare(ctx, scope, n, count);
}

// ---------------------------------------------------------------- эффекты

export function runEffect(ctx: ScriptContext, scope: ScopeRef, block: unknown): void {
  if (block == null) return;
  if (ctx.depth > MAX_DEPTH) {
    ctx.game.scriptError('Слишком глубокая рекурсия в эффекте');
    return;
  }
  const pairs = flattenEffects(block);
  let ifState: 'none' | 'matched' | 'unmatched' = 'none';
  for (const [key, arg] of pairs) {
    if (key === 'if') {
      ifState = runIf(ctx, scope, arg) ? 'matched' : 'unmatched';
      continue;
    }
    if (key === 'else_if') {
      if (ifState === 'unmatched') ifState = runIf(ctx, scope, arg) ? 'matched' : 'unmatched';
      continue;
    }
    if (key === 'else') {
      if (ifState === 'unmatched') runEffect(ctx, scope, arg);
      ifState = 'none';
      continue;
    }
    ifState = 'none';
    runEffectKey(ctx, scope, key, arg);
  }
}

function flattenEffects(block: unknown): [string, any][] {
  if (Array.isArray(block)) return block.flatMap((b) => flattenEffects(b));
  if (typeof block === 'string') return [[block, 'yes']];
  if (isPlainObject(block)) return Object.entries(block);
  return [];
}

function runIf(ctx: ScriptContext, scope: ScopeRef, arg: any): boolean {
  if (!isPlainObject(arg)) return false;
  const { limit, then, else: elseBlock, else_if, ...rest } = arg;
  if (evalTrigger(ctx, scope, limit)) {
    runEffect(ctx, scope, then);
    runEffect(ctx, scope, rest);
    return true;
  }
  if (else_if) {
    for (const b of Array.isArray(else_if) ? else_if : [else_if]) {
      if (runIf(ctx, scope, b)) return true;
    }
  }
  if (elseBlock !== undefined) {
    runEffect(ctx, scope, elseBlock);
    return true;
  }
  return false;
}

function iteratorParts(arg: any): { limit?: any; weight?: any; order_by?: any; max?: any; effects: any } {
  if (!isPlainObject(arg)) return { effects: arg };
  const { limit, weight, order_by, max, position: _p, effect, ...rest } = arg;
  return { limit, weight, order_by, max, effects: effect !== undefined ? [effect, rest] : rest };
}

export function runEffectKey(ctx: ScriptContext, scope: ScopeRef, key: string, arg: any): void {
  const game = ctx.game;
  const reg = game.engine.script;
  switch (key) {
    case 'effect':
    case 'hidden_effect':
    case 'then':
      runEffect(ctx, scope, arg);
      return;
    case 'custom_tooltip':
      if (isPlainObject(arg) && arg.effect) runEffect(ctx, scope, arg.effect);
      return;
    case 'limit':
      return;
    case 'random': {
      const { chance, ...rest } = isPlainObject(arg) ? arg : { chance: 50 };
      if (game.rng.next() * 100 < evalValue(ctx, scope, chance)) runEffect(ctx, scope, rest.effect ?? rest);
      return;
    }
    case 'random_list': {
      const opts = randomListOptions(ctx, scope, arg);
      const pick = game.rng.weighted(opts, (o) => o.weight);
      if (pick) runEffect(ctx, scope, pick.effect);
      return;
    }
    case 'save_scope_as':
      ctx.scopes[String(arg)] = scope;
      return;
    case 'save_scope_value_as':
      if (isPlainObject(arg)) ctx.values[arg.name] = evalValue(ctx, scope, arg.value);
      return;
    case 'trigger_event': {
      const spec = typeof arg === 'string' ? { id: arg } : arg;
      const delay = durationDays(spec);
      game.events.trigger(spec.id, scope, ctx.scopes, delay);
      return;
    }
  }
  if (key.startsWith('scope:') && !key.includes('.')) {
    const sub = ctx.scopes[key.slice(6)];
    if (sub) withScope(ctx, scope, () => runEffect(ctx, sub, arg));
    return;
  }
  for (const prefix of ['every_', 'random_', 'ordered_'] as const) {
    if (!key.startsWith(prefix)) continue;
    const list = reg.lists.get(key.slice(prefix.length));
    if (!list) continue;
    const { limit, weight, order_by, max, effects } = iteratorParts(arg);
    let items = list.list(ctx, scope).filter((it) => withScope(ctx, scope, () => evalTrigger(ctx, it, limit)));
    if (prefix === 'every_') {
      for (const it of items) withScope(ctx, scope, () => runEffect(ctx, it, effects));
    } else if (prefix === 'random_') {
      const it = weight != null ? game.rng.weighted(items, (i) => evalValue(ctx, i, weight)) : game.rng.pick(items);
      if (it) withScope(ctx, scope, () => runEffect(ctx, it, effects));
    } else {
      items = items
        .map((it) => ({ it, v: evalValue(ctx, it, order_by ?? 0) }))
        .sort((a, b) => b.v - a.v)
        .map((x) => x.it);
      const n = max != null ? evalValue(ctx, scope, max) : 1;
      for (const it of items.slice(0, n)) withScope(ctx, scope, () => runEffect(ctx, it, effects));
    }
    return;
  }
  const eff = reg.effects.get(key);
  if (eff) {
    if (eff.scopes && !eff.scopes.includes(scope.type)) {
      game.scriptError(`Эффект "${key}" нельзя применить к скоупу типа ${scope.type}`);
      return;
    }
    eff.apply(ctx, scope, arg);
    return;
  }
  const se = game.content.get('scripted_effects', key);
  if (se) {
    if (isYes(arg) || arg == null) runEffect(ctx, scope, bodyOf(se, 'effect'));
    return;
  }
  if (reg.links.has(key) || key.includes('.') || isScopeStart(ctx, key)) {
    const sub = resolveScope(ctx, scope, key);
    if (sub) withScope(ctx, scope, () => runEffect(ctx, sub, arg));
    return;
  }
  game.scriptError(`Неизвестный эффект "${key}"`);
}

export function randomListOptions(ctx: ScriptContext, scope: ScopeRef, arg: any): { weight: number; effect: any }[] {
  if (Array.isArray(arg)) {
    return arg
      .filter((o) => isPlainObject(o) && evalTrigger(ctx, scope, o.trigger))
      .map((o) => {
        const { weight, trigger: _t, effect, ...rest } = o;
        return { weight: evalValue(ctx, scope, weight ?? 1), effect: effect ?? rest };
      });
  }
  if (isPlainObject(arg)) {
    // Стиль CK3: { "50": {...}, "25": {...} }
    return Object.entries(arg).map(([w, e]) => ({ weight: Number(w) || 0, effect: e }));
  }
  return [];
}

// ---------------------------------------------------------------- описания

export interface DescLine {
  text: string;
  depth: number;
}

/**
 * Строит человекочитаемое описание эффекта для подсказок. Ничего не меняет
 * в мире и не трогает генератор случайных чисел; ветки if вычисляются по
 * текущему состоянию.
 */
export function describeEffect(ctx: ScriptContext, scope: ScopeRef, block: unknown, depth = 0, out: DescLine[] = []): DescLine[] {
  if (block == null || ctx.depth > MAX_DEPTH) return out;
  const game = ctx.game;
  const reg = game.engine.script;
  const prevDescribing = ctx.describing;
  ctx.describing = true;
  const pairs = flattenEffects(block);
  let ifState: 'none' | 'matched' | 'unmatched' = 'none';
  const describeIf = (arg: any): boolean => {
    if (!isPlainObject(arg)) return false;
    const { limit, then, else: elseBlock, else_if, ...rest } = arg;
    if (evalTrigger(ctx, scope, limit)) {
      describeEffect(ctx, scope, then, depth, out);
      describeEffect(ctx, scope, rest, depth, out);
      return true;
    }
    if (else_if) for (const b of Array.isArray(else_if) ? else_if : [else_if]) if (describeIf(b)) return true;
    if (elseBlock !== undefined) {
      describeEffect(ctx, scope, elseBlock, depth, out);
      return true;
    }
    return false;
  };
  try {
    for (const [key, arg] of pairs) {
      if (key === 'if') {
        ifState = describeIf(arg) ? 'matched' : 'unmatched';
        continue;
      }
      if (key === 'else_if') {
        if (ifState === 'unmatched') ifState = describeIf(arg) ? 'matched' : 'unmatched';
        continue;
      }
      if (key === 'else') {
        if (ifState === 'unmatched') describeEffect(ctx, scope, arg, depth, out);
        ifState = 'none';
        continue;
      }
      ifState = 'none';
      switch (key) {
        case 'hidden_effect':
        case 'limit':
        case 'save_scope_as':
        case 'save_scope_value_as':
        case 'trigger_event':
          continue;
        case 'effect':
        case 'then':
          describeEffect(ctx, scope, arg, depth, out);
          continue;
        case 'custom_tooltip':
          out.push({ text: game.text(isPlainObject(arg) ? arg.text : arg, ctx), depth });
          continue;
        case 'random': {
          const { chance, ...rest } = isPlainObject(arg) ? arg : { chance: 50 };
          out.push({ text: game.loc.t('fx.random', { chance: Math.round(evalValue(ctx, scope, chance)) }), depth });
          describeEffect(ctx, scope, rest.effect ?? rest, depth + 1, out);
          continue;
        }
        case 'random_list': {
          const opts = randomListOptions(ctx, scope, arg);
          const total = opts.reduce((s, o) => s + o.weight, 0) || 1;
          out.push({ text: game.loc.t('fx.random_list'), depth });
          for (const o of opts) {
            out.push({ text: game.loc.t('fx.random', { chance: Math.round((o.weight / total) * 100) }), depth: depth + 1 });
            describeEffect(ctx, scope, o.effect, depth + 2, out);
          }
          continue;
        }
      }
      if (key.startsWith('scope:') && !key.includes('.')) {
        const sub = ctx.scopes[key.slice(6)];
        if (sub) describeInScope(ctx, scope, sub, arg, depth, out);
        continue;
      }
      let handled = false;
      for (const prefix of ['every_', 'random_', 'ordered_']) {
        if (!key.startsWith(prefix)) continue;
        const list = reg.lists.get(key.slice(prefix.length));
        if (!list) continue;
        const { limit, effects } = iteratorParts(arg);
        const items = list.list(ctx, scope).filter((it) => withScope(ctx, scope, () => evalTrigger(ctx, it, limit)));
        handled = true;
        if (!items.length) break;
        out.push({ text: game.loc.t(`fx.iter.${prefix.slice(0, -1)}`, { list: game.loc.tOr(`list.${key.slice(prefix.length)}`, key.slice(prefix.length)), n: items.length }), depth });
        withScope(ctx, scope, () => describeEffect(ctx, items[0], effects, depth + 1, out));
        break;
      }
      if (handled) continue;
      const eff = reg.effects.get(key);
      if (eff) {
        const d = eff.describe ? eff.describe(ctx, scope, arg) : defaultDescribe(ctx, key, arg);
        if (d) for (const t of Array.isArray(d) ? d : [d]) out.push({ text: t, depth });
        continue;
      }
      const se = game.content.get('scripted_effects', key);
      if (se) {
        if (se.desc) out.push({ text: game.text(se.desc, ctx), depth });
        else describeEffect(ctx, scope, bodyOf(se, 'effect'), depth, out);
        continue;
      }
      const sub = resolveScope(ctx, scope, key);
      if (sub) describeInScope(ctx, scope, sub, arg, depth, out);
    }
  } finally {
    ctx.describing = prevDescribing;
  }
  return out;
}

function describeInScope(ctx: ScriptContext, from: ScopeRef, sub: ScopeRef, arg: unknown, depth: number, out: DescLine[]) {
  if (sameScope(sub, from)) {
    describeEffect(ctx, sub, arg, depth, out);
    return;
  }
  const inner: DescLine[] = [];
  withScope(ctx, from, () => describeEffect(ctx, sub, arg, depth + 1, inner));
  if (!inner.length) return;
  out.push({ text: `${ctx.game.scopeName(sub)}:`, depth });
  out.push(...inner);
}

function defaultDescribe(ctx: ScriptContext, key: string, arg: unknown): string | null {
  const k = `fx.${key}`;
  if (!ctx.game.loc.has(k)) return null;
  return ctx.game.loc.t(k, { value: typeof arg === 'object' ? '' : String(arg) });
}

/** Возвращает описания невыполненных условий верхнего уровня (для подсказок). */
export function failedTriggers(ctx: ScriptContext, scope: ScopeRef, block: unknown): string[] {
  if (block == null) return [];
  const pairs: [string, any][] = Array.isArray(block)
    ? block.flatMap((b) => (isPlainObject(b) ? Object.entries(b) : []))
    : isPlainObject(block)
      ? Object.entries(block)
      : [];
  const out: string[] = [];
  const game = ctx.game;
  for (const [key, arg] of pairs) {
    if (key === 'custom_tooltip' || key === 'custom_description') {
      if (isPlainObject(arg) && !evalTrigger(ctx, scope, arg.trigger)) out.push(game.text(arg.text, ctx));
      continue;
    }
    if (evalTriggerKey(ctx, scope, key, arg)) continue;
    const trig = game.engine.script.triggers.get(key);
    const d = trig?.describe?.(ctx, scope, arg);
    if (d) out.push(d);
    else {
      const lk = `tr.${key}`;
      out.push(
        game.loc.has(lk)
          ? game.loc.t(lk, { value: typeof arg === 'object' ? '' : String(arg) })
          : `${key}: ${typeof arg === 'object' ? JSON.stringify(arg) : String(arg)}`,
      );
    }
  }
  return out;
}
