/**
 * Моды, лежащие в папке /mods проекта, попадают в сборку через
 * import.meta.glob. Чтобы добавить мод — положите папку с mod.json в /mods
 * и перезапустите dev-сервер (или пересоберите игру).
 */
import type { ModManifest, ModPackage, ModSource } from '../engine/mods/types';

const dataFiles = import.meta.glob('/mods/**/*.{yaml,yml,json,txt}', { query: '?raw', import: 'default' }) as Record<string, () => Promise<string>>;
const scriptFiles = import.meta.glob('/mods/**/*.{js,mjs,ts}') as Record<string, () => Promise<any>>;

class BundledModSource implements ModSource {
  readonly kind = 'bundled' as const;
  constructor(private root: string) {}
  async listFiles() {
    return [...Object.keys(dataFiles), ...Object.keys(scriptFiles)].filter((p) => p.startsWith(this.root)).map((p) => p.slice(this.root.length));
  }
  async readText(path: string) {
    const f = dataFiles[this.root + path];
    if (!f) throw new Error(`Нет файла ${this.root}${path}`);
    return f();
  }
  async importScript(path: string) {
    const f = scriptFiles[this.root + path];
    if (!f) throw new Error(`Нет скрипта ${this.root}${path}`);
    return f();
  }
}

export async function bundledPackages(): Promise<ModPackage[]> {
  const out: ModPackage[] = [];
  for (const path of Object.keys(dataFiles)) {
    const m = /^\/mods\/([^/]+)\/mod\.json$/.exec(path);
    if (!m) continue;
    const root = `/mods/${m[1]}/`;
    try {
      const manifest = JSON.parse(await dataFiles[path]()) as ModManifest;
      out.push({ manifest, source: new BundledModSource(root), origin: 'встроенный' });
    } catch (e) {
      console.error(`Не удалось прочитать ${path}`, e);
    }
  }
  return out;
}
