/**
 * Настольная платформа (Electron). Мост window.desktop создаёт preload-скрипт
 * (electron/preload.cjs). Файлы модов отдаёт протокол cad://app/@mods/…:
 * так скрипты модов грузятся как обычные ES-модули (с относительными import).
 */
import type { ModManifest, ModPackage, ModSource } from '../engine/mods/types';
import type { FolderKind, Platform, SaveMeta } from './types';

export interface DesktopModEntry {
  origin: 'builtin' | 'user';
  folder: string;
  /** Текст mod.json (или null, если его нет). */
  manifest: string | null;
}

export interface DesktopBridge {
  version: string;
  platform: string;
  paths: Record<FolderKind, string>;
  /** Снимок настроек на момент запуска. */
  settings: Record<string, unknown>;
  setSetting(key: string, value: unknown): void;
  /** Базовый адрес файлов модов: cad://app/@mods/ */
  modsUrl: string;
  listMods(): Promise<DesktopModEntry[]>;
  listModFiles(origin: string, folder: string): Promise<string[]>;
  listSaves(): Promise<SaveMeta[]>;
  readSave(slot: string): Promise<string | null>;
  writeSave(meta: SaveMeta, json: string): Promise<void>;
  deleteSave(slot: string): Promise<void>;
  openFolder(which: FolderKind): void;
  quit(): void;
  setFullscreen(on: boolean): void;
  onFullscreenChange(cb: (on: boolean) => void): void;
  setZoom(factor: number): void;
}

const encodePath = (p: string) => p.split('/').map(encodeURIComponent).join('/');

class DesktopModSource implements ModSource {
  readonly kind = 'desktop' as const;
  private files: Promise<string[]> | null = null;
  constructor(
    private bridge: DesktopBridge,
    private origin: string,
    private folder: string,
  ) {}
  private url(path: string) {
    return `${this.bridge.modsUrl}${this.origin}/${encodeURIComponent(this.folder)}/${encodePath(path)}`;
  }
  listFiles() {
    return (this.files ??= this.bridge.listModFiles(this.origin, this.folder));
  }
  async readText(path: string) {
    const r = await fetch(this.url(path));
    if (!r.ok) throw new Error(`Нет файла ${this.folder}/${path}`);
    return r.text();
  }
  importScript(path: string) {
    return import(/* @vite-ignore */ this.url(path));
  }
}

export function createDesktopPlatform(bridge: DesktopBridge): Platform {
  const settings = { ...bridge.settings };
  let fullscreen = !!settings.fullscreen;
  const fsListeners: ((on: boolean) => void)[] = [];
  bridge.onFullscreenChange((on) => {
    fullscreen = on;
    settings.fullscreen = on;
    for (const cb of fsListeners) cb(on);
  });
  return {
    kind: 'desktop',
    version: bridge.version,
    async loadModPackages() {
      const out: ModPackage[] = [];
      const seen = new Map<string, number>();
      // Сначала встроенные, затем пользовательские: мод из «Документов»
      // с тем же id заменяет встроенный.
      const entries = (await bridge.listMods()).sort((a, b) => (a.origin === b.origin ? a.folder.localeCompare(b.folder) : a.origin === 'builtin' ? -1 : 1));
      for (const e of entries) {
        if (!e.manifest) continue;
        try {
          const manifest = JSON.parse(e.manifest) as ModManifest;
          const pkg: ModPackage = {
            manifest,
            source: new DesktopModSource(bridge, e.origin, e.folder),
            origin: e.origin === 'builtin' ? 'встроенный' : `${bridge.paths.mods}/${e.folder}`,
          };
          const i = seen.get(manifest.id);
          if (i !== undefined) out[i] = pkg;
          else {
            seen.set(manifest.id, out.length);
            out.push(pkg);
          }
        } catch (err) {
          console.error(`Не удалось прочитать mod.json в ${e.folder}`, err);
        }
      }
      return out;
    },
    settings: {
      get<T>(key: string, fallback: T): T {
        return key in settings ? (settings[key] as T) : fallback;
      },
      set(key: string, value: unknown) {
        if (value == null) delete settings[key];
        else settings[key] = value;
        bridge.setSetting(key, value ?? null);
      },
    },
    saves: {
      list: () => bridge.listSaves(),
      read: (slot) => bridge.readSave(slot),
      write: (meta, json) => bridge.writeSave(meta, json),
      remove: (slot) => bridge.deleteSave(slot),
    },
    folderPath: (which) => bridge.paths[which],
    openFolder: (which) => bridge.openFolder(which),
    quit: () => bridge.quit(),
    isFullscreen: () => fullscreen,
    setFullscreen: (on) => bridge.setFullscreen(on),
    onFullscreenChange: (cb) => {
      fsListeners.push(cb);
    },
    getZoom: () => Number(settings.zoom ?? 1),
    setZoom: (f) => {
      settings.zoom = f;
      bridge.setZoom(f);
    },
  };
}
