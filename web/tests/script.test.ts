import { beforeAll, describe, expect, it } from 'vitest';
import type { Engine } from '../src/engine/engine';
import type { Game } from '../src/engine/game';
import { charRef, makeContext } from '../src/engine/script/context';
import { describeEffect, evalTrigger, evalValue, runEffect } from '../src/engine/script/interpreter';
import { miniEngine } from './helpers';

let engine: Engine;
let game: Game;
const ctx = () => makeContext(game, charRef('king'), { other: charRef('duke') });

beforeAll(async () => {
  engine = await miniEngine({
    'data/extra.yaml': `
scripted_triggers:
  is_rich: { gold: ">= 50" }
script_values:
  double_gold: { value: gold, multiply: 2 }
`,
  });
  game = engine.newGame('start', 42);
});

describe('мини-мир', () => {
  it('создаётся без ошибок контента', () => {
    expect(engine.issues.filter((i) => i.level === 'error')).toEqual([]);
    expect(game.char('king')!.titles[0]).toBe('k_test');
    expect(game.char('duke')!.liege).toBe('king');
    expect(game.char('prince')!.liege).toBe('king');
    expect(engine.map.provinces.length).toBe(4);
  });
});

describe('триггеры', () => {
  it('сравнения значений', () => {
    expect(evalTrigger(ctx(), charRef('king'), { gold: 100 })).toBe(true);
    expect(evalTrigger(ctx(), charRef('king'), { gold: '> 100' })).toBe(false);
    expect(evalTrigger(ctx(), charRef('king'), { gold: { gte: 50, lt: 200 } })).toBe(true);
    expect(evalTrigger(ctx(), charRef('king'), { age: '>= 30' })).toBe(true);
    expect(evalTrigger(ctx(), charRef('king'), { martial: '>= 8' })).toBe(true); // 6 + brave 2
  });
  it('логика, ссылки и списки', () => {
    expect(evalTrigger(ctx(), charRef('king'), { OR: [{ has_trait: craven }, { has_trait: 'brave' }] })).toBe(true);
    expect(evalTrigger(ctx(), charRef('king'), { NOT: { has_trait: 'brave' } })).toBe(false);
    expect(evalTrigger(ctx(), charRef('prince'), { father: { has_trait: 'brave' } })).toBe(true);
    expect(evalTrigger(ctx(), charRef('king'), { any_vassal: { has_trait: 'craven' } })).toBe(true);
    expect(evalTrigger(ctx(), charRef('king'), { any_child: { count: '>= 2' } })).toBe(false);
    expect(evalTrigger(ctx(), charRef('king'), { 'scope:other': { is_vassal_of: 'root' } })).toBe(true);
    expect(evalTrigger(ctx(), charRef('king'), { 'scope:other.liege': { is_same_as: 'root' } })).toBe(true);
    expect(evalTrigger(ctx(), charRef('king'), { tier: '>= kingdom' })).toBe(true);
    expect(evalTrigger(ctx(), charRef('king'), 'is_rich')).toBe(true);
    expect(evalTrigger(ctx(), charRef('duke'), { is_rich: 'no' })).toBe(true);
  });
});

function has(arr: unknown[], x: unknown) {
  return arr.includes(x);
}
const craven = 'craven';
void has;

describe('значения', () => {
  it('выражения и именованные значения', () => {
    expect(evalValue(ctx(), charRef('king'), { value: 10, add: [5, { value: 'gold', multiply: 0.1 }], max: 20 })).toBe(20);
    expect(evalValue(ctx(), charRef('king'), 'double_gold')).toBe(200);
    expect(evalValue(ctx(), charRef('king'), 'scope:other.gold')).toBe(10);
    expect(evalValue(ctx(), charRef('king'), { value: 1, if: { limit: { has_trait: 'brave' }, add: 9 } })).toBe(10);
    const parts: { label: string; value: number }[] = [];
    evalValue(ctx(), charRef('king'), { value: 0, add: [{ desc: 'Тест', value: 7 }] }, parts);
    expect(parts).toEqual([{ label: 'Тест', value: 7 }]);
  });
});

describe('эффекты', () => {
  it('изменяют состояние и поддерживают if/else, итераторы и сохранённые скоупы', () => {
    const c = ctx();
    runEffect(c, charRef('king'), [
      { add_gold: 5 },
      { if: { limit: { gold: '> 1000' }, add_gold: 1000 }, else: { add_prestige: 7 } },
      { every_vassal: { add_gold: 1 } },
      { random_child: { save_scope_as: 'kid' } },
      { 'scope:kid': { add_trait: 'brave' } },
    ]);
    expect(game.char('king')!.gold).toBe(105);
    expect(game.char('king')!.prestige).toBeGreaterThanOrEqual(7);
    expect(game.char('duke')!.gold).toBe(11);
    expect(game.char('prince')!.traits).toContain('brave');
  });
  it('противоположные черты заменяют друг друга', () => {
    runEffect(ctx(), charRef('prince'), { add_trait: craven });
    expect(game.char('prince')!.traits).toContain('craven');
    expect(game.char('prince')!.traits).not.toContain('brave');
  });
  it('описание эффекта не меняет мир', () => {
    const before = JSON.stringify(game.state);
    const lines = describeEffect(ctx(), charRef('king'), [{ add_gold: 50 }, { 'scope:other': { add_prestige: 10 } }]);
    expect(lines.length).toBeGreaterThanOrEqual(2);
    expect(JSON.stringify(game.state)).toBe(before);
  });
  it('моды регистрируют свои триггеры и эффекты', async () => {
    const e2 = await miniEngine({}, {
      'scripts/m.js': {
        init(api: any) {
          api.script.trigger('is_king_named_adam', { eval: (c: any, s: any) => c.game.char(s.id)?.name === 'Adam' });
          api.script.effect('double_gold', { apply: (c: any, s: any) => { c.game.char(s.id).gold *= 2; } });
        },
      },
    }, { scripts: ['scripts/m.js'] });
    const g2 = e2.newGame('start', 1);
    const c2 = makeContext(g2, charRef('king'));
    expect(evalTrigger(c2, charRef('king'), { is_king_named_adam: true })).toBe(true);
    runEffect(c2, charRef('king'), { double_gold: 'yes' });
    expect(g2.char('king')!.gold).toBe(200);
  });
});
