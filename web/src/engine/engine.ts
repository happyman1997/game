import type { ModManifest } from './mods/types';
import { createModApi } from './api';
import { normalizeContent } from './content/normalize';
import type { ContentStore } from './content/store';
import { validateContent } from './content/validate';
import { type ContentValidator, type EngineFeature, builtinFeatures } from './features';
import { createDefaultFormats } from './core/formats';
import { HookBus } from './core/hooks';
import type { Localization } from './core/localization';
import { Registry } from './core/registry';
import type { Game } from './game';
import { type MapData, buildMap, emptyMap } from './map/build';
import { loadMods } from './mods/loader';
import type { ModIssue, ModPackage } from './mods/types';
import { deserializeGame } from './save';
import { registerBuiltins, registerSkillValues } from './script/builtins';
import { ScriptRegistry } from './script/registry';
import { type GameSystem, builtinSystems } from './systems/core';
import { UIRegistry } from './uiRegistry';
import type { InteractionDecider, InteractionTargetProvider } from './world/interactions';
import { type OpinionProvider, builtinOpinionProviders } from './world/opinion';
import { setupNewGame } from './world/setup';
import { type ModifierProvider, type ProvinceModifierProvider, buildingOwnerProvider, stressProvider } from './world/stats';
import { type SuccessionAlgorithm, builtinSuccessionAlgorithms } from './world/succession';
import { type CbTargetProvider, builtinCbTargets } from './world/war';
import { domainCounties, titleFullName } from './world/titles';

export interface EngineOptions {
  /** Включённые моды; null — все с default_enabled != false. */
  enabled?: Set<string> | null;
  lang?: string;
  onProgress?: (msg: string) => void;
  /** Встроенные строки движка и интерфейса: { ru: {...}, en: {...} }. Моды могут их переопределять. */
  defaultLocalization?: Record<string, unknown[]>;
}

/**
 * Движок: загруженные моды, контент, реестры. Не зависит от конкретной
 * партии — партии (Game) создаются через newGame/loadGame.
 */
export class Engine {
  readonly formats = createDefaultFormats();
  readonly script = new ScriptRegistry();
  readonly hooks = new HookBus();
  readonly systems = new Registry<GameSystem>('система');
  readonly ui = new UIRegistry();
  readonly registries = {
    successionAlgorithms: new Registry<SuccessionAlgorithm>('алгоритм наследования'),
    cbTargets: new Registry<CbTargetProvider>('поставщик целей войны'),
    interactionTargets: new Registry<InteractionTargetProvider>('поставщик целей взаимодействия'),
    interactionDeciders: new Registry<InteractionDecider>('решающий во взаимодействии'),
    modifierProviders: new Registry<ModifierProvider>('поставщик модификаторов'),
    provinceModifierProviders: new Registry<ProvinceModifierProvider>('поставщик модификаторов провинции'),
    opinionProviders: new Registry<OpinionProvider>('поставщик мнения'),
    contentValidators: new Registry<ContentValidator>('проверка контента'),
  };
  /** Механики (образ жизни, совет, темница, фракции, отряды). */
  readonly features = new Registry<EngineFeature>('механика');
  /** Включённые (установленные) механики. */
  readonly installedFeatures = new Set<string>();

  hasFeature(id: string): boolean {
    return this.installedFeatures.has(id);
  }
  content!: ContentStore;
  loc!: Localization;
  mods: ModPackage[] = [];
  issues: ModIssue[] = [];
  /** Кэш производных данных контента (не состояния партии). */
  readonly cache = new Map<string, unknown>();
  private _map?: MapData;
  private _children?: Map<string, string[]>;
  private issueListeners = new Set<(i: ModIssue) => void>();

