/**
 * Источник модов из файловой системы — для тестов, CLI-симуляции и
 * валидатора. В браузерную сборку не попадает.
 */
import { readdir, readFile, stat } from 'node:fs/promises';
import { join, relative, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import type { ModManifest, ModPackage, ModSource } from './types';

export class NodeModSource implements ModSource {
  readonly kind = 'node' as const;
  constructor(private root: string) {}

  async listFiles(): Promise<string[]> {
    const out: string[] = [];
    const walk = async (dir: string) => {
      for (const name of await readdir(dir)) {
        const full = join(dir, name);
        const st = await stat(full);
        if (st.isDirectory()) await walk(full);
        else out.push(relative(this.root, full).split(sep).join('/'));
      }
    };
    await walk(this.root);
    return out.sort();
  }

  readText(path: string): Promise<string> {
    return readFile(join(this.root, path), 'utf8');
  }

  importScript(path: string): Promise<any> {
    return import(pathToFileURL(join(this.root, path)).href);
  }
}

/** Находит все моды (подпапки с mod.json) в указанной папке. */
export async function loadNodeModPackages(modsDir: string): Promise<ModPackage[]> {
  const out: ModPackage[] = [];
  for (const name of (await readdir(modsDir)).sort()) {
    const dir = join(modsDir, name);
    if (!(await stat(dir)).isDirectory()) continue;
    try {
      const manifest = JSON.parse(await readFile(join(dir, 'mod.json'), 'utf8')) as ModManifest;
      out.push({ manifest, source: new NodeModSource(dir), origin: dir });
    } catch {
      // не мод
    }
  }
  return out;
}

/** Загружает встроенную локализацию движка (src/locale/<язык>/*.yaml) для CLI и тестов. */
export async function loadNodeLocale(dir: string, parse: (text: string, path: string) => unknown): Promise<Record<string, unknown[]>> {
  const out: Record<string, unknown[]> = {};
  for (const lang of await readdir(dir)) {
    const ld = join(dir, lang);
    if (!(await stat(ld)).isDirectory()) continue;
    out[lang] = [];
    for (const f of (await readdir(ld)).sort()) {
      if (!/\.(ya?ml|json)$/.test(f)) continue;
      out[lang].push(parse(await readFile(join(ld, f), 'utf8'), join(ld, f)));
    }
  }
  return out;
}
