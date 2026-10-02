import { Engine } from '../../src/engine/engine';
import { loadNodeModPackages } from '../../src/engine/mods/nodeSource';
import { warscore } from '../../src/engine/world/war';
import { realmLevy } from '../../src/engine/world/economy';
const engine = await Engine.create(await loadNodeModPackages('mods'), {});
for (const seed of [1, 2, 3]) {
  const game = engine.newGame('b1066', seed);
  const w = game.char('william')!, h = game.char('harold')!;
  console.log(`seed ${seed}: levies W=${realmLevy(game, w)} H=${realmLevy(game, h)}`);
  let printed = new Set<string>();
  for (let d = 0; d < 365 * 8; d++) {
    game.tick();
    for (const war of Object.values(game.state.wars)) {
      if ((war.attacker === 'william' || war.defender === 'harold') && !printed.has(war.id)) {
        printed.add(war.id);
        console.log(`  ${Math.floor(game.date/365)}.${Math.floor((game.date%365)/30)+1} war ${war.cb} ${war.attacker} -> ${war.defender} target ${war.target}, W levies ${realmLevy(game, w)}`);
      }
      if (war.attacker === 'william' && game.date % 60 === 0) {
        const ws = warscore(game, war);
        const arm = Object.values(game.state.armies).filter(a => war.attackers.includes(a.owner) || war.defenders.includes(a.owner)).map(a => `${a.owner}:${a.size}@${a.location}`).join(' ');
        console.log(`     ws ${JSON.stringify(ws)} armies ${arm}`);
      }
    }
  }
  console.log(`  england holder: ${game.state.titles.k_england.holder}, william alive: ${game.char('william')?.death === undefined}`);
}
