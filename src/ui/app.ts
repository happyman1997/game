/**
 * Браузерное приложение: экраны меню, игровой цикл, панели и окна.
 * Состояние игры живёт в Game (движок); UI только читает его и вызывает
 * функции мира в ответ на действия игрока.
 */
import { createDefaultFormats } from '../engine/core/formats';
import { dateParts } from '../engine/core/date';
import { Engine } from '../engine/engine';
import type { Game } from '../engine/game';
import type { ModIssue, ModPackage } from '../engine/mods/types';
import { serializeGame } from '../engine/save';
import { makeContext } from '../engine/script/context';
import { ageOf, charFullName } from '../engine/world/characters';
import { incomeBreakdown, monthlyIncome, monthlyPiety, monthlyPrestige, realmLevy } from '../engine/world/economy';
import { moveArmy } from '../engine/world/military';
import { opinion } from '../engine/world/opinion';
import { provinceController, rankName, titleFullName, topLiege } from '../engine/world/titles';
import { defaultLocaleSources } from '../locale';
import * as world from '../engine/world';
import { bundledPackages } from './bundled';
import { type Child, clear, esc, fmt, h, hideTip, initTooltips, signed } from './dom';
import { registerBuiltinMapModes } from './map/mapModes';
import { type MapHost, MapView } from './map/mapView';
import { openIssues, renderMainMenu } from './screens/menu';
import { renderEventModal, renderRequestModal } from './panels/events';
import { renderCharacterPanel } from './panels/character';
import { renderProvincePanel, renderTitlePanel } from './panels/province';
import { renderArmyPanel, renderMilitaryPanel } from './panels/military';
import { renderWarsPanel } from './panels/wars';
import { renderIntriguePanel } from './panels/intrigue';
import { renderDecisionsPanel } from './panels/decisions';
import { renderRealmPanel } from './panels/realm';
import { renderLogPanel } from './panels/log';
import { breakdownHtml, button, charLink, portrait, titleCoa } from './widgets';
import { exportSave, openLoadDialog, openSaveDialog, quickSaveSlot, writeSave } from './screens/saves';

export type PanelRef =
  | { kind: 'character'; id: string }
  | { kind: 'province'; id: string }
  | { kind: 'title'; id: string }
  | { kind: 'army'; id: string }
  | { kind: 'tab'; id: string };

const SPEED_MS = [Infinity, 700, 300, 120, 40, 8];

export class App implements MapHost {
  engine: Engine | null = null;
  game: Game | null = null;
  packages: ModPackage[] = [];
  folderPackages: ModPackage[] = [];
  enabled: Set<string> | null = null;
  lang = 'ru';
  map!: MapView;
  speed = 2;
  paused = true;
  pickMode = false;
  panel: PanelRef | null = null;
  history: PanelRef[] = [];
  private selectedArmyId: string | null = null;
  private modalStack: HTMLElement[] = [];
  private shownEvent: string | null = null;
  private dirty = true;
  private lastRender = 0;
  private acc = 0;
  private lastFrame = 0;
  private lastYearSaved = -1;
  private seenMessages = 0;

  readonly root: HTMLElement;
  private screen!: HTMLElement;
  private topBar!: HTMLElement;
  private leftPanel!: HTMLElement;
  private bottomBar!: HTMLElement;
  private modesBar!: HTMLElement;
  private rightCol!: HTMLElement;
  private modalLayer!: HTMLElement;
  private toastLayer!: HTMLElement;

  constructor(root: HTMLElement) {
    this.root = root;
    try {
      this.lang = localStorage.getItem('cad.lang') ?? (navigator.language.startsWith('ru') ? 'ru' : 'ru');
      const en = localStorage.getItem('cad.enabledMods');
      if (en) this.enabled = new Set(JSON.parse(en));
    } catch {
      /* localStorage недоступен */
    }
  }

  // ------------------------------------------------------------ локализация

  t(key: string, params?: Record<string, unknown>): string {
    return this.engine ? this.engine.loc.t(key, params) : key;
  }

  // ------------------------------------------------------------ запуск

  async boot() {
    initTooltips();
    this.showLoading('…');
    this.packages = await bundledPackages();
    await this.buildEngine();
    this.showMainMenu();
    this.bindKeys();
    requestAnimationFrame((t) => this.frame(t));
  }