  static async create(packages: ModPackage[], opts: EngineOptions = {}): Promise<Engine> {
    const e = new Engine();
    const res = await loadMods(packages, e.formats, {
      enabled: opts.enabled,
      onProgress: opts.onProgress,
      preload: (pkg, module) => {
        const fn = module?.preload ?? module?.default?.preload;
        if (typeof fn === 'function') fn({ mod: pkg.manifest, formats: e.formats });
      },
    });
    e.content = res.content;
    e.loc = res.loc;
    e.mods = res.order;
    e.issues.push(...res.issues);
    if (opts.lang) e.loc.lang = opts.lang;
    for (const [lang, docs] of Object.entries(opts.defaultLocalization ?? {})) for (const d of docs) e.loc.addDefaults(lang, d);

    normalizeContent(e.content);
    registerBuiltins(e);
    registerSkillValues(e);
    e.registerDefaults();
    const disabled = new Set<string>(e.content.singleton('defines').disabled_features ?? []);
    for (const f of builtinFeatures) {
      e.features.register(f.id, f, 'core');
      f.script?.(e);
      if (!disabled.has(f.id)) {
        f.install(e);
        e.installedFeatures.add(f.id);
      }
    }
    // Записи, требующие отключённой механики, убираются из контента.
    for (const type of e.content.types()) {
      for (const id of e.content.ids(type)) {
        const req = e.content.get(type, id)?.requires_feature;
        if (req && [].concat(req).some((x: string) => !e.installedFeatures.has(x))) e.content.delete(type, id);
      }
    }

    for (const s of res.scripts) {
      const m = s.module;
      const init = m?.init ?? m?.default?.init ?? (typeof m?.default === 'function' ? m.default : undefined);
      if (typeof init !== 'function') continue;
      const manifest = e.mods.find((p) => p.manifest.id === s.mod)?.manifest as ModManifest;
      try {
        opts.onProgress?.(`Инициализация ${s.mod}/${s.path}`);
        await init(createModApi(e, manifest));
      } catch (err: any) {
        e.issues.push({ mod: s.mod, file: s.path, level: 'error', message: `init(): ${err?.message ?? err}` });
        console.error(err);
      }
    }
    e.issues.push(...validateContent(e));
    e.hooks.emit('engine.ready', { engine: e });
    return e;
  }

  private registerDefaults() {
    for (const s of builtinSystems) this.systems.register(s.id, s, 'core');
    for (const [id, a] of Object.entries(builtinSuccessionAlgorithms)) this.registries.successionAlgorithms.register(id, a, 'core');
    for (const [id, p] of Object.entries(builtinCbTargets)) this.registries.cbTargets.register(id, p, 'core');
    for (const [id, fn] of Object.entries(builtinOpinionProviders)) this.registries.opinionProviders.register(id, { fn }, 'core');
    this.registries.modifierProviders.register('buildings', { label: 'modsrc.buildings', fn: buildingOwnerProvider }, 'core');
    this.registries.modifierProviders.register('stress', { label: 'modsrc.stress', fn: stressProvider }, 'core');

    this.registries.interactionTargets.register('grantable_titles', {
      options: (game, actor) => {
        const cap = actor.capital;
        const counties = domainCounties(game, actor).filter((c) => c !== cap);
        const duchies = actor.titles.filter((t) => game.content.get('titles', t)?.tier === 'duchy' && t !== actor.titles[0]);
        return [...duchies, ...counties].map((id) => ({ id, label: titleFullName(game, id), ref: { type: 'title' as const, id } }));
      },
    }, 'core');
    this.registries.interactionTargets.register('revocable_titles', {
      options: (game, actor, recipient) =>
        recipient.liege === actor.id
          ? recipient.titles.map((id) => ({ id, label: titleFullName(game, id), ref: { type: 'title' as const, id } }))
          : [],
    }, 'core');
    this.registries.interactionTargets.register('recipient_claims', {
      options: (game, actor, recipient) =>
        recipient.titles.filter((t) => !actor.claims.includes(t)).map((id) => ({ id, label: titleFullName(game, id), ref: { type: 'title' as const, id } })),
    }, 'core');

    this.ui.eventThemes.register('default', { icon: '📜', color: '#8a6d3b' });
  }

  // ------------------------------------------------------------ карта и иерархия

  get map(): MapData {
    if (!this._map) this._map = this.content.all('provinces').length ? buildMap(this.content) : emptyMap();
    return this._map;
  }

  /** Сбрасывает карту (например, если мод изменил провинции из скрипта). */
  invalidateMap(): void {
    this._map = undefined;
    this._paths = undefined;
    this._dist.clear();
    this.cache.clear();
  }

