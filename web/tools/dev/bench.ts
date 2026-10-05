/** Отладка: время симуляции с разными отключёнными механиками. npx tsx tools/dev/bench.ts 10 secrets,council */
import { createDefaultFormats } from '../../src/engine/core/formats';
import { Engine } from '../../src/engine/engine';
import { MemoryModSource } from '../../src/engine/mods/sources';
import { loadNodeLocale, loadNodeModPackages } from '../../src/engine/mods/nodeSource';

const years = Number(process.argv[2] ?? 10);
const disabled = (process.argv[3] ?? '').split(',').filter(Boolean);
const pkgs = await loadNodeModPackages('../mods');
if (disabled.length) {
  pkgs.push({
    manifest: { id: 'bench', name: 'bench', dependencies: ['core'] } as any,
    source: new MemoryModSource({ 'data/d.yaml': `defines:\n  disabled_features: [${disabled.join(', ')}]\n` }, {}),
    origin: 'memory',
  });
}
const engine = await Engine.create(pkgs, { defaultLocalization: await loadNodeLocale('../locale', (t, p) => createDefaultFormats().parse(t, p)) });
const game = engine.newGame('b1066', 1066);
engine.map;
const t0 = Date.now();
for (let i = 0; i < 365 * years; i++) game.tick();
console.log(`disabled=[${disabled}] ${years}y: ${Date.now() - t0} ms, living ${game.living().length}, chars ${Object.keys(game.state.characters).length}`);
