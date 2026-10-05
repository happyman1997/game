import { describe, expect, it } from 'vitest';
import { createDefaultFormats } from '../src/engine/core/formats';
import { loadMods } from '../src/engine/mods/loader';
import { memoryMod } from './helpers';

const formats = createDefaultFormats();

describe('загрузчик модов', () => {
  it('учитывает зависимости и load_after при порядке загрузки', async () => {
    const res = await loadMods(
      [
        memoryMod({ id: 'b', dependencies: ['a'] }, { 'data/x.yaml': 'things: { t: { v: b } }' }),
        memoryMod({ id: 'a' }, { 'data/x.yaml': 'things: { t: { v: a, keep: 1 } }' }),
        memoryMod({ id: 'c', load_after: ['b'] }, { 'data/x.yaml': 'things: { t: { v: c } }' }),
      ],
      formats,
    );
    expect(res.order.map((p) => p.manifest.id)).toEqual(['a', 'b', 'c']);
    expect(res.content.get('things', 't')).toEqual({ id: 't', v: 'c', keep: 1 });
    expect(res.content.provenance.get('things/t')).toEqual(['a', 'b', 'c']);
  });

  it('отключает мод без зависимостей и сообщает об ошибке', async () => {
    const res = await loadMods([memoryMod({ id: 'orphan', dependencies: ['missing'] }, {})], formats);
    expect(res.order).toHaveLength(0);
    expect(res.issues.some((i) => i.level === 'error' && i.mod === 'orphan')).toBe(true);
  });

  it('сообщает о синтаксических ошибках, не падая', async () => {
    const res = await loadMods([memoryMod({ id: 'bad' }, { 'data/x.yaml': 'a: [1, 2', 'data/y.json': '{ "things": { "ok": {} } }' })], formats);
    expect(res.issues.some((i) => i.file === 'data/x.yaml')).toBe(true);
    expect(res.content.has('things', 'ok')).toBe(true);
  });

  it('грузит локализацию по папкам языков и уважает enabled', async () => {
    const res = await loadMods(
      [
        memoryMod({ id: 'l' }, { 'localization/ru/a.yaml': 'hello: { world: Привет }', 'localization/en/a.yaml': 'hello: { world: Hello }' }),
        memoryMod({ id: 'off' }, { 'data/x.yaml': 'things: { z: {} }' }),
      ],
      formats,
      { enabled: new Set(['l']) },
    );
    res.loc.lang = 'en';
    expect(res.loc.t('hello.world')).toBe('Hello');
    res.loc.lang = 'ru';
    expect(res.loc.t('hello.world')).toBe('Привет');
    expect(res.content.has('things', 'z')).toBe(false);
  });

  it('JSON допускает комментарии', async () => {
    const res = await loadMods([memoryMod({ id: 'j' }, { 'data/a.json': '{ // комментарий\n "things": { "a": { "v": 1 } } /* ещё */ }' })], formats);
    expect(res.content.get('things', 'a').v).toBe(1);
  });
});
