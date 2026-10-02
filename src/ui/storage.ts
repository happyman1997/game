/**
 * Хранилище больших данных браузера (сохранения): IndexedDB с запасным
 * вариантом localStorage. Сохранение партии за десятки лет весит
 * мегабайты — в localStorage (~5 МБ на сайт) поместилось бы лишь пара слотов.
 */
const DB = 'crown-and-dynasty';
const STORE = 'kv';

let dbPromise: Promise<IDBDatabase | null> | null = null;

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
    const t = db.transaction(STORE, mode);
    const r = fn(t.objectStore(STORE));
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
}

export async function kvSet(key: string, value: string): Promise<void> {
  const db = await openDb();
  if (db) {
    await tx(db, 'readwrite', (s) => s.put(value, key));
    try {
      localStorage.removeItem(key); // старая копия из localStorage больше не нужна
    } catch {
      /* ignore */
    }
    return;
  }
  localStorage.setItem(key, value);
}

export async function kvGet(key: string): Promise<string | null> {
  const db = await openDb();
  if (db) {
    const v = await tx<string | undefined>(db, 'readonly', (s) => s.get(key));
    if (v != null) return v;
  }
  try {
    return localStorage.getItem(key); // сохранения прежних версий
  } catch {
    return null;
  }
}

export async function kvDelete(key: string): Promise<void> {
  const db = await openDb();
  if (db) await tx(db, 'readwrite', (s) => s.delete(key));
  try {
    localStorage.removeItem(key);
  } catch {
    /* ignore */
  }
}
