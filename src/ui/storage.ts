/**
 * Хранилище больших данных браузера (сохранения): IndexedDB с запасным
 * вариантом localStorage. Сохранение партии за десятки лет весит
 * мегабайты — в localStorage (~5 МБ на сайт) поместилось бы лишь пара слотов.
 */
const DB = 'crown-and-dynasty';
const STORE = 'kv';

let dbPromise: Promise<IDBDatabase | null> | null = null;
/** Последний запасной вариант: память вкладки (если браузер запретил и IndexedDB, и localStorage). */
const memory = new Map<string, string>();

/** localStorage, который не бросает исключений (в песочнице доступ к нему может быть запрещён). */
export const safeLocal = {
  get(key: string): string | null {
    try {
      return localStorage.getItem(key);
    } catch {
      return memory.get(key) ?? null;
    }
  },
  set(key: string, value: string): void {
    try {
      localStorage.setItem(key, value);
    } catch {
      memory.set(key, value);
    }
  },
  remove(key: string): void {
    memory.delete(key);
    try {
      localStorage.removeItem(key);
    } catch {
      /* ignore */
    }
  },
};

function openDb(): Promise<IDBDatabase | null> {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve) => {
    try {
      if (typeof indexedDB === 'undefined') return resolve(null);
      const req = indexedDB.open(DB, 1);
      req.onupgradeneeded = () => req.result.createObjectStore(STORE);
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => resolve(null);
      req.onblocked = () => resolve(null);
    } catch {
      resolve(null);
    }
  });
  return dbPromise;
}

function tx<T>(db: IDBDatabase, mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    try {
      const t = db.transaction(STORE, mode);
      const r = fn(t.objectStore(STORE));
      r.onsuccess = () => resolve(r.result);
      r.onerror = () => reject(r.error);
    } catch (e) {
      reject(e);
    }
  });
}

export async function kvSet(key: string, value: string): Promise<void> {
  const db = await openDb();
  if (db) {
    try {
      await tx(db, 'readwrite', (s) => s.put(value, key));
      safeLocal.remove(key); // старая копия из localStorage больше не нужна
      return;
    } catch (e) {
      console.warn('IndexedDB: запись не удалась, используем запасное хранилище', e);
    }
  }
  safeLocal.set(key, value);
}

export async function kvGet(key: string): Promise<string | null> {
  const db = await openDb();
  if (db) {
    try {
      const v = await tx<string | undefined>(db, 'readonly', (s) => s.get(key));
      if (v != null) return v;
    } catch {
      /* читаем из запасного хранилища */
    }
  }
  return safeLocal.get(key); // сохранения прежних версий
}

export async function kvDelete(key: string): Promise<void> {
  const db = await openDb();
  if (db) await tx(db, 'readwrite', (s) => s.delete(key)).catch(() => undefined);
  safeLocal.remove(key);
}