  deJureChildren(): Map<string, string[]> {
    if (!this._children) {
      const m = new Map<string, string[]>();
      for (const t of this.content.all('titles')) {
        if (!t.liege) continue;
        const l = m.get(t.liege) ?? [];
        l.push(t.id);
        m.set(t.liege, l);
      }
      this._children = m;
    }
    return this._children;
  }

  neighbors(provId: string): string[] {
    return this.map.neighbors.get(provId) ?? [];
  }

  private _paths?: { index: Map<string, number>; ids: string[]; dist: Float32Array; next: Int16Array };

  /**
   * Таблица кратчайших путей между всеми провинциями (с учётом местности).
   * Считается один раз: контент после загрузки не меняется.
   */
  pathTable() {
    if (this._paths) return this._paths;
    const m = this.map;
    const ids = m.provinces;
    const n = ids.length;
    const index = m.index;
    const dist = new Float32Array(n * n).fill(Infinity);
    const next = new Int16Array(n * n).fill(-1);
    const moveCost = (to: string) => this.content.get('terrain', this.content.get('provinces', to)?.terrain ?? '')?.movement ?? 1;
    const adj: { j: number; w: number }[][] = ids.map((a) =>
      (m.neighbors.get(a) ?? []).map((b) => ({ j: index.get(b)!, w: this.distance(a, b) * moveCost(b) })),
    );
    const d = new Float64Array(n);
    const first = new Int16Array(n);
    const done = new Uint8Array(n);
    for (let s = 0; s < n; s++) {
      d.fill(Infinity);
      first.fill(-1);
      done.fill(0);
      d[s] = 0;
      for (;;) {
        let u = -1;
        let best = Infinity;
        for (let i = 0; i < n; i++) if (!done[i] && d[i] < best) { best = d[i]; u = i; }
        if (u < 0) break;
        done[u] = 1;
        for (const { j, w } of adj[u]) {
          const nd = best + w;
          if (nd < d[j]) {
            d[j] = nd;
            first[j] = u === s ? j : first[u];
          }
        }
      }
      for (let t = 0; t < n; t++) {
        dist[s * n + t] = d[t];
        next[s * n + t] = first[t];
      }
    }
    this._paths = { index, ids, dist, next };
    return this._paths;
  }

  /** Длина кратчайшего пути (Infinity, если пути нет). */
  pathLength(a: string, b: string): number {
    const t = this.pathTable();
    const i = t.index.get(a);
    const j = t.index.get(b);
    if (i === undefined || j === undefined) return Infinity;
    return t.dist[i * t.ids.length + j];
  }

  private _dist = new Map<string, number>();

  distance(a: string, b: string): number {
    const key = a < b ? `${a}|${b}` : `${b}|${a}`;
    const cached = this._dist.get(key);
    if (cached !== undefined) return cached;
    const v = this.rawDistance(a, b);
    this._dist.set(key, v);
    return v;
  }

  private rawDistance(a: string, b: string): number {
    const m = this.map;
    const i = m.index.get(a);
    const j = m.index.get(b);
    if (i === undefined || j === undefined) return 100;
    return Math.hypot(m.centers[i * 2] - m.centers[j * 2], m.centers[i * 2 + 1] - m.centers[j * 2 + 1]);
  }

  orderedSystems(): GameSystem[] {
    return this.systems.values().sort((a, b) => a.order - b.order);
  }

  // ------------------------------------------------------------ проблемы модов

  reportIssue(i: ModIssue): void {
    this.issues.push(i);
    if (this.issues.length > 500) this.issues.splice(0, this.issues.length - 500);
    for (const l of this.issueListeners) l(i);
    if (i.level === 'error') console.error(i.message);
    else console.warn(i.message);
  }

  onIssue(fn: (i: ModIssue) => void): () => void {
    this.issueListeners.add(fn);
    return () => this.issueListeners.delete(fn);
  }

  // ------------------------------------------------------------ партии

  bookmarks() {
    return this.content.all('bookmarks');
  }

  newGame(bookmarkId: string, seed?: number): Game {
    return setupNewGame(this, bookmarkId, seed);
  }

  loadGame(json: string): { game: Game; warnings: string[] } {
    return deserializeGame(this, json);
  }
}