  allPackages(): ModPackage[] {
    const ids = new Set(this.folderPackages.map((p) => p.manifest.id));
    return [...this.packages.filter((p) => !ids.has(p.manifest.id)), ...this.folderPackages];
  }

  async buildEngine() {
    const formats = createDefaultFormats();
    const defaults: Record<string, unknown[]> = {};
    for (const [lang, files] of Object.entries(defaultLocaleSources())) {
      defaults[lang] = files.map((f) => formats.parse(f.text, f.path));
    }
    this.engine = await Engine.create(this.allPackages(), {
      enabled: this.enabled,
      lang: this.lang,
      defaultLocalization: defaults,
      onProgress: (m) => this.showLoading(m),
    });
    registerBuiltinMapModes(this.engine);
    this.engine.hooks.onError = (err, hook, owner) => {
      console.error(err);
      this.engine?.reportIssue({ level: 'error', mod: owner, message: `Хук ${hook}: ${(err as Error)?.message ?? err}` });
    };
    (window as any).CAD = { app: this, engine: this.engine, world };
  }

  setEnabledMods(ids: Set<string> | null) {
    this.enabled = ids;
    try {
      if (ids) localStorage.setItem('cad.enabledMods', JSON.stringify([...ids]));
      else localStorage.removeItem('cad.enabledMods');
    } catch {
      /* ignore */
    }
  }

  setLanguage(lang: string) {
    this.lang = lang;
    try {
      localStorage.setItem('cad.lang', lang);
    } catch {
      /* ignore */
    }
    if (this.engine) this.engine.loc.lang = lang;
    this.map?.invalidate();
    this.markDirty();
  }

  issues(): ModIssue[] {
    return this.engine?.issues ?? [];
  }

  // ------------------------------------------------------------ экраны

  private setScreen(el: HTMLElement) {
    clear(this.root);
    this.root.appendChild(el);
    this.screen = el;
  }

  showLoading(msg: string) {
    if (this.screen?.classList.contains('loading-screen')) {
      this.screen.querySelector('.loading-msg')!.textContent = msg;
      return;
    }
    this.setScreen(h('div', { class: 'loading-screen' }, h('div', { class: 'loading-title' }, 'Корона и Династия'), h('div', { class: 'loading-msg' }, msg)));
  }

  showMainMenu() {
    this.game = null;
    this.paused = true;
    this.modalStack = [];
    this.setScreen(renderMainMenu(this));
  }

  /** Новая партия: если playerId не указан — режим выбора персонажа на карте. */
  startNewGame(bookmark: string, playerId?: string) {
    this.showLoading(this.t('ui.generating_world'));
    setTimeout(() => {
      const game = this.engine!.newGame(bookmark);
      this.enterGame(game);
      if (playerId) this.setPlayer(playerId);
      else {
        this.pickMode = true;
        this.openTab('pick');
      }
    }, 20);
  }

  setPlayer(id: string) {
    const g = this.game!;
    g.state.player = id;
    g.state.playerDynasty = g.char(id)?.dynasty;
    this.pickMode = false;
    g.emit('player.selected', { character: id });
    g.onAction('on_player_start', { type: 'character', id });
    const cap = g.char(id)?.capital;
    if (cap) this.map.focus(cap, Math.max(this.map.zoom, 1.6));
    this.openCharacter(id);
    this.markDirty();
  }

  enterGame(game: Game) {
    this.game = game;
    this.paused = true;
    this.panel = null;
    this.history = [];
    this.selectedArmyId = null;
    this.shownEvent = null;
    this.seenMessages = game.state.messages.length;
    this.lastYearSaved = dateParts(game.date).y;
    const screen = h('div', { class: 'game-screen' });
    const mapWrap = h('div', { class: 'map-wrap' });
    this.topBar = h('div', { class: 'topbar' });
    this.leftPanel = h('div', { class: 'left-panel hidden' });
    this.bottomBar = h('div', { class: 'bottombar' });
    this.modesBar = h('div', { class: 'modesbar' });
    this.rightCol = h('div', { class: 'right-col' });
    this.modalLayer = h('div', { class: 'modal-layer' });
    this.toastLayer = h('div', { class: 'toast-layer' });
    screen.append(mapWrap, this.topBar, this.leftPanel, this.bottomBar, this.modesBar, this.rightCol, this.modalLayer, this.toastLayer);
    this.setScreen(screen);
    this.map = new MapView(this, mapWrap);
    this.map.setGame(game);
    game.listeners.add((kind) => {
      if (kind === 'event' || kind === 'army') this.markDirty(true);
      else this.markDirty();
    });
    this.markDirty(true);
  }

