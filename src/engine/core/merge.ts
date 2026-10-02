/**
 * Слияние данных модов.
 *
 * По умолчанию объекты сливаются рекурсивно, а массивы и примитивы
 * заменяются. Поведение можно уточнить директивами:
 *
 *   $replace: true      — заменить объект целиком, а не сливать
 *   $delete: true       — удалить запись/поле
 *   { $append: [...] }  — дописать элементы в конец массива
 *   { $prepend: [...] } — дописать в начало массива
 *   { $remove: [...] }  — удалить элементы (по значению или по полю id)
 */
export const DELETE = Symbol('delete');

export function isPlainObject(v: unknown): v is Record<string, any> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

export function clone<T>(v: T): T {
  if (Array.isArray(v)) return v.map(clone) as any;
  if (isPlainObject(v)) {
    const out: Record<string, any> = {};
    for (const k of Object.keys(v)) out[k] = clone((v as any)[k]);
    return out as T;
  }
  return v;
}

const ARRAY_OPS = new Set(['$append', '$prepend', '$remove']);

function isArrayOp(v: unknown): v is Record<string, any[]> {
  if (!isPlainObject(v)) return false;
  const keys = Object.keys(v);
  return keys.length > 0 && keys.every((k) => ARRAY_OPS.has(k));
}

function sameItem(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (isPlainObject(a) && isPlainObject(b) && 'id' in b) return a.id === b.id;
  if (isPlainObject(a) && typeof b === 'string') return a.id === b;
  return JSON.stringify(a) === JSON.stringify(b);
}

/** Удаляет служебные $-ключи из результата. */
function stripDirectives(v: any): any {
  if (Array.isArray(v)) return v.map(stripDirectives);
  if (isPlainObject(v)) {
    const out: Record<string, any> = {};
    for (const k of Object.keys(v)) {
      if (k === '$replace' || k === '$delete') continue;
      out[k] = stripDirectives(v[k]);
    }
    return out;
  }
  return v;
}

export function deepMerge(base: any, patch: any): any {
  if (isPlainObject(patch)) {
    if (patch.$delete === true) return DELETE;
    if (isArrayOp(patch)) {
      let arr: any[] = Array.isArray(base) ? [...base] : [];
      if (patch.$remove) {
        const rem = patch.$remove;
        arr = arr.filter((x) => !rem.some((r: unknown) => sameItem(x, r)));
      }
      if (patch.$prepend) arr = [...clone(patch.$prepend), ...arr];
      if (patch.$append) arr = [...arr, ...clone(patch.$append)];
      return arr;
    }
    if (patch.$replace === true || !isPlainObject(base)) return stripDirectives(clone(patch));
    const out: Record<string, any> = clone(base);
    for (const k of Object.keys(patch)) {
      if (k === '$replace' || k === '$delete') continue;
      const v = deepMerge(base[k], patch[k]);
      if (v === DELETE) delete out[k];
      else out[k] = v;
    }
    return out;
  }
  return clone(patch);
}
