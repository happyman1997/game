import { dateParts } from './core/date';
import { Rng } from './core/rng';
import type { TextValue } from './core/localization';
import type { Engine } from './engine';
import type { MapData } from './map/build';
import { type ScriptContext, makeContext } from './script/context';
import { evalValue, resolveScope, splitPath } from './script/interpreter';
import type { Character, GameState, Message, ProvinceState, ScopeRef, TitleState } from './types';
import { charFullName, charName, isAlive } from './world/characters';
import { EventRuntime } from './world/events';
import { titleFullName } from './world/titles';
import type { ProvinceDef, TitleDef } from './content/defs';

/**
 * Запущенная партия: состояние мира + ссылки на движок (контент, реестры).
 * Логика мира разнесена по модулям world/*, системы — по systems/*.
 */
export class Game {
  readonly rng: Rng;
  readonly events: EventRuntime;
  private livingCache: Character[] | null = null;
  private rulersCache: Character[] | null = null;
  private byLiege: Map<string, Character[]> | null = null;
  readonly statCache = new Map<string, Record<string, number>>();
  /** Кэш на день (сбрасывается каждый тик): для производных данных механик. */
  readonly dayCache = new Map<string, unknown>();
  /** Кэш на месяц (сбрасывается 1-го числа): для дорогих производных данных механик. */
  readonly monthCache = new Map<string, unknown>();
  private reportedErrors = new Set<string>();
  /** Слушатели изменений для UI (не сохраняются). */
  readonly listeners = new Set<(kind: string) => void>();
  /** Во время генерации мира on_action и сообщения отключены. */
  quiet = false;

  constructor(
    readonly engine: Engine,
    readonly state: GameState,
  ) {
    this.rng = new Rng(state.rng);
    this.events = new EventRuntime(this);
  }

  // ------------------------------------------------------------ доступ

  get content() {
    return this.engine.content;
  }
  get loc() {
    return this.engine.loc;
  }
  get defines(): any {
    return this.engine.content.singleton('defines');
  }
  get map(): MapData {
    return this.engine.map;
  }
  get date(): number {
    return this.state.date;
  }
  get player(): Character | undefined {
    return this.state.player ? this.state.characters[this.state.player] : undefined;
  }

  char(id: string | undefined | null): Character | undefined {
    return id ? this.state.characters[id] : undefined;
  }
  title(id: string | undefined | null): TitleState | undefined {
    return id ? this.state.titles[id] : undefined;
  }
  titleDef(id: string): TitleDef {
    return this.content.require<TitleDef>('titles', id);
  }
  prov(id: string | undefined | null): ProvinceState | undefined {
    return id ? this.state.provinces[id] : undefined;
  }
  provDef(id: string): ProvinceDef {
    return this.content.require<ProvinceDef>('provinces', id);
  }

  exists(ref: ScopeRef | null | undefined): boolean {
    if (!ref) return false;
    switch (ref.type) {
      case 'character':
        return !!this.state.characters[ref.id];
      case 'title':
        return !!this.state.titles[ref.id];
      case 'province':
        return !!this.state.provinces[ref.id];
      case 'dynasty':
        return !!this.state.dynasties[ref.id];
      case 'war':
        return !!this.state.wars[ref.id];
      case 'scheme':
        return !!this.state.schemes[ref.id];
      case 'army':
        return !!this.state.armies[ref.id];
      case 'faction':
        return !!this.state.factions[ref.id];
      default:
        return false;
    }
  }

  newId(prefix: string): string {
    return `${prefix}${this.state.nextId++}`;
  }

  // ------------------------------------------------------------ индексы

  /** Сбрасывает кэши индексов. Вызывайте после прямого изменения liege/titles. */
  markDirty(): void {
    this.livingCache = null;
    this.rulersCache = null;
    this.byLiege = null;
    this.statCache.clear();
  }

  living(): Character[] {
    if (!this.livingCache) this.livingCache = Object.values(this.state.characters).filter((c) => c.death === undefined);
    return this.livingCache;
  }

  rulers(): Character[] {
    if (!this.rulersCache) this.rulersCache = this.living().filter((c) => c.titles.length > 0);
    return this.rulersCache;
  }

  private liegeIndex(): Map<string, Character[]> {
    if (!this.byLiege) {
      this.byLiege = new Map();
      for (const c of this.living()) {
        if (!c.liege) continue;
        const l = this.byLiege.get(c.liege) ?? [];
        l.push(c);
        this.byLiege.set(c.liege, l);
      }
    }
    return this.byLiege;
  }

