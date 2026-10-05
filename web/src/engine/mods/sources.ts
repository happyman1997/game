import type { ModManifest, ModPackage, ModSource } from './types';

/** Мод из набора файлов в памяти (удобно для тестов и генерации модов кодом). */
export class MemoryModSource implements ModSource {
  readonly kind = 'memory' as const;
  constructor(
    private files: Record<string, string>,
    private scripts: Record<string, any> = {},
  ) {}
  async listFiles() {
    return [...Object.keys(this.files), ...Object.keys(this.scripts)];
  }
  async readText(path: string) {
    const f = this.files[path];
    if (f === undefined) throw new Error(`Нет файла ${path}`);
    return f;
  }
  async importScript(path: string) {
    if (path in this.scripts) return this.scripts[path];
    throw new Error(`Нет скрипта ${path}`);
  }
}

/**
 * Папка мода, выбранная игроком через <input type="file" webkitdirectory>.
 * Скрипты загружаются через Blob URL как ES-модули.
 */
export class FileListModSource implements ModSource {
  readonly kind = 'folder' as const;
  constructor(private files: Map<string, File>) {}
  async listFiles() {
    return [...this.files.keys()];
  }
  async readText(path: string) {
    const f = this.files.get(path);
    if (!f) throw new Error(`Нет файла ${path}`);
    return f.text();
  }
  async importScript(path: string) {
    const text = await this.readText(path);
    const url = URL.createObjectURL(new Blob([text], { type: 'text/javascript' }));
    try {
      return await import(/* @vite-ignore */ url);
    } finally {
      URL.revokeObjectURL(url);
    }
  }
}

/**
 * Разбирает FileList из выбора папки в браузере на моды.
 * Поддерживает выбор как одной папки мода, так и папки с несколькими модами.
 */
export async function packagesFromFileList(list: FileList | File[]): Promise<ModPackage[]> {
  const byRoot = new Map<string, Map<string, File>>();
  const all = [...(list as any)] as File[];
  // Находим все mod.json и считаем их папки корнями модов.
  const roots = all
    .map((f) => (f as any).webkitRelativePath || f.name)
    .filter((p: string) => p.endsWith('mod.json'))
    .map((p: string) => p.slice(0, -'mod.json'.length));
  for (const f of all) {
    const p: string = (f as any).webkitRelativePath || f.name;
    const root = roots.filter((r) => p.startsWith(r)).sort((a, b) => b.length - a.length)[0];
    if (root === undefined) continue;
    if (!byRoot.has(root)) byRoot.set(root, new Map());
    byRoot.get(root)!.set(p.slice(root.length), f);
  }
  const out: ModPackage[] = [];
  for (const [root, files] of byRoot) {
    const source = new FileListModSource(files);
    const manifest = JSON.parse(await source.readText('mod.json')) as ModManifest;
    out.push({ manifest, source, origin: `папка ${root || '/'}` });
  }
  return out;
}
