/**
 * Проверка контента модов: ссылки на несуществующие записи и неизвестные
 * ключи в скриптовых блоках. Результат показывается в менеджере модов и
 * выводится командой `npm run validate`.
 */
import { isPlainObject } from '../core/merge';
import type { Engine } from '../engine';
import type { ModIssue } from '../mods/types';
import { bodyOf } from '../script/interpreter';

const TRIGGER_CONTROL = new Set(['AND', 'and', 'OR', 'or', 'NOT', 'not', 'NOR', 'nor', 'NAND', 'always', 'exists', 'is', 'this', 'custom_tooltip', 'custom_description', 'desc', 'text']);
const EFFECT_CONTROL = new Set(['if', 'else_if', 'else', 'effect', 'hidden_effect', 'then', 'custom_tooltip', 'limit', 'random', 'random_list', 'save_scope_as', 'save_scope_value_as', 'trigger_event']);

export class ScriptValidator {
  issues: ModIssue[] = [];
  constructor(private engine: Engine) {}

  /** Предупреждение от проверки механики или мода. */
  issue(message: string, level: 'warning' | 'error' = 'warning') {
    this.issues.push({ level, message });
  }

  /** Проверка ссылки на запись контента. */
  ref(type: string, id: unknown, where: string) {
    if (id == null) return;
    if (!this.engine.content.has(type, String(id))) this.issue(`${where}: ссылка на несуществующий ${type}/${id}`);
  }

  /** Проверка скриптового значения (только ссылок на триггеры внутри limit). */
  value(expr: unknown, where: string) {
    if (!isPlainObject(expr)) return;
    for (const [k, v] of Object.entries(expr)) {
      if (k === 'limit') this.trigger(v, where);
      else if (k === 'if' || k === 'add' || k === 'multiply' || k === 'subtract') for (const x of Array.isArray(v) ? v : [v]) this.value(x, where);
    }
  }

  /** Аргументы-ссылки на контент: has_trait: brave → traits/brave должна существовать. */
  private static readonly ARG_REFS: Record<string, { type: string; field?: string }> = {
    has_trait: { type: 'traits' },
    add_trait: { type: 'traits' },
    remove_trait: { type: 'traits' },
    has_modifier: { type: 'modifiers' },
    add_modifier: { type: 'modifiers', field: 'id' },
    remove_modifier: { type: 'modifiers' },
    add_province_modifier: { type: 'modifiers', field: 'id' },
    add_opinion: { type: 'opinion_modifiers', field: 'modifier' },
    reverse_add_opinion: { type: 'opinion_modifiers', field: 'modifier' },
    has_building: { type: 'buildings' },
    add_building: { type: 'buildings' },
    culture: { type: 'cultures' },
    faith: { type: 'faiths' },
    change_culture: { type: 'cultures' },
    change_faith: { type: 'faiths' },
    set_succession_law: { type: 'succession_laws' },
    has_perk: { type: 'perks' },
    add_perk: { type: 'perks' },
    has_focus: { type: 'focuses' },
    set_focus: { type: 'focuses' },
    has_secret: { type: 'secret_types' },
    has_realm_law: { type: 'realm_laws' },
    set_realm_law: { type: 'realm_laws' },
    add_regiment: { type: 'regiment_types' },
    has_regiment: { type: 'regiment_types' },
  };

  private checkArgRefs(key: string, arg: unknown, where: string) {
    const spec = ScriptValidator.ARG_REFS[key];
    if (!spec) return;
    let vals: unknown[] = [];
    if (spec.field && isPlainObject(arg)) vals = [arg[spec.field]];
    else vals = Array.isArray(arg) ? arg : [arg];
    for (const x of vals) {
      if (typeof x !== 'string' || x === 'yes' || x === 'no' || /[:.]/.test(x)) continue;
      if (spec.type === 'opinion_modifiers' && x === 'generic') continue;
      if (!this.engine.content.has(spec.type, x)) this.warn(where, `${key}: нет ${spec.type}/${x}`);
    }
  }

  private warn(where: string, msg: string) {
    const mods = this.engine.content.provenance.get(where.split(' ')[0]) ?? [];
    this.issues.push({ level: 'warning', mod: mods[mods.length - 1], message: `${where}: ${msg}` });
  }

  private isPathKey(key: string): boolean {
    const r = this.engine.script;
    if (key.startsWith('scope:') || key.startsWith('title:') || key.startsWith('character:') || key.startsWith('province:')) return true;
    if (key === 'root' || key === 'prev' || key === 'this') return true;
    if (key.includes('.')) {
      const first = key.split('.')[0];
      return this.isPathKey(first) || r.links.has(first);
    }
    return r.links.has(key);
  }