  // ------------------------------------------------------------ цикл

  markDirty(now = false) {
    this.dirty = true;
    if (now) this.lastRender = 0;
  }

  private blockingPending(): boolean {
    const g = this.game;
    if (!g) return true;
    return g.state.pendingEvents.length > 0 || g.state.pendingRequests.length > 0 || !!g.state.gameOver || this.pickMode || this.modalStack.length > 0;
  }

  private frame(t: number) {
    requestAnimationFrame((tt) => this.frame(tt));
    const dt = this.lastFrame ? Math.min(250, t - this.lastFrame) : 0;
    this.lastFrame = t;
    const g = this.game;
    if (!g || !this.map) return;
    if (!this.paused && !this.blockingPending()) {
      this.acc += dt;
      const ms = SPEED_MS[this.speed];
      let n = 0;
      while (this.acc >= ms && n < 25 && !this.blockingPending()) {
        this.acc -= ms;
        g.tick();
        n++;
        this.autosave();
      }
      if (n >= 25) this.acc = 0;
    } else this.acc = 0;
    this.map.draw();
    if (this.dirty && t - this.lastRender > (this.paused ? 30 : 250)) {
      this.dirty = false;
      this.lastRender = t;
      this.render();
    }
  }

  private autosave() {
    const g = this.game!;
    const { y, m, d } = dateParts(g.date);
    if (m === 1 && d === 1 && y !== this.lastYearSaved && g.state.player) {
      this.lastYearSaved = y;
      try {
        writeSave(this, 'autosave', serializeGame(g));
      } catch (e) {
        console.warn('Автосохранение не удалось', e);
      }
    }
  }

  togglePause() {
    this.paused = !this.paused;
    this.markDirty(true);
  }

  setSpeed(s: number) {
    this.speed = Math.max(1, Math.min(5, s));
    this.markDirty(true);
  }

  private bindKeys() {
    window.addEventListener('keydown', (e) => {
      if (!this.game || (e.target as HTMLElement)?.tagName === 'INPUT') return;
      if (e.code === 'Space') {
        e.preventDefault();
        this.togglePause();
      } else if (e.key >= '1' && e.key <= '5') this.setSpeed(Number(e.key));
      else if (e.key === 'Escape') {
        if (this.modalStack.length) this.closeModal();
        else this.closePanel();
      } else if (e.key === 'F5') {
        e.preventDefault();
        this.quickSave();
      }
    });
  }

  quickSave() {
    if (!this.game) return;
    try {
      writeSave(this, quickSaveSlot(), serializeGame(this.game));
      this.toast(this.t('ui.saved'));
    } catch (e) {
      this.toast(`${this.t('ui.save_failed')}: ${(e as Error).message}`, 'bad');
    }
  }

  // ------------------------------------------------------------ панели

  private pushHistory() {
    if (this.panel) {
      this.history.push(this.panel);
      if (this.history.length > 30) this.history.shift();
    }
  }

  openPanel(p: PanelRef) {
    if (this.panel && this.panel.kind === p.kind && this.panel.id === p.id) return this.markDirty(true);
    this.pushHistory();
    this.panel = p;
    this.markDirty(true);
  }

  openCharacter(id: string) {
    this.openPanel({ kind: 'character', id });
  }
  openProvince(id: string, focus = false) {
    if (focus) this.map.focus(id);
    this.openPanel({ kind: 'province', id });
  }
  openTitle(id: string) {
    this.openPanel({ kind: 'title', id });
  }
  openTab(id: string) {
    if (this.panel?.kind === 'tab' && this.panel.id === id) return this.closePanel();
    this.openPanel({ kind: 'tab', id });
  }
  closePanel() {
    this.panel = null;
    this.history = [];
    this.markDirty(true);
  }
  back() {
    this.panel = this.history.pop() ?? null;
    this.markDirty(true);
  }

