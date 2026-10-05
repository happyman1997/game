import type { Engine } from './engine';
import { Game } from './game';
import type { GameState } from './types';
import { SAVE_VERSION } from './world/setup';

/**
 * Сохранения — это JSON состояния партии плюс список модов.
 * Данные модов (modData) сохраняются автоматически.
 */
export const SAVE_FORMAT = 'crown-and-dynasty-save';

export function serializeGame(game: Game): string {
  game.emit('game.before_save', {});
  return JSON.stringify({ format: SAVE_FORMAT, version: SAVE_VERSION, savedAt: new Date().toISOString(), state: game.state });
}

export function deserializeGame(engine: Engine, json: string): { game: Game; warnings: string[] } {
  const data = JSON.parse(json);
  if (data?.format !== SAVE_FORMAT || !data.state) throw new Error('Это не файл сохранения');
  const state = data.state as GameState;
  const warnings: string[] = [];
  if (data.version > SAVE_VERSION) warnings.push(`Сохранение сделано более новой версией (${data.version})`);
  const active = new Map(engine.mods.map((m) => [m.manifest.id, m.manifest.version]));
  for (const m of state.mods ?? []) {
    if (!active.has(m.id)) warnings.push(`Мод "${m.id}" был включён при сохранении, но сейчас отключён`);
    else if (m.version && active.get(m.id) !== m.version) warnings.push(`Версия мода "${m.id}" изменилась: ${m.version} → ${active.get(m.id)}`);
  }
  state.modData ??= {};
  state.pendingRequests ??= [];
  state.factions ??= {};
  state.mods = engine.mods.map((m) => ({ id: m.manifest.id, version: m.manifest.version }));
  const game = new Game(engine, state);
  game.markDirty();
  engine.hooks.emit('game.loaded', { game });
  return { game, warnings };
}
