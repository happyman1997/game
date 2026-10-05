/**
 * Браузерная платформа: моды встроены в сборку (import.meta.glob),
 * сохранения — в IndexedDB, настройки — в localStorage.
 */
import { kvDelete, kvGet, kvSet, safeLocal } from '../ui/storage';
import type { Platform, SaveMeta } from './types';

const INDEX = 'cad.saves';
/** Старые ключи localStorage, чтобы не потерять настройки прежних версий. */
const LEGACY: Record<string, string> = { lang: 'cad.lang', enabledMods: 'cad.enabledMods' };

function readIndex(): SaveMeta[] {
  try {
    return JSON.parse(safeLocal.get(INDEX) ?? '[]');
  } catch {
    return [];
  }
}

export function createWebPlatform(): Platform {
  return {
    kind: 'web',
    async loadModPackages() {
      const { bundledPackages } = await import('../ui/bundled');
      return bundledPackages();
    },
    settings: {
      get<T>(key: string, fallback: T): T {
        const raw = safeLocal.get(LEGACY[key] ?? `cad.setting.${key}`);
        if (raw == null) return fallback;
        if (key === 'lang') return raw as T;
        try {
          return JSON.parse(raw) as T;
        } catch {
          return fallback;
        }
      },
      set(key: string, value: unknown) {
        const k = LEGACY[key] ?? `cad.setting.${key}`;
        if (value == null) safeLocal.remove(k);
        else safeLocal.set(k, key === 'lang' ? String(value) : JSON.stringify(value));
      },
    },
    saves: {
      async list() {
        return readIndex();
      },
      read(slot) {
        return kvGet(`cad.save.${slot}`);
      },
      async write(meta, json) {
        await kvSet(`cad.save.${meta.slot}`, json);
        safeLocal.set(INDEX, JSON.stringify([meta, ...readIndex().filter((s) => s.slot !== meta.slot)]));
      },
      async remove(slot) {
        await kvDelete(`cad.save.${slot}`);
        safeLocal.set(INDEX, JSON.stringify(readIndex().filter((s) => s.slot !== slot)));
      },
    },
  };
}