  // MapHost
  selectProvince(id: string) {
    this.selectedArmyId = null;
    this.openProvince(id);
  }
  selectArmy(id: string) {
    this.selectedArmyId = id;
    this.openPanel({ kind: 'army', id });
  }
  selectedArmy(): string | null {
    const g = this.game;
    if (!g || !this.selectedArmyId || !g.state.armies[this.selectedArmyId]) return null;
    return this.selectedArmyId;
  }
  selectedProvince(): string | null {
    return this.panel?.kind === 'province' ? this.panel.id : null;
  }
  moveSelectedArmy(dest: string) {
    const g = this.game!;
    const id = this.selectedArmy();
    if (!id) return;
    const a = g.state.armies[id];
    if (!g.isPlayer(a.owner)) return;
    if (!moveArmy(g, id, dest)) this.toast(this.t('ui.no_path'), 'bad');
    this.markDirty(true);
  }

  provinceTooltip(id: string): string {
    const g = this.game!;
    const def = g.content.get('provinces', id);
    if (!def) return '';
    if (def.impassable) return `<div class="tip-title">${esc(g.nameOf('provinces', id))}</div><div class="muted">${esc(this.t('ui.impassable'))}</div>`;
    const holder = g.char(g.state.titles[id]?.holder);
    const ctrl = provinceController(g, id);
    const parts = [`<div class="tip-title">${esc(titleFullName(g, id))}</div>`];
    if (holder) {
      parts.push(`<div>${esc(charFullName(g, holder, true))}</div>`);
      const top = topLiege(g, holder);
      if (top.id !== holder.id) parts.push(`<div class="muted">${esc(this.t('ui.realm_of', { name: titleFullName(g, top.titles[0]) }))}</div>`);
    }
    if (ctrl && holder && ctrl.id !== holder.id) parts.push(`<div class="bad">${esc(this.t('ui.occupied_by', { who: charFullName(g, ctrl, true) }))}</div>`);
    const spec = g.engine.ui.mapModes.get(this.map.mode);
    const extra = spec?.tooltip?.(g, id);
    if (extra) parts.push(`<div class="muted">${esc(String(extra))}</div>`);
    return parts.join('');
  }

  characterTooltip(id: string): string {
    const g = this.game!;
    const c = g.char(id);
    if (!c) return '';
    const parts = [`<div class="tip-title">${esc(charFullName(g, c, true))}</div>`];
    if (c.titles[0]) parts.push(`<div>${esc(titleFullName(g, c.titles[0]))}</div>`);
    parts.push(`<div class="muted">${esc(this.t('ui.age_n', { n: ageOf(g, c) }))}${c.death !== undefined ? ' ✝' : ''}</div>`);
    const p = g.player;
    if (p && p.id !== c.id && c.death === undefined) parts.push(`<div>${esc(this.t('ui.opinion_of_you'))}: ${signed(opinion(g, c, p))}</div>`);
    return parts.join('');
  }

  // ------------------------------------------------------------ модальные окна

  modal(content: HTMLElement, opts: { cls?: string; closable?: boolean } = {}): () => void {
    const wrap = h('div', { class: `modal ${opts.cls ?? ''}` }, content);
    const backdrop = h('div', { class: 'modal-backdrop' }, wrap);
    if (opts.closable !== false) {
      backdrop.addEventListener('mousedown', (e) => {
        if (e.target === backdrop) this.closeModal();
      });
    }
    this.modalLayer.appendChild(backdrop);
    this.modalStack.push(backdrop);
    hideTip();
    return () => {
      backdrop.remove();
      this.modalStack = this.modalStack.filter((m) => m !== backdrop);
      this.markDirty(true);
    };
  }

  closeModal() {
    const m = this.modalStack.pop();
    m?.remove();
    this.markDirty(true);
  }

  toast(text: string, kind: 'good' | 'bad' | 'info' = 'info') {
    if (!this.toastLayer) return;
    const el = h('div', { class: `toast ${kind}` }, text);
    this.toastLayer.appendChild(el);
    setTimeout(() => el.classList.add('fade'), 3500);
    setTimeout(() => el.remove(), 4200);
  }

  // ------------------------------------------------------------ отрисовка

  render() {
    const g = this.game;
    if (!g) return;
    this.renderTopBar();
    this.renderBottomBar();
    this.renderModes();
    this.renderRightCol();
    this.renderLeftPanel();
    this.renderPending();
  }

