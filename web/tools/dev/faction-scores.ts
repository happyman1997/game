/** Отладка: распределение желания ИИ-вассалов вступать во фракции. */
import { createDefaultFormats } from '../../src/engine/core/formats';
import { Engine } from '../../src/engine/engine';
import { type FactionDef, aiJoinScore, canJoinFaction, claimantCandidates } from '../../src/engine/features/factions';
import { loadNodeLocale, loadNodeModPackages } from '../../src/engine/mods/nodeSource';
import { opinion } from '../../src/engine/world/opinion';

const engine = await Engine.create(await loadNodeModPackages('../mods'), {
  defaultLocalization: await loadNodeLocale('../locale', (t, p) => createDefaultFormats().parse(t, p)),
});
const game = engine.newGame('b1066', 7);
for (let i = 0; i < 365 * Number(process.argv[2] ?? 3); i++) game.tick();
const scores: Record<string, number[]> = {};
const ops: number[] = [];
for (const v of game.rulers()) {
  if (!v.liege) continue;
  const l = game.char(v.liege)!;
  ops.push(opinion(game, v, l));
  for (const def of game.content.all<FactionDef>('factions')) {
    const cl = def.claimant ? claimantCandidates(game, l)[0]?.id : undefined;
    if (!canJoinFaction(game, v, def, l, cl)) continue;
    (scores[def.id] ??= []).push(Math.round(aiJoinScore(game, v, def, l, undefined, cl)));
  }
}
const q = (a: number[]) => { const s = [...a].sort((x, y) => x - y); return [s[0], s[Math.floor(s.length / 4)], s[Math.floor(s.length / 2)], s[Math.floor(s.length * 3 / 4)], s[s.length - 1]]; };
console.log('vassals', ops.length, 'opinion quartiles', q(ops));
for (const [k, v] of Object.entries(scores)) console.log(k, v.length, q(v));
import { factionPower } from '../../src/engine/features/factions';
import { realmLevy } from '../../src/engine/world/economy';
import { charFullName } from '../../src/engine/world/characters';
console.log('factions', Object.values(game.state.factions).map((f) => `${f.type} vs ${charFullName(game, game.char(f.target)!, true)} (${realmLevy(game, game.char(f.target)!)}) members ${f.members.length} power ${factionPower(game, f)}% disc ${f.discontent} [${f.members.map((m) => realmLevy(game, game.char(m)!)).join(',')}]`));
console.log('wars', Object.values(game.state.wars).map((w) => w.name));
