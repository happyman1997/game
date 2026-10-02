/**
 * Проверка модов: синтаксис файлов, зависимости, ссылки на несуществующий
 * контент и неизвестные ключи в скриптах.
 *   npm run validate              — все моды из ./mods
 *   npm run validate -- core,mymod — только указанные
 */
import { createDefaultFormats } from '../src/engine/core/formats';
import { Engine } from '../src/engine/engine';
import { loadNodeLocale, loadNodeModPackages } from '../src/engine/mods/nodeSource';

const only = process.argv[2];
const engine = await Engine.create(await loadNodeModPackages('mods'), {
  enabled: only ? new Set(only.split(',')) : null,
  defaultLocalization: await loadNodeLocale('src/locale', (t, p) => createDefaultFormats().parse(t, p)),
});
console.log(`Загружено модов: ${engine.mods.map((m) => `${m.manifest.id}@${m.manifest.version ?? '?'}`).join(', ')}`);
for (const t of ['traits', 'events', 'decisions', 'interactions', 'provinces', 'titles', 'characters']) {
  console.log(`  ${t}: ${engine.content.ids(t).length}`);
}
// Пробный запуск каждой закладки
for (const b of engine.bookmarks()) {
  try {
    const g = engine.newGame(b.id, 1);
    for (let d = 0; d < 60; d++) g.tick();
    console.log(`  закладка ${b.id}: OK (${g.rulers().length} правителей)`);
  } catch (e) {
    engine.issues.push({ level: 'error', message: `Закладка ${b.id}: ${(e as Error).message}` });
  }
}
// Локализация: ключи, которые есть в ru, но нет в en (и наоборот)
const langs = engine.loc.languages();
for (const a of langs) {
  for (const b of langs) {
    if (a === b) continue;
    const missing = engine.loc.keys(a).filter((k) => !engine.loc.keys(b).includes(k) && !k.startsWith('name.'));
    if (missing.length) console.log(`  локализация: в "${b}" нет ${missing.length} ключей из "${a}" (например: ${missing.slice(0, 5).join(', ')})`);
  }
}
if (!engine.issues.length) console.log('Проблем не найдено ✔');
for (const i of engine.issues) console.log(`[${i.level}] ${i.mod ?? ''} ${i.file ?? ''} ${i.message}`);
process.exit(engine.issues.some((i) => i.level === 'error') ? 1 : 0);