  private renderPending() {
    const g = this.game!;
    if (g.state.gameOver && !this.modalStack.length) {
      this.modal(
        h('div', { class: 'gameover' },
          h('h2', null, this.t('ui.game_over')),
          h('p', null, this.t(`ui.game_over_${g.state.gameOver.reason}`)),
          button(this.t('ui.main_menu'), () => this.showMainMenu())),
        { closable: false },
      );
      return;
    }
    if (this.modalStack.length) return;
    const ev = g.state.pendingEvents[0];
    if (ev && this.shownEvent !== ev.uid) {
      this.shownEvent = ev.uid;
      const close = this.modal(renderEventModal(this, ev, () => {
        close();
        this.shownEvent = null;
      }), { cls: 'event-modal', closable: false });
      return;
    }
    const rq = g.state.pendingRequests[0];
    if (rq && !ev) {
      const close = this.modal(renderRequestModal(this, rq, () => close()), { cls: 'event-modal', closable: false });
    }
  }

  private renderTopBar() {
    const g = this.game!;
    const p = g.player;
    clear(this.topBar);
    const left = h('div', { class: 'tb-left' });
    if (p) {
      const income = monthlyIncome(g, p);
      left.append(
        h('div', { class: 'tb-portrait' }, portrait(this, p, 46)),
        h('div', { class: 'tb-name' },
          h('div', { class: 'tb-title' }, titleCoa(this, p.titles[0], 22), charFullName(g, p, true)),
          h('div', { class: 'tb-res' },
            h('span', { class: 'res', tip: () => `<div class="tip-title">${esc(this.t('ui.gold'))}</div>${breakdownHtml(incomeBreakdown(g, p), 1)}` }, `💰 ${fmt(p.gold)} `, h('small', { class: income >= 0 ? 'good' : 'bad' }, `(${signed(income, 1)})`)),
            h('span', { class: 'res', tip: this.t('ui.prestige') }, `⭐ ${fmt(p.prestige)} `, h('small', null, `(${signed(monthlyPrestige(g, p), 1)})`)),
            h('span', { class: 'res', tip: this.t('ui.piety') }, `✝ ${fmt(p.piety)} `, h('small', null, `(${signed(monthlyPiety(g, p), 1)})`)),
            h('span', { class: 'res', tip: this.t('ui.levies') }, `⚔ ${fmt(realmLevy(g, p))}`),
            p.stress > 0 ? h('span', { class: ['res', p.stress >= 100 && 'bad'], tip: this.t('ui.stress') }, `😣 ${fmt(p.stress)}`) : null,
            ...g.engine.ui.topBar.values().sort((a, b) => (a.order ?? 0) - (b.order ?? 0)).map((w) => {
              const r = safe(() => w.render(g));
              return r ? h('span', { class: 'res', tip: r.tooltip }, `${r.icon ?? ''} ${r.text}`) : null;
            }),
          ),
        ),
      );
    } else {
      left.append(h('div', { class: 'tb-pick' }, this.t('ui.pick_character_hint')));
    }
    const { y, m, d } = dateParts(g.date);
    const right = h('div', { class: 'tb-right' },
      h('div', { class: 'tb-date', tip: this.t('ui.speed_hint') }, `${d} ${this.t(`month.${m}`)} ${y}`),
      h('div', { class: 'speed' },
        button(this.paused ? '▶' : '⏸', () => this.togglePause(), { cls: ['speed-btn', this.paused && 'paused'].filter(Boolean).join(' '), tip: this.t('ui.pause_hint') }),
        ...[1, 2, 3, 4, 5].map((s) => button('›', () => { this.setSpeed(s); if (this.paused) this.togglePause(); }, { cls: `speed-dot ${s <= this.speed ? 'on' : ''}`, tip: this.t('ui.speed_n', { n: s }) })),
      ),
      button('☰', () => this.openGameMenu(), { cls: 'menu-btn', tip: this.t('ui.menu') }),
    );
    this.topBar.append(left, right);
  }

  private tabs(): { id: string; icon: string; name: string }[] {
    const g = this.game!;
    const list = [
      { id: 'me', icon: '👤', name: this.t('ui.tab.character') },
      { id: 'realm', icon: '🏰', name: this.t('ui.tab.realm') },
      { id: 'military', icon: '⚔', name: this.t('ui.tab.military') },
      { id: 'wars', icon: '🔥', name: this.t('ui.tab.wars') },
      { id: 'intrigue', icon: '🗡', name: this.t('ui.tab.intrigue') },
      { id: 'decisions', icon: '📜', name: this.t('ui.tab.decisions') },
      { id: 'log', icon: '📖', name: this.t('ui.tab.log') },
    ];
    for (const p of g.engine.ui.panels.values().sort((a, b) => (a.order ?? 0) - (b.order ?? 0))) {
      list.push({ id: `mod:${p.id}`, icon: p.icon, name: g.loc.resolve(p.name) });
    }
    return list;
  }

