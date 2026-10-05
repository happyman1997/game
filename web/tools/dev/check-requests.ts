import { createDefaultFormats } from '../../src/engine/core/formats';
import { Engine } from '../../src/engine/engine';
import { loadNodeLocale, loadNodeModPackages } from '../../src/engine/mods/nodeSource';
import { serializeGame } from '../../src/engine/save';
import { resolveRequest } from '../../src/engine/world/interactions';

const engine = await Engine.create(await loadNodeModPackages('../mods'), { defaultLocalization: await loadNodeLocale('../locale', (t, p) => createDefaultFormats().parse(t, p)) });
const game = engine.newGame('b1066', 5);
game.state.player = 'malcolm';
let requests = 0;
let events = 0;
for (let y = 0; y < 30; y++) {
  for (let d = 0; d < 365; d++) {
    game.tick();
    while (game.state.pendingEvents.length) {
      events++;
      game.events.choose(game.state.pendingEvents[0].uid, 0);
    }
    while (game.state.pendingRequests.length) {
      const r = game.state.pendingRequests[0];
      if (requests < 3) console.log('request:', r.interaction, 'from', game.scopeName({ type: 'character', id: r.actor }), r.secondary ? 'with ' + game.scopeName({ type: 'character', id: r.secondary }) : '', '→', game.scopeName({ type: 'character', id: r.recipient }));
      requests++;
      resolveRequest(game, r.uid, true);
    }
    if (game.state.gameOver) break;
  }
  if (game.state.gameOver) break;
}
const json = serializeGame(game);
console.log({ year: Math.floor(game.date / 365), player: game.player && game.scopeName({ type: 'character', id: game.player.id }, 'full_name'), requests, events, chars: Object.keys(game.state.characters).length, living: game.living().length, saveKB: Math.round(json.length / 1024), gameOver: game.state.gameOver });
