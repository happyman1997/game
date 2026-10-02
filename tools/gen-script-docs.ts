/**
 * Генерирует справочник по скриптовому языку из реестров движка
 * (включая всё, что зарегистрировали JS-моды): docs/SCRIPT_REFERENCE.md
 */
import { writeFileSync } from 'node:fs';
import { createDefaultFormats } from '../src/engine/core/formats';
import { Engine } from '../src/engine/engine';
import { loadNodeLocale, loadNodeModPackages } from '../src/engine/mods/nodeSource';

const engine = await Engine.create(await loadNodeModPackages('mods'), {
  defaultLocalization: await loadNodeLocale('src/locale', (t, p) => createDefaultFormats().parse(t, p)),
});
const r = engine.script;
const lines: string[] = [
  '# Справочник скриптового языка',
  '',
  '> Файл сгенерирован командой `npm run docs:script` из реестров движка и включённых модов.',
  '> Колонка «Источник» показывает, кто зарегистрировал элемент (core — движок, иначе id мода).',
  '',
];
const table = (title: string, rows: [string, string, string, string][], head: [string, string, string, string]) => {
  lines.push(`## ${title}`, '', `| ${head.join(' | ')} |`, `|${head.map(() => '---').join('|')}|`);
  for (const row of rows.sort((a, b) => a[0].localeCompare(b[0]))) lines.push(`| ${row.map((c) => c.replace(/\|/g, '\\|')).join(' | ')} |`);
  lines.push('');
};
const owner = (reg: { ownerOf(id: string): string | undefined }, id: string) => reg.ownerOf(id) ?? 'core';
table('Триггеры (условия)', r.triggers.entries().map(([id, d]) => [`\`${id}\``, (d.scopes ?? ['любой']).join(', '), d.doc ?? '', owner(r.triggers, id)]), ['Имя', 'Скоупы', 'Описание', 'Источник']);
table('Эффекты', r.effects.entries().map(([id, d]) => [`\`${id}\``, (d.scopes ?? ['любой']).join(', '), d.doc ?? '', owner(r.effects, id)]), ['Имя', 'Скоупы', 'Описание', 'Источник']);
table('Значения', r.values.entries().map(([id, d]) => [`\`${id}\``, (d.scopes ?? ['любой']).join(', '), d.doc ?? '', owner(r.values, id)]), ['Имя', 'Скоупы', 'Описание', 'Источник']);
table('Ссылки на скоупы', r.links.entries().map(([id, d]) => [`\`${id}\``, (d.from ?? ['любой']).join(', '), d.doc ?? '', owner(r.links, id)]), ['Имя', 'Из скоупа', 'Описание', 'Источник']);
table('Списки (any_ / every_ / random_ / ordered_)', r.lists.entries().map(([id, d]) => [`\`${id}\``, (d.from ?? ['любой']).join(', '), d.doc ?? '', owner(r.lists, id)]), ['Имя', 'Из скоупа', 'Описание', 'Источник']);
table('Константы', r.constants.entries().map(([id, v]) => [`\`${id}\``, String(v), '', owner(r.constants, id)]), ['Имя', 'Значение', '', 'Источник']);
lines.push('## Механики', '', '| Механика | Описание | Включена |', '|---|---|---|');
for (const [id, f] of engine.features.entries()) lines.push(`| \`${id}\` | ${f.doc ?? ''} | ${engine.hasFeature(id) ? 'да' : 'нет'} |`);
lines.push('', 'Отключение: `defines.disabled_features: [id, ...]`. Источник `core/<механика>` в таблицах выше — элементы, которые регистрирует механика.', '');
lines.push('## Реестры движка', '');
for (const [name, reg] of Object.entries(engine.registries)) lines.push(`- **${name}**: ${reg.ids().map((x) => `\`${x}\``).join(', ')}`);
lines.push(`- **systems**: ${engine.orderedSystems().map((s) => `\`${s.id}\` (${s.order})`).join(', ')}`);
lines.push(`- **ui.mapModes**: ${engine.ui.mapModes.ids().map((x) => `\`${x}\``).join(', ') || '(регистрируются интерфейсом)'}`);
lines.push('');
writeFileSync('docs/SCRIPT_REFERENCE.md', lines.join('\n'));
console.log(`docs/SCRIPT_REFERENCE.md: ${r.triggers.size} триггеров, ${r.effects.size} эффектов, ${r.values.size} значений, ${r.links.size} ссылок, ${r.lists.size} списков`);