  private renderBottomBar() {
    clear(this.bottomBar);
    if (!this.game!.player) return;
    for (const t of this.tabs()) {
      const active = this.panel?.kind === 'tab' && this.panel.id === t.id;
      this.bottomBar.append(button(h('span', { class: 'tab-icon' }, t.icon), () => (t.id === 'me' ? this.openCharacter(this.game!.player!.id) : this.openTab(t.id)), { cls: `tab-btn ${active ? 'active' : ''}`, tip: t.name }));
    }
  }

  private renderModes() {
    const g = this.game!;
    clear(this.modesBar);
    for (const m of g.engine.ui.mapModes.values().sort((a, b) => (a.order ?? 0) - (b.order ?? 0))) {
      this.modesBar.append(button(m.icon ?? '🗺', () => { this.map.setMode(m.id); this.markDirty(true); }, { cls: `mode-btn ${this.map.mode === m.id ? 'active' : ''}`, tip: g.loc.resolve(m.name) }));
    }
  }

  private renderRightCol() {
    const g = this.game!;
    clear(this.rightCol);
    const p = g.player;
    if (p) {
      const armies = Object.values(g.state.armies).filter((a) => a.owner === p.id);
      const wars = Object.values(g.state.wars).filter((w) => w.attackers.includes(p.id) || w.defenders.includes(p.id));
      const schemes = Object.values(g.state.schemes).filter((s) => s.owner === p.id);
      const out = h('div', { class: 'outliner' });
      if (wars.length) out.append(h('div', { class: 'ol-head' }, this.t('ui.tab.wars')), ...wars.map((w) => h('div', { class: 'ol-item', onclick: () => this.openTab('wars') }, '🔥 ', w.name ?? '')));
      if (armies.length) out.append(h('div', { class: 'ol-head' }, this.t('ui.armies')), ...armies.map((a) => h('div', { class: ['ol-item', this.selectedArmyId === a.id && 'active'], onclick: () => { this.selectArmy(a.id); this.map.focus(a.location); } }, `⚔ ${fmt(a.size)} — ${g.nameOf('provinces', a.location)}${a.path.length ? ' →' : ''}`)));
      if (schemes.length) out.append(h('div', { class: 'ol-head' }, this.t('ui.tab.intrigue')), ...schemes.map((s) => h('div', { class: 'ol-item', onclick: () => this.openTab('intrigue') }, `${g.content.get('schemes', s.type)?.icon ?? '🗡'} ${g.nameOf('schemes', s.type)}: ${Math.floor(s.progress)}%`)));
      if (out.children.length) this.rightCol.append(out);
    }
    const msgs = g.state.messages.slice(-8).reverse();
    const fresh = g.state.messages.length - this.seenMessages;
    this.seenMessages = g.state.messages.length;
    const log = h('div', { class: 'msglog' });
    msgs.forEach((m, i) => {
      const { y, m: mo, d } = dateParts(m.date);
      log.append(h('div', {
        class: ['msg', `msg-${m.kind}`, i < fresh && 'fresh'],
        onclick: () => {
          if (!m.ref) return;
          if (m.ref.type === 'character') this.openCharacter(m.ref.id);
          else if (m.ref.type === 'province') this.openProvince(m.ref.id, true);
          else if (m.ref.type === 'title') this.openTitle(m.ref.id);
          else if (m.ref.type === 'war') this.openTab('wars');
        },
      }, h('span', { class: 'msg-date' }, `${d}.${mo}.${y}`), ' ', m.text));
    });
    if (msgs.length) this.rightCol.append(log);
  }

