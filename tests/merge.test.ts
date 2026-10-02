import { describe, expect, it } from 'vitest';
import { DELETE, deepMerge } from '../src/engine/core/merge';

describe('deepMerge', () => {
  it('сливает объекты рекурсивно и заменяет массивы', () => {
    const base = { a: 1, b: { c: 2, d: 3 }, list: [1, 2] };
    expect(deepMerge(base, { b: { c: 5 }, list: [9] })).toEqual({ a: 1, b: { c: 5, d: 3 }, list: [9] });
  });
  it('$replace заменяет объект целиком', () => {
    expect(deepMerge({ b: { c: 2, d: 3 } }, { b: { $replace: true, x: 1 } })).toEqual({ b: { x: 1 } });
  });
  it('$delete удаляет поле', () => {
    expect(deepMerge({ a: 1, b: 2 }, { b: { $delete: true } })).toEqual({ a: 1 });
    expect(deepMerge({ a: 1 }, { $delete: true })).toBe(DELETE);
  });
  it('$append / $prepend / $remove работают со списками', () => {
    expect(deepMerge([1, 2, 3], { $append: [4] })).toEqual([1, 2, 3, 4]);
    expect(deepMerge([1, 2, 3], { $prepend: [0] })).toEqual([0, 1, 2, 3]);
    expect(deepMerge([1, 2, 3], { $remove: [2] })).toEqual([1, 3]);
    expect(deepMerge([{ id: 'a' }, { id: 'b' }], { $remove: ['a'] })).toEqual([{ id: 'b' }]);
    expect(deepMerge(undefined, { $append: ['x'] })).toEqual(['x']);
  });
  it('не мутирует исходные данные', () => {
    const base = { a: { b: [1] } };
    const out = deepMerge(base, { a: { c: 1 } });
    out.a.b.push(2);
    expect(base.a.b).toEqual([1]);
  });
});
