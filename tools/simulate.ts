/**
 * Безголовая симуляция: грузит моды из ./mods, создаёт партию и крутит
 * время без игрока. Полезно моддерам для проверки баланса и ошибок.
 *   npm run sim -- --years 50 --seed 42 [--bookmark b1066] [--mods core,example]
 */
import { Engine } from '../src/engine/engine';
import { loadNodeLocale, loadNodeModPackages } from '../src/engine/mods/nodeSource';
import { createDefaultFormats } from '../src/engine/core/formats';
import { realmCounties, titleFullName, topLiege } from '../src/engine/world/titles';
import { charFullName } from '../src/engine/world/characters';

function arg(name: string, def?: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : def;
}

const years = Number(arg('years', '30'));
const seed = Number(arg('seed', '1066'));
const modsArg = arg('mods');
const t0 = Date.now();
const engine = await Engine.create(await loadNodeModPackages('mods'), {
  enabled: modsArg ? new Set(modsArg.split(',')) : null,
  lang: arg('lang', 'ru'),
  defaultLocalization: await loadNodeLocale('src/locale', (t, p) => createDefaultFormats().parse(t, p)),
});
console.log(`Моды: ${engine.mods.map((m) => m.manifest.id).join(', ')} (${Date.now() - t0} мс)`);
for (const i of engine.issues) console.log(`  [${i.level}] ${i.mod ?? ''} ${i.file ?? ''} ${i.message}`);
const stats: Record<string, number> = {};
const count = (k: string) => (stats[k] = (stats[k] ?? 0) + 1);
const verbose = process.argv.includes('--verbose');
engine.hooks.on('war.declared', ({ game, war }) => {
  count('войн объявлено');
  if (verbose) console.log(`    ⚔ ${Math.floor(game.date / 365)}: ${war.name}`);
});
engine.hooks.on('war.ended', ({ game, war, outcome }) => {
  count(`войн: ${outcome}`);
  if (verbose) console.log(`    🏳 ${Math.floor(game.date / 365)}: ${war.name} — ${outcome}`);
});
engine.hooks.on('battle', () => count('сражений'));
engine.hooks.on('siege.won', () => count('осад'));
engine.hooks.on('character.birth', () => count('рождений'));
engine.hooks.on('character.death', ({ reason }) => count(`смертей: ${reason}`));
engine.hooks.on('character.marriage', () => count('браков'));
engine.hooks.on('event.fired', () => count('событий'));
engine.hooks.on('interaction', ({ interaction, accepted }) => count(`взаимодействие ${interaction}${accepted ? '' : ' (отказ)'}`));
engine.hooks.on('decision.taken', ({ decision }) => count(`решение ${decision}`));
engine.hooks.on('scheme.ended', ({ scheme, success }) => count(`интрига ${scheme.type} ${success ? 'успех' : 'провал'}`));
engine.hooks.on('title.transferred', () => count('передач титулов'));
engine.hooks.on('perk.gained', () => count('перков открыто'));
engine.hooks.on('council.appointed', () => count('назначений в совет'));
engine.hooks.on('prison.imprisoned', ({ reason }) => count(`заключений${reason ? ` (${reason})` : ''}`));
engine.hooks.on('prison.released', ({ reason }) => count(`освобождений${reason ? ` (${reason})` : ''}`));
engine.hooks.on('faction.created', ({ faction }) => count(`фракций создано: ${faction.type}`));
engine.hooks.on('faction.ultimatum', ({ faction, accepted }) => count(`ультиматумов ${faction.type}: ${accepted ? 'принято' : 'война'}`));
engine.hooks.on('regiment.recruited', ({ regiment }) => count(`отрядов нанято: ${regiment.type}`));
const bookmark = arg('bookmark') ?? engine.bookmarks()[0]?.id;
const game = engine.newGame(bookmark, seed);
console.log(`Старт: ${game.living().length} живых персонажей, ${game.rulers().length} правителей`);

const report = () => {
  const tops = game.rulers().filter((r) => !r.liege);
  const sized = tops.map((r) => ({ r, n: realmCounties(game, r).length })).sort((a, b) => b.n - a.n).slice(0, 8);
  console.log(`  ${new Date(0).getFullYear() && Math.floor(game.date / 365)}: живых ${game.living().length}, войн ${Object.keys(game.state.wars).length}, армий ${Object.keys(game.state.armies).length}`);
  for (const { r, n } of sized) console.log(`    ${charFullName(game, r, true)} — ${titleFullName(game, r.titles[0])}, графств: ${n}, золото ${Math.round(r.gold)}`);
};
report();
const t1 = Date.now();
for (let y = 0; y < years; y++) {
  for (let d = 0; d < 365; d++) game.tick();
  if ((y + 1) % 10 === 0 || y === years - 1) report();
}
console.log(`Симуляция ${years} лет: ${Date.now() - t1} мс`);
console.log('Статистика:');
for (const [k, v] of Object.entries(stats).sort()) console.log(`  ${k}: ${v}`);
const issues = engine.issues.filter((i) => i.message.startsWith('Скрипт'));
if (issues.length) {
  console.log('Ошибки скриптов:');
  for (const i of issues.slice(0, 40)) console.log('  ', i.message);
}
void topLiege;
