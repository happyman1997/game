/** Отладка: кто получает Англию через 6 лет (по нескольким сидам). */
import { createDefaultFormats } from '../../src/engine/core/formats';
import { Engine } from '../../src/engine/engine';
import { loadNodeLocale, loadNodeModPackages } from '../../src/engine/mods/nodeSource';
import { militaryStrength } from '../../src/engine/world/economy';

const engine = await Engine.create(await loadNodeModPackages('mods'), {
  defaultLocalization: await loadNodeLocale('src/locale', (t, p) => createDefaultFormats().parse(t, p)),
});
const seeds = (process.argv[2] ?? '1,2,3,4,5,6').split(',').map(Number);
const tally: Record<string, number> = {};
let current: { log: string[]; game: any } = { log: [], game: null };
engine.hooks.on('war.declared', ({ war }) => {
  if (['william', 'harald_hardrada', 'sweyn_estridsen'].includes(war.attacker) && war.defender === 'harold') current.log.push(`${Math.floor(current.game.date / 365)} ${war.attacker} → ${war.cb}`);
});
engine.hooks.on('war.ended', ({ war, outcome }) => {
  if (war.defender === 'harold' || war.target === 'k_england') current.log.push(`${Math.floor(current.game.date / 365)} ${war.attacker}:${outcome}`);
});
for (const seed of seeds) {
  const game = engine.newGame('b1066', seed);
  current = { log: [], game };
  const s0 = ['william', 'harald_hardrada', 'harold'].map((id) => `${id}=${Math.round(militaryStrength(game, game.char(id)!))}`).join(' ');
  for (let d = 0; d < 365 * 6; d++) game.tick();
  const holder = game.state.titles.k_england.holder;
  const dyn = game.char(holder)?.dynasty ?? '?';
  tally[dyn] = (tally[dyn] ?? 0) + 1;
  console.log(`seed ${seed}: ${s0} → England: ${holder} (${dyn}) | ${current.log.join('; ')}`);
}
console.log('England by dynasty:', tally);