  private isValueKey(key: string): boolean {
    const name = key.replace(/\(.*$/, '');
    return (
      this.engine.script.values.has(name) ||
      this.engine.content.has('script_values', name) ||
      name.startsWith('var:') ||
      name.startsWith('global_var:')
    );
  }

  trigger(block: unknown, where: string): void {
    if (block == null || typeof block === 'boolean') return;
    if (typeof block === 'string') {
      if (block !== 'yes' && block !== 'no' && !this.engine.content.has('scripted_triggers', block)) this.warn(where, `неизвестный триггер "${block}"`);
      return;
    }
    if (Array.isArray(block)) {
      block.forEach((b) => this.trigger(b, where));
      return;
    }
    if (!isPlainObject(block)) return;
    const r = this.engine.script;
    for (const [k, v] of Object.entries(block)) {
      if (['AND', 'and', 'OR', 'or', 'NOT', 'not', 'NOR', 'nor', 'NAND'].includes(k)) {
        if (Array.isArray(v)) v.forEach((b) => this.trigger(b, where));
        else this.trigger(v, where);
        continue;
      }
      if (k === 'custom_tooltip' || k === 'custom_description') {
        if (isPlainObject(v)) this.trigger(v.trigger, where);
        continue;
      }
      if (TRIGGER_CONTROL.has(k)) continue;
      if (k.startsWith('any_') && r.lists.has(k.slice(4))) {
        if (isPlainObject(v)) {
          const { count: _c, percent: _p, ...rest } = v;
          this.trigger(rest, where);
        }
        continue;
      }
      if (r.triggers.has(k) || this.engine.content.has('scripted_triggers', k)) {
        this.checkArgRefs(k, v, where);
        continue;
      }
      if (this.isValueKey(k)) continue;
      if (this.isPathKey(k)) {
        if (isPlainObject(v) || Array.isArray(v)) this.trigger(v, where);
        continue;
      }
      this.warn(where, `неизвестный триггер "${k}"`);
    }
  }

  effect(block: unknown, where: string): void {
    if (block == null) return;
    if (typeof block === 'string') {
      if (!this.engine.content.has('scripted_effects', block) && !this.engine.script.effects.has(block)) this.warn(where, `неизвестный эффект "${block}"`);
      return;
    }
    if (Array.isArray(block)) {
      block.forEach((b) => this.effect(b, where));
      return;
    }
    if (!isPlainObject(block)) return;
    const r = this.engine.script;
    for (const [k, v] of Object.entries(block)) {
      if (k === 'if' || k === 'else_if') {
        for (const b of Array.isArray(v) ? v : [v]) {
          if (!isPlainObject(b)) continue;
          const { limit, then, else: e, else_if, ...rest } = b;
          this.trigger(limit, where);
          this.effect(then, where);
          this.effect(e, where);
          this.effect(rest, where);
          if (else_if) this.effect({ else_if }, where);
        }
        continue;
      }
      if (k === 'else' || k === 'effect' || k === 'hidden_effect' || k === 'then') {
        this.effect(v, where);
        continue;
      }
      if (k === 'random') {
        if (isPlainObject(v)) {
          const { chance: _c, ...rest } = v;
          this.effect(rest, where);
        }
        continue;
      }
      if (k === 'random_list') {
        const items = Array.isArray(v) ? v : isPlainObject(v) ? Object.values(v) : [];
        for (const it of items) {
          if (!isPlainObject(it)) continue;
          if (Array.isArray(v)) {
            const { weight: _w, trigger, effect, ...rest } = it;
            this.trigger(trigger, where);
            this.effect(effect ?? rest, where);
          } else this.effect(it, where);
        }
        continue;
      }
      if (k === 'custom_tooltip') {
        if (isPlainObject(v)) this.effect(v.effect, where);
        continue;
      }
      if (k === 'trigger_event') {
        const id = typeof v === 'string' ? v : (v as any)?.id;
        if (id && !this.engine.content.has('events', id)) this.warn(where, `trigger_event: нет события "${id}"`);
        continue;
      }
      if (EFFECT_CONTROL.has(k)) continue;
      const iter = ['every_', 'random_', 'ordered_'].find((p) => k.startsWith(p) && r.lists.has(k.slice(p.length)));
      if (iter) {
        if (isPlainObject(v)) {
          const { limit, weight: _w, order_by: _o, max: _m, position: _p, ...rest } = v;
          this.trigger(limit, where);
          this.effect(rest, where);
        }
        continue;
      }
      if (r.effects.has(k) || this.engine.content.has('scripted_effects', k)) {
        this.checkArgRefs(k, v, where);
        continue;
      }
      if (this.isPathKey(k)) {
        this.effect(v, where);
        continue;
      }
      this.warn(where, `неизвестный эффект "${k}"`);
    }
  }
}

export function validateContent(engine: Engine): ModIssue[] {
  const c = engine.content;
  const v = new ScriptValidator(engine);
  const ref = (type: string, id: unknown, where: string) => {
    if (id == null) return;
    if (!c.has(type, String(id))) v.issues.push({ level: 'warning', message: `${where}: ссылка на несуществующий ${type}/${id}` });
  };

  for (const p of c.all('provinces')) {
    if (p.impassable) continue;
    ref('cultures', p.culture, `provinces/${p.id}`);
    ref('faiths', p.faith, `provinces/${p.id}`);
    ref('terrain', p.terrain, `provinces/${p.id}`);
    for (const h of p.holdings ?? []) ref('holdings', h, `provinces/${p.id}`);
    if (p.duchy) ref('titles', p.duchy, `provinces/${p.id}`);
  }
  for (const t of c.all('titles')) if (t.liege) ref('titles', t.liege, `titles/${t.id}`);
  for (const t of c.all('traits')) for (const o of t.opposites ?? []) ref('traits', o, `traits/${t.id}`);
  for (const ch of c.all('characters')) {
    for (const t of ch.traits ?? []) ref('traits', t, `characters/${ch.id}`);
    ref('cultures', ch.culture, `characters/${ch.id}`);
    ref('faiths', ch.faith, `characters/${ch.id}`);
    if (ch.dynasty) ref('dynasties', ch.dynasty, `characters/${ch.id}`);
    if (ch.father) ref('characters', ch.father, `characters/${ch.id}`);
    if (ch.mother) ref('characters', ch.mother, `characters/${ch.id}`);
  }
  for (const b of c.all('bookmarks')) {
    for (const [title, chId] of Object.entries(b.holders ?? {})) {
      ref('titles', title, `bookmarks/${b.id}`);
      ref('characters', chId, `bookmarks/${b.id}`);
    }
  }
  for (const law of c.all('succession_laws')) {
    if (!engine.registries.successionAlgorithms.has(law.algorithm)) v.issues.push({ level: 'warning', message: `succession_laws/${law.id}: нет алгоритма "${law.algorithm}"` });
  }
  for (const cb of c.all('casus_belli')) {
    if (!engine.registries.cbTargets.has(cb.targets)) v.issues.push({ level: 'warning', message: `casus_belli/${cb.id}: нет поставщика целей "${cb.targets}"` });
    v.trigger(cb.is_valid, `casus_belli/${cb.id} is_valid`);
    for (const k of ['on_declare', 'on_victory', 'on_white_peace', 'on_defeat']) v.effect(cb[k], `casus_belli/${cb.id} ${k}`);
  }
  for (const e of c.all('events')) {
    const w = `events/${e.id}`;
    v.trigger(e.trigger, `${w} trigger`);
    v.effect(e.immediate, `${w} immediate`);
    v.effect(e.after, `${w} after`);
    (e.options ?? []).forEach((o: any, i: number) => {
      v.trigger(o.trigger, `${w} option ${i + 1}`);
      v.effect(o.effect, `${w} option ${i + 1}`);
    });
  }
  for (const d of c.all('decisions')) {
    v.trigger(d.is_shown, `decisions/${d.id} is_shown`);
    v.trigger(d.is_valid, `decisions/${d.id} is_valid`);
    v.effect(d.effect, `decisions/${d.id} effect`);
  }
  for (const d of c.all('interactions')) {
    const w = `interactions/${d.id}`;
    v.trigger(d.is_shown, `${w} is_shown`);
    v.trigger(d.is_valid, `${w} is_valid`);
    v.effect(d.on_accept, `${w} on_accept`);
    v.effect(d.on_decline, `${w} on_decline`);
    if (d.secondary_actor) {
      v.trigger(d.secondary_actor.trigger, `${w} secondary_actor`);
      for (const l of Array.isArray(d.secondary_actor.list) ? d.secondary_actor.list : [d.secondary_actor.list]) {
        if (!engine.script.lists.has(l)) v.issues.push({ level: 'warning', message: `${w}: нет списка "${l}"` });
      }
    }
    if (d.target && !engine.registries.interactionTargets.has(d.target.provider))
      v.issues.push({ level: 'warning', message: `${w}: нет поставщика целей "${d.target.provider}"` });
    if (d.scheme) ref('schemes', d.scheme, w);
    if (d.decider && d.decider !== 'recipient' && d.decider !== 'guardian' && !engine.registries.interactionDeciders.has(d.decider))
      v.issues.push({ level: 'warning', message: `${w}: нет решающего "${d.decider}"` });
  }
  for (const s of c.all('schemes')) {
    v.trigger(s.is_valid, `schemes/${s.id} is_valid`);
    for (const k of ['on_success', 'on_failure', 'on_discovered']) v.effect(s[k], `schemes/${s.id} ${k}`);
  }
  for (const oa of c.all('on_actions')) {
    v.effect(oa.effect, `on_actions/${oa.id}`);
    for (const ev of oa.events ?? []) ref('events', ev, `on_actions/${oa.id}`);
    const re = oa.random_events?.events;
    const ids = Array.isArray(re) ? re.map((x: any) => x.event) : isPlainObject(re) ? Object.keys(re) : [];
    for (const ev of ids) ref('events', ev, `on_actions/${oa.id}`);
  }
  for (const st of c.all('scripted_triggers')) v.trigger(bodyOf(st, 'trigger'), `scripted_triggers/${st.id}`);
  for (const se of c.all('scripted_effects')) v.effect(bodyOf(se, 'effect'), `scripted_effects/${se.id}`);
  for (const b of c.all('buildings')) v.trigger(b.trigger, `buildings/${b.id}`);
  for (const [id, fn] of engine.registries.contentValidators.entries()) {
    try {
      fn(engine, v);
    } catch (e) {
      v.issue(`Проверка ${id}: ${(e as Error).message}`, 'error');
    }
  }
  return v.issues;
}
