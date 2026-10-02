/**
 * Встроенные строки движка и интерфейса для браузерной сборки.
 * Моды могут переопределить любую строку в своих файлах локализации.
 */
const files = import.meta.glob('/src/locale/*/*.{yaml,yml}', { query: '?raw', import: 'default', eager: true }) as Record<string, string>;

export function defaultLocaleSources(): Record<string, { path: string; text: string }[]> {
  const out: Record<string, { path: string; text: string }[]> = {};
  for (const [path, text] of Object.entries(files)) {
    const lang = path.split('/')[3];
    (out[lang] ??= []).push({ path, text });
  }
  return out;
}