  /** Прямые вассалы (землевладельцы, чей сюзерен — id). */
  vassalsOf(id: string): Character[] {
    return (this.liegeIndex().get(id) ?? []).filter((c) => c.titles.length > 0);
  }

  /** Придворные (безземельные персонажи при дворе id). */
  courtiersOf(id: string): Character[] {
    return (this.liegeIndex().get(id) ?? []).filter((c) => c.titles.length === 0);
  }

  // ------------------------------------------------------------ текст

  /**
   * Разрешает текст из данных (ключ локализации, {ru, en} или сырой текст)
   * и подставляет [путь] из скриптового контекста:
   *   "[actor.name] просит руки [scope:target|g:вашего сына|вашей дочери]"
   */
  text(v: TextValue, ctx?: ScriptContext, params?: Record<string, unknown>): string {
    const s = this.loc.resolve(v, params);
    if (!s.includes('[')) return s;
    const c = ctx ?? (this.state.player ? makeContext(this, { type: 'character', id: this.state.player }) : undefined);
    if (!c) return s;
    return s.replace(/\[([^\]]+)\]/g, (_m, expr: string) => this.interpolate(expr, c));
  }

  private interpolate(expr: string, ctx: ScriptContext): string {
    const [pathRaw, ...mods] = expr.split('|');
    const path = pathRaw.trim();
    const gender = mods.find((m) => m.startsWith('g:'));
    const segs = splitPath(path);
    const last = segs[segs.length - 1];
    const props = ['name', 'first_name', 'full_name', 'title_name', 'rank', 'culture_name', 'faith_name', 'dynasty_name', 'age'];
    let scopePath = path;
    let prop: string | null = null;
    if (props.includes(last) && segs.length > 0) {
      prop = last;
      scopePath = segs.slice(0, -1).join('.') || 'root';
    }
    const sc = resolveScope(ctx, ctx.root, scopePath);
    if (gender && sc?.type === 'character') {
      const [m, f] = gender.slice(2).split('/');
      return this.char(sc.id)?.female ? (f ?? m) : m;
    }
    if (sc) return this.scopeName(sc, prop ?? 'name');
    const num = evalValue(ctx, ctx.root, path);
    return String(Math.round(num * 10) / 10);
  }

  /** Отображаемое имя объекта мира. */
  scopeName(ref: ScopeRef, prop = 'name'): string {
    switch (ref.type) {
      case 'character': {
        const c = this.char(ref.id);
        if (!c) return '?';
        switch (prop) {
          case 'first_name':
            return charName(this, c);
          case 'full_name':
            return charFullName(this, c, true);
          case 'title_name':
            return c.titles[0] ? titleFullName(this, c.titles[0]) : '';
          case 'rank':
            return charFullName(this, c, true).split(' ')[0];
          case 'culture_name':
            return this.nameOf('cultures', c.culture);
          case 'faith_name':
            return this.nameOf('faiths', c.faith);
          case 'dynasty_name':
            return c.dynasty ? this.nameOf('dynasties', c.dynasty) : '';
          case 'age':
            return String(Math.floor((this.date - c.birth) / 365));
          default:
            return charFullName(this, c, false);
        }
      }
      case 'title':
        return titleFullName(this, ref.id);
      case 'province':
        return this.nameOf('provinces', ref.id);
      case 'dynasty':
        return this.nameOf('dynasties', ref.id);
      case 'war': {
        const w = this.state.wars[ref.id];
        return w ? this.text(w.name ?? 'ui.war') : '?';
      }
      case 'faction': {
        const f = this.state.factions[ref.id];
        return f ? this.nameOf('factions', f.type) : '?';
      }
      default:
        return ref.id;
    }
  }

  /** Имя записи контента: поле name, ключ "тип.id", ключ id, иначе id. */
  nameOf(type: string, id: string): string {
    if (type === 'dynasties') {
      const st = this.state.dynasties[id];
      if (st?.name) return this.dynastyName(st.name);
    }
    const def = this.content.get(type, id) ?? (type === 'dynasties' ? this.state.dynasties[id] : undefined);
    if (def?.name != null) return this.loc.resolve(def.name);
    const singular = singularOf(type);
    for (const k of [`${singular}.${id}`, `${type}.${id}`, id]) {
      const v = this.loc.raw(k);
      if (v !== undefined) return v;
    }
    return id;
  }

  /** Название сгенерированной династии: "gen:<культура>:<имя или графство>". */
  dynastyName(raw: string): string {
    if (!raw.startsWith('gen:')) return this.loc.raw(`dynasty_name.${raw}`) ?? raw;
    const [, culture, key] = raw.split(':');
    const isPlace = !!this.content.get('provinces', key);
    const val = isPlace ? this.nameOf('provinces', key) : (this.loc.rawExact(`name.${key}`) ?? key);
    return this.loc.tOr(`dynasty_pattern.${culture}`, isPlace ? 'de {place}' : '{name}ing', { name: val, place: val });
  }

  descOf(type: string, id: string): string {
    const def = this.content.get(type, id);
    if (def?.desc != null) return this.loc.resolve(def.desc);
    const singular = singularOf(type);
    return this.loc.raw(`${singular}_desc.${id}`) ?? '';
  }

  scriptError(msg: string): void {
    if (this.reportedErrors.has(msg)) return;
    this.reportedErrors.add(msg);
    this.engine.reportIssue({ level: 'warning', message: `Скрипт: ${msg}` });
  }

  // ------------------------------------------------------------ хуки и сообщения

  emit(hook: string, payload: Record<string, unknown> = {}): void {
    this.engine.hooks.emit(hook, { game: this, ...payload });
  }

  /** Запускает on_action из данных и одноимённый хук "on_action.<id>". */
  onAction(id: string, root: ScopeRef, scopes: Record<string, ScopeRef> = {}): void {
    if (this.quiet) return;
    this.events.runOnAction(id, root, scopes);
    this.emit(`on_action.${id}`, { root, scopes });
  }

  /** Сообщение в журнал игрока. Сохраняется, только если касается игрока (или involves не задан). */
  message(text: string, kind: Message['kind'] = 'info', ref?: ScopeRef, involves?: (string | undefined)[]): void {
    if (this.quiet) return;
    if (involves && this.state.player && !involves.includes(this.state.player)) {
      // Проверяем, касается ли событие реалма игрока напрямую
      const p = this.state.player;
      const touches = involves.some((id) => {
        const c = this.char(id);
        return !!c && (c.liege === p || c.father === p || c.mother === p || c.spouses.includes(p));
      });
      if (!touches) return;
    }
    this.state.messages.push({ date: this.date, text, kind, ref });
    if (this.state.messages.length > 300) this.state.messages.splice(0, this.state.messages.length - 300);
    this.notify('message');
  }

  notify(kind: string): void {
    for (const l of this.listeners) {
      try {
        l(kind);
      } catch (e) {
        console.error(e);
      }
    }
  }

  isPlayer(id: string | undefined): boolean {
    return !!id && id === this.state.player;
  }

  // ------------------------------------------------------------ время

  /** Продвигает игру на один день. */
  tick(): void {
    if (this.state.gameOver) return;
    this.state.date += 1;
    this.statCache.clear();
    this.dayCache.clear();
    const { d, m } = dateParts(this.state.date);
    const systems = this.engine.orderedSystems();
    for (const s of systems) this.runSystem(s.id, () => s.onDay?.(this));
    if (d === 1) {
      this.monthCache.clear();
      this.markDirty();
      for (const s of systems) this.runSystem(s.id, () => s.onMonth?.(this));
      if (m === 1) for (const s of systems) this.runSystem(s.id, () => s.onYear?.(this));
    }
    this.emit('day');
    this.notify('tick');
  }

  private runSystem(id: string, fn: () => void) {
    try {
      fn();
    } catch (e: any) {
      console.error(`Ошибка в системе ${id}:`, e);
      this.scriptError(`Система ${id}: ${e?.message ?? e}`);
    }
  }

  /** Значение из дневного кэша (или вычислить и запомнить). */
  cachedDaily<T>(key: string, fn: () => T): T {
    if (this.dayCache.has(key)) return this.dayCache.get(key) as T;
    const v = fn();
    this.dayCache.set(key, v);
    return v;
  }

  /** Значение из помесячного кэша (или вычислить и запомнить). */
  cachedMonthly<T>(key: string, fn: () => T): T {
    if (this.monthCache.has(key)) return this.monthCache.get(key) as T;
    const v = fn();
    this.monthCache.set(key, v);
    return v;
  }

  /** Для мода: персистентные данные мода в сохранении. */
  modData<T = any>(modId: string, init: () => T): T {
    if (!(modId in this.state.modData)) this.state.modData[modId] = init();
    return this.state.modData[modId];
  }

  isAlive(id: string | undefined): boolean {
    return isAlive(this.char(id));
  }
}

/** Ключ локализации записи: traits → trait, dynasties → dynasty, focuses → focus. */
export function singularOf(type: string): string {
  if (/ies$/.test(type)) return type.replace(/ies$/, 'y');
  if (/(ss|x|z|sh|ch|us)es$/.test(type)) return type.replace(/es$/, '');
  return type.replace(/s$/, '');
}
