/**
 * Платформа, на которой запущена игра. Интерфейс игры не знает, где он
 * работает: в настольном приложении (Electron) моды, сохранения и настройки
 * лежат файлами на диске, в браузере — встроены в сборку и хранятся в
 * IndexedDB/localStorage.
 */
import type { ModPackage } from '../engine/mods/types';

export interface SaveMeta {
  slot: string;
  name: string;
  /** Игровая дата (д.м.г). */
  date: string;
  player: string;
  /** Когда сохранено (локальное время). */
  savedAt: string;
}

export interface SaveStore {
  /** От новых к старым. */
  list(): Promise<SaveMeta[]>;
  read(slot: string): Promise<string | null>;
  write(meta: SaveMeta, json: string): Promise<void>;
  remove(slot: string): Promise<void>;
}

export interface Settings {
  get<T>(key: string, fallback: T): T;
  set(key: string, value: unknown): void;
}

export type FolderKind = 'mods' | 'saves' | 'user' | 'builtin_mods';

export interface Platform {
  readonly kind: 'desktop' | 'web';
  /** Все доступные моды (встроенные и пользовательские). */
  loadModPackages(): Promise<ModPackage[]>;
  readonly saves: SaveStore;
  readonly settings: Settings;
  /** Только в настольной версии: */
  readonly version?: string;
  folderPath?(which: FolderKind): string;
  openFolder?(which: FolderKind): void;
  quit?(): void;
  isFullscreen?(): boolean;
  setFullscreen?(on: boolean): void;
  onFullscreenChange?(cb: (on: boolean) => void): void;
  /** Масштаб интерфейса (1 = 100%). */
  getZoom?(): number;
  setZoom?(f: number): void;
}