  private renderLeftPanel() {
    const g = this.game!;
    const lp = this.leftPanel;
    const scroll = lp.querySelector('.panel-body')?.scrollTop ?? 0;
    const prevKey = lp.dataset.key;
    clear(lp);
    if (!this.panel) {
      lp.classList.add('hidden');
      return;
    }
    lp.classList.remove('hidden');
    let body: Child = null;
    let title: Child = '';
    const p = this.panel;
    try {
      if (p.kind === 'character') [title, body] = [this.t('ui.tab.character'), renderCharacterPanel(this, p.id)];
      else if (p.kind === 'province') [title, body] = [this.t('ui.province'), renderProvincePanel(this, p.id)];
      else if (p.kind === 'title') [title, body] = [this.t('ui.title'), renderTitlePanel(this, p.id)];
      else if (p.kind === 'army') [title, body] = [this.t('ui.army'), renderArmyPanel(this, p.id)];
      else if (p.kind === 'tab') {
        const tab = this.tabs().find((t) => t.id === p.id);
        title = tab?.name ?? '';
        switch (p.id) {
          case 'pick': title = this.t('ui.pick_title'); body = this.renderPickPanel(); break;
          case 'realm': body = renderRealmPanel(this); break;
          case 'military': body = renderMilitaryPanel(this); break;
          case 'wars': body = renderWarsPanel(this); break;
          case 'intrigue': body = renderIntriguePanel(this); break;
          case 'decisions': body = renderDecisionsPanel(this); break;
          case 'log': body = renderLogPanel(this); break;
          default:
            if (p.id.startsWith('mod:')) {
              const spec = g.engine.ui.panels.get(p.id.slice(4));
              const r = spec ? safe(() => spec.render(g, this)) : null;
              body = typeof r === 'string' ? h('div', { html: r }) : (r as Node | null);
            }
        }
      }
    } catch (e) {
      console.error(e);
      body = h('div', { class: 'bad' }, String((e as Error).message ?? e));
    }
    lp.append(
      h('div', { class: 'panel-head' },
        this.history.length ? button('←', () => this.back(), { cls: 'icon-btn', tip: this.t('ui.back') }) : h('span'),
        h('div', { class: 'panel-title' }, title),
        button('✕', () => this.closePanel(), { cls: 'icon-btn', tip: this.t('ui.close') }),
      ),
      h('div', { class: 'panel-body' }, body),
    );
    const key = `${p.kind}:${p.id}`;
    lp.dataset.key = key;
    if (prevKey === key) lp.querySelector('.panel-body')!.scrollTop = scroll;
  }

  private renderPickPanel(): HTMLElement {
    const g = this.game!;
    const bm = g.content.get('bookmarks', g.state.bookmark);
    const list = h('div', { class: 'pick-list' });
    for (const id of bm?.playable ?? []) {
      const c = g.char(id);
      if (!c || c.death !== undefined) continue;
      list.append(h('div', { class: 'pick-item', onclick: () => this.openCharacter(id) }, portrait(this, c, 40, false), h('div', null, h('div', { class: 'pick-name' }, charFullName(g, c, true)), h('div', { class: 'muted' }, c.titles[0] ? titleFullName(g, c.titles[0]) : ''))));
    }
    return h('div', null, h('p', null, this.t('ui.pick_text')), list);
  }

  openGameMenu() {
    const g = this.game!;
    const wasPaused = this.paused;
    this.paused = true;
    const close = this.modal(
      h('div', { class: 'game-menu' },
        h('h2', null, this.t('ui.menu')),
        button(this.t('ui.resume'), () => { close(); this.paused = wasPaused; }),
        button(this.t('ui.save_game'), () => { close(); openSaveDialog(this); }, { disabled: !g.state.player }),
        button(this.t('ui.load_game'), () => { close(); openLoadDialog(this); }),
        button(this.t('ui.export_save'), () => exportSave(this)),
        button(this.lang === 'ru' ? 'English' : 'Русский', () => { this.setLanguage(this.lang === 'ru' ? 'en' : 'ru'); close(); }),
        button(this.t('ui.mod_issues'), () => { close(); openIssues(this); }),
        button(this.t('ui.main_menu'), () => { close(); this.showMainMenu(); }),
      ),
    );
  }

  /** Короткий ранг + имя для списков. */
  rankedName(id: string): string {
    const g = this.game!;
    const c = g.char(id);
    if (!c) return '?';
    return c.titles.length ? `${rankName(g, c)} ${charFullName(g, c, false)}` : charFullName(g, c, false);
  }

  context(rootId: string) {
    return makeContext(this.game!, { type: 'character', id: rootId });
  }

  charLink(id: string) {
    return charLink(this, id);
  }
}

function safe<T>(fn: () => T): T | null {
  try {
    return fn();
  } catch (e) {
    console.error(e);
    return null;
  }
}
