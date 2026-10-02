/** Отладка: как часто Вильгельм завоёвывает Англию (по нескольким сидам). */
import { createDefaultFormats } from '../../src/engine/core/formats';
import { Engine } from '../../src/engine/engine';
import { loadNodeLocale, loadNodeModPackages } from '../../src/engine/mods/nodeSource';
import { militaryStrength } from '../../src/engine/world/economy';

const engine = await Engine.create(await loadNodeModPackages('mods'), {
  defaultLocalization: await loadNodeLocale('src/locale', (t, p) => createDefaultFormats().parse(t, p)),
});
const seeds = (process.argv[2] ?? '1,2,3,4,5,6').split(',').map(Number);
let wins = 0;
for (const seed of seeds) {
  const game = engine.newGame('b1066', seed);
  const w = game.char('william')!;
  const h = game.char('harold')!;
  const s0 = `W=${Math.round(militaryStrength(game, w))} (${(w.regiments ?? []).map((r) => r.type).join(',')}) H=${Math.round(militaryStrength(game, h))} (${(h.regiments ?? []).map((r) => r.type).join(',')})`;
  const log: string[] = [];
  engine.hooks.on('war.ended', ({ war, outcome }) => { if (war.attacker === 'william') log.push(`${Math.floor(game.date / 365)} ${war.cb} ${outcome}`); });
  for (let d = 0; d < 365 * 6; d++) game.tick();
  const holder = game.state.titles.k_england.holder;
  const won = !!holder && game.char(holder)?.dynasty === w.dynasty;
  if (won) wins++;
  console.log(`seed ${seed}: ${s0} → England: ${holder} ${won ? 'NORMAN' : ''} ${log.join('; ')}`);
}
console.log(`William wins ${wins}/${seeds.length}`);
