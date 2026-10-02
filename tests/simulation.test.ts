import { describe, expect, it } from 'vitest';
import { serializeGame } from '../src/engine/save';
import type { Game } from '../src/engine/game';
import { domainCounties } from '../src/engine/world/titles';
import { realEngine } from './helpers';

function checkInvariants(game: Game) {
  const problems: string[] = [];
  for (const t of Object.values(game.state.titles)) {
    if (t.holder) {
      const h = game.char(t.holder);
      if (!h) problems.push(`${t.id}: владелец ${t.holder} не существует`);
      else if (h.death !== undefined) problems.push(`${t.id}: владелец мёртв`);
      else if (!h.titles.includes(t.id)) problems.push(`${t.id}: нет в списке титулов владельца`);
    }
  }
  for (const c of game.living()) {
    for (const t of c.titles) if (game.state.titles[t]?.holder !== c.id) problems.push(`${c.id}: титул ${t} принадлежит другому`);
    let cur = c;
    for (let i = 0; i < 40 && cur.liege; i++) {
      const l = game.char(cur.liege);
      if (!l) {
        problems.push(`${cur.id}: сюзерен ${cur.liege} не существует`);
        break;
      }
      cur = l;
      if (i === 39) problems.push(`${c.id}: цикл сюзеренитета`);
    }
  }
  for (const w of Object.values(game.state.wars)) {
    if (!game.isAlive(w.attacker) || !game.isAlive(w.defender)) problems.push(`${w.id}: лидер войны мёртв`);
  }
  return problems;
}

describe('симуляция 1066', () => {
  it('все моды загружаются без ошибок и предупреждений', async () => {
    const engine = await realEngine();
    expect(engine.mods.map((m) => m.manifest.id)).toEqual(expect.arrayContaining(['core', 'plague', 'tournaments', 'elective_monarchy']));
    expect(engine.issues).toEqual([]);
  });

  it('25 лет без игрока: мир остаётся согласованным', async () => {
    const engine = await realEngine();
    const game = engine.newGame('b1066', 7);
    expect(checkInvariants(game)).toEqual([]);
    for (let y = 0; y < 25; y++) {
      for (let d = 0; d < 365; d++) game.tick();
      const probs = checkInvariants(game);
      expect(probs, `год ${Math.floor(game.date / 365)}`).toEqual([]);
    }
    // правители держат хотя бы одно графство
    const landless = game.rulers().filter((r) => domainCounties(game, r).length === 0);
    expect(landless.length).toBeLessThanOrEqual(2);
    expect(game.living().length).toBeGreaterThan(200);
    expect(engine.issues.filter((i) => i.message.startsWith('Скрипт'))).toEqual([]);
  });

  it('сохранение и загрузка дают то же состояние, а партия продолжается детерминированно', async () => {
    const engine = await realEngine();
    const game = engine.newGame('b1066', 3);
    game.state.player = 'william';
    for (let d = 0; d < 400; d++) game.tick();
    const json = serializeGame(game);
    const { game: loaded, warnings } = engine.loadGame(json);
    expect(warnings).toEqual([]);
    expect(JSON.parse(serializeGame(loaded)).state).toEqual(JSON.parse(json).state);
    // одинаковые сиды → одинаковое будущее
    const g1 = engine.loadGame(json).game;
    const g2 = engine.loadGame(json).game;
    for (let d = 0; d < 200; d++) {
      g1.tick();
      g2.tick();
    }
    expect(g1.state.rng).toEqual(g2.state.rng);
    expect(Object.keys(g1.state.characters).length).toBe(Object.keys(g2.state.characters).length);
  });

  it('игрок получает события и может их выбирать; наследник продолжает игру', async () => {
    const engine = await realEngine(['core']);
    const game = engine.newGame('b1066', 11);
    game.state.player = 'harold';
    game.onAction('on_player_start', { type: 'character', id: 'harold' });
    expect(game.state.pendingEvents.length).toBeGreaterThan(0);
    while (game.state.pendingEvents.length) game.events.choose(game.state.pendingEvents[0].uid, 0);
    // смерть игрока → наследник
    const { killCharacter } = await import('../src/engine/world/succession');
    killCharacter(game, game.char('harold')!, 'battle');
    expect(game.state.player).not.toBe('harold');
    expect(game.player?.titles).toContain('k_england');
  });
});
