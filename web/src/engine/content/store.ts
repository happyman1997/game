import { DELETE, deepMerge, isPlainObject } from '../core/merge';

/**
 * Хранилище контента — результат слияния данных всех модов.
 *
 * Каждый файл данных — это словарь «тип контента → { id → определение }»:
 *
 *   traits:
 *     brave: { ... }
 *   events:
 *     my_mod.0001: { ... }
 *
 * Типы-«синглтоны» (defines, map) — это один объект, а не коллекция.
 * Неизвестные типы тоже сохраняются: так мод может завести свой тип
 * контента и читать его из JS-скрипта через content.all('мой_тип').
 */
export class ContentStore {
  private collections = new Map<string, Map<string, any>>();
  private singletons = new Map<string, any>();
  readonly singletonTypes = new Set<string>(['defines', 'map']);
  /** "тип/id" → список модов, которые определили или изменили запись. */
  readonly provenance = new Map<string, string[]>();

  mergeSection(type: string, data: unknown, modId: string): void {
    if (this.singletonTypes.has(type)) {
      const merged = deepMerge(this.singletons.get(type) ?? {}, data);
      this.singletons.set(type, merged === DELETE ? {} : merged);
      this.track(type, '*', modId);
      return;
    }
    if (!isPlainObject(data)) throw new Error(`Раздел "${type}" должен быть словарём id → определение`);
    let col = this.collections.get(type);
    if (!col) {
      col = new Map();
      this.collections.set(type, col);
    }
    for (const [id, def] of Object.entries(data)) {
      const prev = col.get(id);
      const merged = deepMerge(prev, def ?? {});
      if (merged === DELETE) col.delete(id);
      else col.set(id, isPlainObject(merged) ? { ...merged, id } : merged);
      this.track(type, id, modId);
    }
  }

  private track(type: string, id: string, modId: string) {
    const k = `${type}/${id}`;
    const l = this.provenance.get(k) ?? [];
    if (!l.includes(modId)) l.push(modId);
    this.provenance.set(k, l);
  }

  get<T = any>(type: string, id: string | undefined | null): T | undefined {
    if (id == null) return undefined;
    return this.collections.get(type)?.get(id);
  }

  require<T = any>(type: string, id: string): T {
    const v = this.get<T>(type, id);
    if (v === undefined) throw new Error(`Нет контента ${type}/${id}`);
    return v;
  }

  has(type: string, id: string): boolean {
    return this.collections.get(type)?.has(id) ?? false;
  }

  set(type: string, id: string, def: any): void {
    let col = this.collections.get(type);
    if (!col) {
      col = new Map();
      this.collections.set(type, col);
    }
    col.set(id, isPlainObject(def) ? { ...def, id } : def);
  }

  delete(type: string, id: string): void {
    this.collections.get(type)?.delete(id);
  }

  all<T = any>(type: string): T[] {
    return [...(this.collections.get(type)?.values() ?? [])];
  }

  ids(type: string): string[] {
    return [...(this.collections.get(type)?.keys() ?? [])];
  }

  map<T = any>(type: string): Map<string, T> {
    let col = this.collections.get(type);
    if (!col) {
      col = new Map();
      this.collections.set(type, col);
    }
    return col;
  }

  singleton<T = any>(type: string): T {
    let s = this.singletons.get(type);
    if (!s) {
      s = {};
      this.singletons.set(type, s);
    }
    return s;
  }

  setSingleton(type: string, value: any): void {
    this.singletons.set(type, value);
  }

  types(): string[] {
    return [...this.collections.keys(), ...this.singletons.keys()];
  }
}
