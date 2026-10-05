import { ContentStore } from '../content/store';
import { FormatRegistry } from '../core/formats';
import { Localization } from '../core/localization';
import { isPlainObject } from '../core/merge';
import type { ModIssue, ModPackage } from './types';

export interface LoadedScript {
  mod: string;
  path: string;
  module: any;
}

export interface LoadResult {
  order: ModPackage[];
  content: ContentStore;
  loc: Localization;
  scripts: LoadedScript[];
  issues: ModIssue[];
}

/**
 * Определяет порядок загрузки: зависимости и load_after раньше,
 * при прочих равных — по priority, затем по id.
 */
export function resolveLoadOrder(packages: ModPackage[], issues: ModIssue[]): ModPackage[] {
  const byId = new Map<string, ModPackage>();
  for (const p of packages) {
    if (byId.has(p.manifest.id)) {
      issues.push({ mod: p.manifest.id, level: 'warning', message: `Мод с id "${p.manifest.id}" найден дважды; используется последний (${p.origin})` });
    }
    byId.set(p.manifest.id, p);
  }
  // Отбрасываем моды с отсутствующими зависимостями (рекурсивно).
  let changed = true;
  while (changed) {
    changed = false;
    for (const [id, p] of byId) {
      const missing = (p.manifest.dependencies ?? []).filter((d) => !byId.has(d));
      if (missing.length) {
        issues.push({ mod: id, level: 'error', message: `Не хватает зависимостей: ${missing.join(', ')} — мод отключён` });
        byId.delete(id);
        changed = true;
      }
    }
  }
  const pkgs = [...byId.values()].sort(
    (a, b) => (a.manifest.priority ?? 0) - (b.manifest.priority ?? 0) || a.manifest.id.localeCompare(b.manifest.id),
  );
  const before = new Map<string, Set<string>>();
  for (const p of pkgs) {
    const deps = new Set<string>();
    for (const d of [...(p.manifest.dependencies ?? []), ...(p.manifest.load_after ?? [])]) if (byId.has(d)) deps.add(d);
    before.set(p.manifest.id, deps);
  }
  const order: ModPackage[] = [];
  const done = new Set<string>();
  while (order.length < pkgs.length) {
    const next = pkgs.find((p) => !done.has(p.manifest.id) && [...before.get(p.manifest.id)!].every((d) => done.has(d)));
    if (!next) {
      const rest = pkgs.filter((p) => !done.has(p.manifest.id));
      issues.push({ level: 'error', message: `Циклическая зависимость между модами: ${rest.map((p) => p.manifest.id).join(', ')}` });
      for (const p of rest) {
        order.push(p);
        done.add(p.manifest.id);
      }
      break;
    }
    order.push(next);
    done.add(next.manifest.id);
  }
  return order;
}

/**
 * Загружает моды: данные сливаются в ContentStore в порядке загрузки,
 * локализация — в Localization, скрипты импортируются (но init вызывается
 * позже, при создании Engine).
 */
export async function loadMods(
  packages: ModPackage[],
  formats: FormatRegistry,
  opts: {
    enabled?: Set<string> | null;
    onProgress?: (msg: string) => void;
    /** Вызывается сразу после импорта скрипта мода — до разбора его данных (например, чтобы зарегистрировать формат). */
    preload?: (pkg: ModPackage, module: any) => void;
  } = {},
): Promise<LoadResult> {
  const issues: ModIssue[] = [];
  const enabled = opts.enabled;
  const active = packages.filter((p) =>
    enabled ? enabled.has(p.manifest.id) : p.manifest.default_enabled !== false,
  );
  const order = resolveLoadOrder(active, issues);
  const content = new ContentStore();
  const loc = new Localization();
  const scripts: LoadedScript[] = [];

  for (const pkg of order) {
    const m = pkg.manifest;
    opts.onProgress?.(`Загрузка мода ${m.id}`);
    let files: string[];
    try {
      files = (await pkg.source.listFiles()).sort();
    } catch (e: any) {
      issues.push({ mod: m.id, level: 'error', message: `Не удалось прочитать файлы: ${e.message}` });
      continue;
    }
    for (const path of m.scripts ?? []) {
      try {
        const module = await pkg.source.importScript(path);
        scripts.push({ mod: m.id, path, module });
        opts.preload?.(pkg, module);
      } catch (e: any) {
        issues.push({ mod: m.id, file: path, level: 'error', message: `Ошибка загрузки скрипта: ${e.message}` });
      }
    }
    const dataDirs = (m.data ?? ['data']).map((d) => d.replace(/\/?$/, '/'));
    const locDir = (m.localization ?? 'localization').replace(/\/?$/, '/');

    for (const file of files) {
      if (!formats.canParse(file)) continue;
      const isData = dataDirs.some((d) => file.startsWith(d));
      const isLoc = file.startsWith(locDir);
      if (!isData && !isLoc) continue;
      let parsed: unknown;
      try {
        parsed = formats.parse(await pkg.source.readText(file), `${m.id}/${file}`);
      } catch (e: any) {
        issues.push({ mod: m.id, file, level: 'error', message: e.message });
        continue;
      }
      if (parsed == null) continue;
      if (isLoc) {
        // localization/ru/whatever.yaml → язык "ru"
        const lang = file.slice(locDir.length).split('/')[0];
        if (!lang || lang.includes('.')) {
          issues.push({ mod: m.id, file, level: 'warning', message: 'Файл локализации должен лежать в папке языка, например localization/ru/' });
          continue;
        }
        loc.add(lang, parsed);
        continue;
      }
      if (!isPlainObject(parsed)) {
        issues.push({ mod: m.id, file, level: 'error', message: 'Файл данных должен быть словарём «тип контента → записи»' });
        continue;
      }
      for (const [type, section] of Object.entries(parsed)) {
        try {
          content.mergeSection(type, section, m.id);
        } catch (e: any) {
          issues.push({ mod: m.id, file, level: 'error', message: `${type}: ${e.message}` });
        }
      }
    }

  }
  return { order, content, loc, scripts, issues };
}
