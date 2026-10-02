import { isPlainObject } from './merge';

/**
 * Локализация. Файлы модов лежат в localization/<язык>/*.yaml и содержат
 * вложенные словари, которые «сплющиваются» в ключи через точку:
 *
 *   trait:
 *     brave: Храбрый      →  trait.brave
 *
 * Подстановки {name} заполняются параметрами из кода, а [путь]
 * вычисляется скриптовым движком (см. Game.text).
 */
export type TextValue = string | Record<string, string> | undefined | null;

export class Localization {
  private tables = new Map<string, Map<string, string>>();
  lang = 'ru';
  fallbacks: string[] = ['en', 'ru'];

  add(lang: string, entries: unknown, prefix = ''): void {
    let table = this.tables.get(lang);
    if (!table) {
      table = new Map();
      this.tables.set(lang, table);
    }
    const walk = (obj: unknown, pre: string) => {
      if (isPlainObject(obj)) {
        for (const [k, v] of Object.entries(obj)) walk(v, pre ? `${pre}.${k}` : k);
      } else if (obj != null) {
        table!.set(pre, String(obj));
      }
    };
    walk(entries, prefix);
  }

  languages(): string[] {
    return [...this.tables.keys()];
  }

  raw(key: string): string | undefined {
    const t = this.tables.get(this.lang)?.get(key);
    if (t !== undefined) return t;
    for (const fb of this.fallbacks) {
      const v = this.tables.get(fb)?.get(key);
      if (v !== undefined) return v;
    }
    return undefined;
  }

  /** Только текущий язык, без запасных (для имён: лучше «сырое» имя, чем перевод с другого языка). */
  rawExact(key: string): string | undefined {
    return this.tables.get(this.lang)?.get(key);
  }

  has(key: string): boolean {
    return this.raw(key) !== undefined;
  }

  t(key: string, params?: Record<string, unknown>): string {
    const s = this.raw(key);
    if (s === undefined) return params ? format(key, params) : key;
    return params ? format(s, params) : s;
  }

  /** Как t, но возвращает fallback, если ключа нет. */
  tOr(key: string, fallback: string, params?: Record<string, unknown>): string {
    const s = this.raw(key);
    return format(s ?? fallback, params ?? {});
  }

  /**
   * Разрешает «текстовое значение» из данных мода:
   *  - объект {ru: "...", en: "..."} — выбирается текущий язык;
   *  - строка, совпадающая с ключом локализации — переводится;
   *  - иначе строка используется как есть (можно писать текст прямо в данных).
   */
  resolve(v: TextValue, params?: Record<string, unknown>): string {
    if (v == null) return '';
    if (typeof v === 'object') {
      const s = v[this.lang] ?? this.fallbacks.map((f) => v[f]).find((x) => x != null) ?? Object.values(v)[0] ?? '';
      return params ? format(s, params) : s;
    }
    const s = this.raw(v) ?? v;
    return params ? format(s, params) : s;
  }

  keys(lang = this.lang): string[] {
    return [...(this.tables.get(lang)?.keys() ?? [])];
  }
}

export function format(template: string, params: Record<string, unknown>): string {
  return template.replace(/\{(\w+)\}/g, (m, k) => (k in params ? String(params[k]) : m));
}
