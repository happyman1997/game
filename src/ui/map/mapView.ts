/**
 * Отрисовка карты на canvas: растр провинций, раскраска по режиму карты,
 * рельеф (теневой отмыв), границы держав, подписи, армии и осады.
 */
import { hexToRgb } from '../../engine/content/normalize';
import { fbm } from '../../engine/core/noise';
import type { Game } from '../../engine/game';
import type { MapData } from '../../engine/map/build';
import type { MapModeSpec, RGB } from '../../engine/uiRegistry';
import { daysToNext } from '../../engine/world/military';
import { titleShortName, topLiege } from '../../engine/world/titles';
import { participantSide, warsOf } from '../../engine/world/war';
import { hideTip, showFloatingTip } from '../dom';

export interface MapHost {
  game: Game | null;
  selectProvince(id: string): void;
  selectArmy(id: string): void;
  selectedArmy(): string | null;
  moveSelectedArmy(dest: string): void;
  provinceTooltip(id: string): string;
  selectedProvince(): string | null;
}

function toRgb(c: RGB | string | null | undefined): RGB | null {
  if (!c) return null;
  if (Array.isArray(c)) return c;
  if (c.startsWith('#')) return hexToRgb(c);
  return null;
}

export class MapView {
  readonly canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D;
  private base: HTMLCanvasElement;
  private baseCtx: CanvasRenderingContext2D;
  private img!: ImageData;
  private map!: MapData;
  private shade!: Float32Array;
  private sea!: Uint8ClampedArray;
  private borderNb!: Int32Array;
  private bbox!: Int32Array;
  private realmOf: Int32Array = new Int32Array(0);
  private subRealmOf: Int32Array = new Int32Array(0);
  private labels: { text: string; x: number; y: number; size: number }[] = [];
  private highlight: HTMLCanvasElement | null = null;
  private highlightFor = -2;
  private hover = -1;
  private hoverCanvas: HTMLCanvasElement | null = null;
  private hoverFor = -2;
  mode = 'realms';
  zoom = 1;
  ox = 0;
  oy = 0;
  private dragging = false;
  private dragStart: { x: number; y: number; ox: number; oy: number } | null = null;
  private signature = '';
  private dirtyColors = true;
  private game: Game | null = null;

  constructor(
    private host: MapHost,
    container: HTMLElement,
  ) {
    this.canvas = document.createElement('canvas');
    this.canvas.className = 'map-canvas';
    container.appendChild(this.canvas);
    this.ctx = this.canvas.getContext('2d')!;
    this.base = document.createElement('canvas');
    this.baseCtx = this.base.getContext('2d', { willReadFrequently: false })!;
    this.bindEvents();
    window.addEventListener('resize', () => this.resize());
  }

  setGame(game: Game) {
    this.game = game;
    if (this.map !== game.map) {
      this.map = game.map;
      this.precompute();
      this.fit();
    }
    this.dirtyColors = true;
  }

  setMode(mode: string) {
    this.mode = mode;
    this.dirtyColors = true;
  }

  invalidate() {
    this.dirtyColors = true;
  }

  resize() {
    const dpr = window.devicePixelRatio || 1;
    const w = this.canvas.clientWidth;
    const h = this.canvas.clientHeight;
    this.canvas.width = Math.round(w * dpr);
    this.canvas.height = Math.round(h * dpr);
  }

  fit() {
    this.resize();
    const w = this.canvas.clientWidth || 1200;
    const h = this.canvas.clientHeight || 800;
    this.zoom = Math.max(0.3, Math.min(w / this.map.width, h / this.map.height) * 1.05);
    this.ox = this.map.width / 2 - w / 2 / this.zoom;
    this.oy = this.map.height / 2 - h / 2 / this.zoom;
  }

  /** Центрировать карту на провинции. */
  focus(provId: string, zoom?: number) {
    const i = this.map.index.get(provId);
    if (i === undefined) return;
    if (zoom) this.zoom = zoom;
    const w = this.canvas.clientWidth;
    const h = this.canvas.clientHeight;
    this.ox = this.map.centers[i * 2] - w / 2 / this.zoom;
    this.oy = this.map.centers[i * 2 + 1] - h / 2 / this.zoom;
  }

  // ------------------------------------------------------------ предвычисления

  private precompute() {
    const m = this.map;
    const W = m.width;
    const H = m.height;
    const N = W * H;
    this.base.width = W;
    this.base.height = H;
    this.img = this.baseCtx.createImageData(W, H);
    const game = this.game!;
    // высоты по местности, сглаженные
    const tH = new Float32Array(m.provinces.length);
    m.provinces.forEach((p, i) => {
      const terrain = game.content.get('terrain', game.content.get('provinces', p)?.terrain ?? '');
      tH[i] = terrain?.height ?? 0.1;
    });
    let hgt: Float32Array = new Float32Array(N);
    for (let i = 0; i < N; i++) hgt[i] = m.pixels[i] >= 0 ? tH[m.pixels[i]] : -0.05;
    hgt = boxBlur(boxBlur(hgt, W, H, 7), W, H, 7);
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        const i = y * W + x;
        if (m.pixels[i] < 0) continue;
        hgt[i] += (fbm(x / 22, y / 22, 7, 4) - 0.5) * (0.12 + hgt[i] * 0.9) + (fbm(x / 5, y / 5, 11, 2) - 0.5) * 0.04;
      }
    }
    this.shade = new Float32Array(N);
    for (let y = 1; y < H - 1; y++) {
      for (let x = 1; x < W - 1; x++) {
        const i = y * W + x;
        const dx = hgt[i - 1] - hgt[i + 1];
        const dy = hgt[i - W] - hgt[i + W];
        this.shade[i] = Math.max(0.6, Math.min(1.35, 1 + (dx + dy) * 3.2));
      }
    }
    // море: расстояние до берега
    const dist = new Uint8Array(N).fill(255);
    let frontier: number[] = [];
    for (let i = 0; i < N; i++) if (m.pixels[i] >= 0) {
      dist[i] = 0;
      frontier.push(i);
    }
    for (let d = 1; d < 60 && frontier.length; d++) {
      const next: number[] = [];
      for (const p of frontier) {
        const x = p % W;
        for (const q of [x > 0 ? p - 1 : -1, x < W - 1 ? p + 1 : -1, p - W, p + W]) {
          if (q < 0 || q >= N || dist[q] !== 255) continue;
          dist[q] = d;
          next.push(q);
        }
      }
      frontier = next;
    }
    this.sea = new Uint8ClampedArray(N * 3);
    for (let i = 0; i < N; i++) {
      if (m.pixels[i] >= 0) continue;
      const x = i % W;
      const y = (i / W) | 0;
      const t = Math.min(1, dist[i] / 45);
      const n = (fbm(x / 30, y / 30, 3, 3) - 0.5) * 18;
      const wave = dist[i] > 2 && dist[i] < 5 ? 10 : 0;
      this.sea[i * 3] = 70 - 40 * t + n + wave;
      this.sea[i * 3 + 1] = 112 - 52 * t + n + wave;
      this.sea[i * 3 + 2] = 140 - 50 * t + n + wave;
    }
    // соседи на границах и рамки провинций
    this.borderNb = new Int32Array(N).fill(-2);
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        const i = y * W + x;
        const a = m.pixels[i];
        if (a < 0) continue;
        const nbs = [x < W - 1 ? i + 1 : -1, y < H - 1 ? i + W : -1, x > 0 ? i - 1 : -1, y > 0 ? i - W : -1];
        for (const j of nbs) {
          if (j < 0) continue;
          const b = m.pixels[j];
          if (b !== a) {
            this.borderNb[i] = b;
            break;
          }
        }
      }
    }
    const P = m.provinces.length;
    this.bbox = new Int32Array(P * 4);
    for (let p = 0; p < P; p++) {
      this.bbox[p * 4] = W;
      this.bbox[p * 4 + 1] = H;
      this.bbox[p * 4 + 2] = 0;
      this.bbox[p * 4 + 3] = 0;
    }
    for (let i = 0; i < N; i++) {
      const p = m.pixels[i];
      if (p < 0) continue;
      const x = i % W;
      const y = (i / W) | 0;
      const b = p * 4;
      if (x < this.bbox[b]) this.bbox[b] = x;
      if (y < this.bbox[b + 1]) this.bbox[b + 1] = y;
      if (x > this.bbox[b + 2]) this.bbox[b + 2] = x;
      if (y > this.bbox[b + 3]) this.bbox[b + 3] = y;
    }
    this.highlightFor = -2;
    this.hoverFor = -2;
  }

  // ------------------------------------------------------------ раскраска

  private computeSignature(): string {
    const g = this.game!;
    const parts: string[] = [this.mode, g.loc.lang, g.state.player ?? ''];
    for (const p of this.map.provinces) {
      const st = g.state.provinces[p];
      parts.push(`${g.state.titles[p]?.holder ?? ''}:${st?.occupant ?? ''}`);
    }
    // для режимов, зависящих от данных, — раз в месяц
    if (this.mode !== 'realms' && this.mode !== 'culture' && this.mode !== 'faith' && this.mode !== 'terrain') parts.push(String(Math.floor(g.date / 30)));
    parts.push(String(Object.keys(g.state.wars).length));
    return parts.join('|');
  }

  private recolor() {
    const g = this.game!;
    const m = this.map;
    const spec: MapModeSpec | undefined = g.engine.ui.mapModes.get(this.mode) ?? g.engine.ui.mapModes.get('realms');
    const P = m.provinces.length;
    const colors = new Uint8ClampedArray(P * 3);
    const occColors = new Int16Array(P * 3).fill(-1);
    this.realmOf = new Int32Array(P).fill(-1);
    this.subRealmOf = new Int32Array(P).fill(-1);
    const realmIds = new Map<string, number>();
    const subIds = new Map<string, number>();
    for (let p = 0; p < P; p++) {
      const id = m.provinces[p];
      if (m.impassable[p]) {
        colors.set([92, 88, 80], p * 3);
        continue;
      }
      const holder = g.char(g.state.titles[id]?.holder);
      if (holder) {
        const top = topLiege(g, holder);
        if (!realmIds.has(top.id)) realmIds.set(top.id, realmIds.size);
        this.realmOf[p] = realmIds.get(top.id)!;
        // «подкоролевство»: прямой вассал верховного сюзерена, в чьей державе графство
        let sub = holder;
        for (let k = 0; k < 20 && sub.liege && sub.liege !== top.id; k++) {
          const l = g.char(sub.liege);
          if (!l) break;
          sub = l;
        }
        if (!subIds.has(sub.id)) subIds.set(sub.id, subIds.size);
        this.subRealmOf[p] = subIds.get(sub.id)!;
      }
      let c: RGB | null = null;
      try {
        c = toRgb(spec?.color(g, id));
      } catch (e) {
        console.error(e);
      }
      colors.set(c ?? [120, 120, 120], p * 3);
      const occ = g.state.provinces[id]?.occupant;
      if (occ && this.mode === 'realms') {
        const o = g.char(occ);
        const oc = o?.titles[0] ? toRgb(g.content.get('titles', topLiege(g, o).titles[0])?.color) : null;
        if (oc) occColors.set(oc, p * 3);
      }
    }
    const data = this.img.data;
    const W = m.width;
    const N = m.pixels.length;
    for (let i = 0; i < N; i++) {
      const p = m.pixels[i];
      const o = i * 4;
      if (p < 0) {
        data[o] = this.sea[i * 3];
        data[o + 1] = this.sea[i * 3 + 1];
        data[o + 2] = this.sea[i * 3 + 2];
        data[o + 3] = 255;
        continue;
      }
      let r = colors[p * 3];
      let gg = colors[p * 3 + 1];
      let b = colors[p * 3 + 2];
      if (occColors[p * 3] >= 0) {
        const x = i % W;
        const y = (i / W) | 0;
        if ((x + y) % 10 < 4) {
          r = occColors[p * 3];
          gg = occColors[p * 3 + 1];
          b = occColors[p * 3 + 2];
        }
      }
      const s = this.shade[i];
      r *= s;
      gg *= s;
      b *= s;
      const nb = this.borderNb[i];
      if (nb !== -2) {
        if (nb < 0) {
          // берег
          r *= 0.55;
          gg *= 0.55;
          b *= 0.55;
        } else if (this.realmOf[p] !== this.realmOf[nb] || m.impassable[nb]) {
          r *= 0.28;
          gg *= 0.28;
          b *= 0.28;
        } else if (this.subRealmOf[p] !== this.subRealmOf[nb]) {
          r *= 0.5;
          gg *= 0.5;
          b *= 0.5;
        } else {
          r *= 0.72;
          gg *= 0.72;
          b *= 0.72;
        }
      }
      data[o] = r;
      data[o + 1] = gg;
      data[o + 2] = b;
      data[o + 3] = 255;
    }
    this.baseCtx.putImageData(this.img, 0, 0);
    this.computeLabels(realmIds);
    this.highlightFor = -2;
  }

  private computeLabels(realmIds: Map<string, number>) {
    const g = this.game!;
    const m = this.map;
    const acc = new Map<number, { x: number; y: number; a: number; owner: string }>();
    const owners = [...realmIds.entries()];
    for (let p = 0; p < m.provinces.length; p++) {
      const r = this.realmOf[p];
      if (r < 0) continue;
      const a = m.areas[p];
      const e = acc.get(r) ?? { x: 0, y: 0, a: 0, owner: owners[r][0] };
      e.x += m.centers[p * 2] * a;
      e.y += m.centers[p * 2 + 1] * a;
      e.a += a;
      acc.set(r, e);
    }
    this.labels = [];
    for (const e of acc.values()) {
      const c = g.char(e.owner);
      if (!c?.titles[0] || e.a < 1500) continue;
      const text = titleShortName(g, c.titles[0]).toUpperCase();
      const size = Math.max(7, Math.min(40, Math.sqrt(e.a) / Math.max(4, text.length * 0.55)));
      this.labels.push({ text, x: e.x / e.a, y: e.y / e.a, size });
    }
  }

  private buildHighlight(p: number, fill: string, stroke: string): HTMLCanvasElement | null {
    if (p < 0) return null;
    const m = this.map;
    const [x0, y0, x1, y1] = [this.bbox[p * 4], this.bbox[p * 4 + 1], this.bbox[p * 4 + 2], this.bbox[p * 4 + 3]];
    const w = x1 - x0 + 1;
    const h = y1 - y0 + 1;
    if (w <= 0 || h <= 0) return null;
    const c = document.createElement('canvas');
    c.width = w;
    c.height = h;
    const ctx = c.getContext('2d')!;
    const img = ctx.createImageData(w, h);
    const [fr, fg, fb, fa] = parseRgba(fill);
    const [sr, sg, sb, sa] = parseRgba(stroke);
    const W = m.width;
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const i = y * W + x;
        if (m.pixels[i] !== p) continue;
        const o = ((y - y0) * w + (x - x0)) * 4;
        const edge = this.borderNb[i] !== -2;
        img.data[o] = edge ? sr : fr;
        img.data[o + 1] = edge ? sg : fg;
        img.data[o + 2] = edge ? sb : fb;
        img.data[o + 3] = edge ? sa : fa;
      }
    }
    ctx.putImageData(img, 0, 0);
    (c as any).ox = x0;
    (c as any).oy = y0;
    return c;
  }

  // ------------------------------------------------------------ кадр

  draw() {
    const g = this.game;
    if (!g || !this.map) return;
    const sig = this.computeSignature();
    if (this.dirtyColors || sig !== this.signature) {
      this.signature = sig;
      this.dirtyColors = false;
      this.recolor();
    }
    const ctx = this.ctx;
    const dpr = window.devicePixelRatio || 1;
    if (this.canvas.width !== Math.round(this.canvas.clientWidth * dpr)) this.resize();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.clampView();
    ctx.fillStyle = '#1f3a50';
    ctx.fillRect(0, 0, this.canvas.clientWidth, this.canvas.clientHeight);
    ctx.save();
    ctx.scale(this.zoom, this.zoom);
    ctx.translate(-this.ox, -this.oy);
    ctx.imageSmoothingEnabled = this.zoom < 2;
    ctx.drawImage(this.base, 0, 0);
    // выделение
    const sel = this.host.selectedProvince();
    const selIdx = sel ? (this.map.index.get(sel) ?? -1) : -1;
    if (selIdx !== this.highlightFor) {
      this.highlightFor = selIdx;
      this.highlight = this.buildHighlight(selIdx, 'rgba(255,255,255,0.18)', 'rgba(255,240,180,0.95)');
    }
    if (this.hover !== this.hoverFor) {
      this.hoverFor = this.hover;
      this.hoverCanvas = this.hover !== selIdx ? this.buildHighlight(this.hover, 'rgba(255,255,255,0.10)', 'rgba(255,255,255,0.5)') : null;
    }
    if (this.hoverCanvas) ctx.drawImage(this.hoverCanvas, (this.hoverCanvas as any).ox, (this.hoverCanvas as any).oy);
    if (this.highlight) ctx.drawImage(this.highlight, (this.highlight as any).ox, (this.highlight as any).oy);
    ctx.restore();
    this.drawLabels();
    this.drawArmies();
  }

  /** Не даём увести карту далеко за края. */
  private clampView() {
    const w = this.canvas.clientWidth / this.zoom;
    const h = this.canvas.clientHeight / this.zoom;
    const mx = this.map.width;
    const my = this.map.height;
    const marginX = Math.max(0, w * 0.4);
    const marginY = Math.max(0, h * 0.4);
    this.ox = Math.max(-marginX, Math.min(mx - w + marginX, this.ox));
    this.oy = Math.max(-marginY, Math.min(my - h + marginY, this.oy));
    if (w > mx + 2 * marginX) this.ox = (mx - w) / 2;
    if (h > my + 2 * marginY) this.oy = (my - h) / 2;
  }

  private toScreen(x: number, y: number): [number, number] {
    return [(x - this.ox) * this.zoom, (y - this.oy) * this.zoom];
  }

  private drawLabels() {
    const ctx = this.ctx;
    const g = this.game!;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    if (this.zoom < 2.6) {
      for (const l of this.labels) {
        const px = l.size * this.zoom;
        if (px < 9) continue;
        const [x, y] = this.toScreen(l.x, l.y);
        ctx.font = `600 ${px}px "Cormorant Garamond", Georgia, serif`;
        ctx.lineWidth = Math.max(2, px / 6);
        ctx.strokeStyle = 'rgba(20,14,8,0.55)';
        ctx.fillStyle = 'rgba(245,232,200,0.92)';
        const spaced = l.text.split('').join(' ');
        ctx.strokeText(spaced, x, y);
        ctx.fillText(spaced, x, y);
      }
    }
    if (this.zoom >= 1.7) {
      const m = this.map;
      const px = Math.min(15, 5.5 * this.zoom);
      ctx.font = `${px}px "Cormorant Garamond", Georgia, serif`;
      for (let p = 0; p < m.provinces.length; p++) {
        if (m.areas[p] * this.zoom * this.zoom < 1800) continue;
        const [x, y] = this.toScreen(m.centers[p * 2], m.centers[p * 2 + 1] + 9);
        if (x < -50 || y < -20 || x > this.canvas.clientWidth + 50 || y > this.canvas.clientHeight + 20) continue;
        ctx.lineWidth = 3;
        ctx.strokeStyle = 'rgba(0,0,0,0.6)';
        ctx.fillStyle = '#f2ead6';
        const name = g.nameOf('provinces', m.provinces[p]);
        ctx.strokeText(name, x, y);
        ctx.fillText(name, x, y);
      }
    }
  }

  private armyPos(a: { location: string; path: string[]; progress: number }): [number, number] {
    const m = this.map;
    const i = m.index.get(a.location)!;
    let x = m.centers[i * 2];
    let y = m.centers[i * 2 + 1];
    if (a.path.length) {
      const j = m.index.get(a.path[0])!;
      x += (m.centers[j * 2] - x) * a.progress;
      y += (m.centers[j * 2 + 1] - y) * a.progress;
    }
    return [x, y];
  }

  private armyScreenPositions(): { id: string; x: number; y: number }[] {
    const g = this.game!;
    const byLoc = new Map<string, number>();
    const out: { id: string; x: number; y: number }[] = [];
    for (const a of Object.values(g.state.armies)) {
      const [mx, my] = this.armyPos(a);
      const k = byLoc.get(a.location) ?? 0;
      byLoc.set(a.location, k + 1);
      const [x, y] = this.toScreen(mx, my);
      out.push({ id: a.id, x: x + k * 10, y: y - 14 - k * 6 });
    }
    return out;
  }

  private drawArmies() {
    const g = this.game!;
    const ctx = this.ctx;
    const m = this.map;
    const player = g.state.player;
    const selArmy = this.host.selectedArmy();
    // осады
    for (const p of Object.values(g.state.provinces)) {
      if (!p.siege) continue;
      const i = m.index.get(p.id);
      if (i === undefined) continue;
      const [x, y] = this.toScreen(m.centers[i * 2], m.centers[i * 2 + 1]);
      ctx.beginPath();
      ctx.lineWidth = 4;
      ctx.strokeStyle = 'rgba(0,0,0,0.6)';
      ctx.arc(x, y + 8, 9, 0, Math.PI * 2);
      ctx.stroke();
      ctx.beginPath();
      ctx.strokeStyle = '#ffcc33';
      ctx.arc(x, y + 8, 9, -Math.PI / 2, -Math.PI / 2 + (Math.PI * 2 * p.siege.progress) / 100);
      ctx.stroke();
      ctx.font = '11px sans-serif';
      ctx.fillStyle = '#fff';
      ctx.fillText('🏰', x, y + 8);
    }
    // путь выбранной армии
    if (selArmy && g.state.armies[selArmy]?.path.length) {
      const a = g.state.armies[selArmy];
      ctx.beginPath();
      ctx.setLineDash([6, 5]);
      ctx.lineWidth = 2.5;
      ctx.strokeStyle = '#ffe9a8';
      const [sx, sy] = this.toScreen(...this.armyPos(a));
      ctx.moveTo(sx, sy);
      for (const p of a.path) {
        const i = m.index.get(p)!;
        const [x, y] = this.toScreen(m.centers[i * 2], m.centers[i * 2 + 1]);
        ctx.lineTo(x, y);
      }
      ctx.stroke();
      ctx.setLineDash([]);
      const last = a.path[a.path.length - 1];
      const li = m.index.get(last)!;
      const [lx, ly] = this.toScreen(m.centers[li * 2], m.centers[li * 2 + 1]);
      ctx.fillStyle = '#ffe9a8';
      ctx.font = '12px sans-serif';
      ctx.fillText(`⚑ ${daysToNext(g, a)}`, lx, ly - 4);
    }
    const playerWars = player ? warsOf(g, player) : [];
    for (const pos of this.armyScreenPositions()) {
      const a = g.state.armies[pos.id];
      const owner = g.char(a.owner);
      if (!owner) continue;
      const top = topLiege(g, owner);
      const color = g.content.get('titles', top.titles[0] ?? '')?.color ?? '#888888';
      let enemy = false;
      for (const w of playerWars) {
        const ps = participantSide(w, player!);
        const os = participantSide(w, a.owner);
        if (ps && os && ps !== os) enemy = true;
      }
      const label = a.size >= 1000 ? `${(a.size / 1000).toFixed(1)}k` : String(a.size);
      ctx.font = 'bold 12px sans-serif';
      const w = ctx.measureText(label).width + 22;
      const x = pos.x - w / 2;
      const y = pos.y - 9;
      ctx.fillStyle = 'rgba(0,0,0,0.55)';
      ctx.fillRect(x + 2, y + 2, w, 18);
      ctx.fillStyle = color;
      ctx.fillRect(x, y, w, 18);
      ctx.lineWidth = a.id === selArmy ? 3 : 1.5;
      ctx.strokeStyle = a.id === selArmy ? '#fff6c8' : a.owner === player ? '#f0c040' : enemy ? '#ff4040' : '#1a1208';
      ctx.strokeRect(x, y, w, 18);
      ctx.fillStyle = '#fff';
      ctx.textAlign = 'left';
      ctx.fillText(a.retreating ? '🏳' : '⚔', x + 3, y + 10);
      ctx.fillText(label, x + 18, y + 10);
      ctx.textAlign = 'center';
    }
  }

  // ------------------------------------------------------------ ввод

  /** Экранные координаты центра провинции (для тестов и подсказок). */
  screenOf(provId: string): [number, number] | null {
    const i = this.map.index.get(provId);
    if (i === undefined) return null;
    const r = this.canvas.getBoundingClientRect();
    const [x, y] = this.toScreen(this.map.centers[i * 2], this.map.centers[i * 2 + 1]);
    return [x + r.left, y + r.top];
  }

  screenToMap(sx: number, sy: number): [number, number] {
    return [sx / this.zoom + this.ox, sy / this.zoom + this.oy];
  }

  provinceAt(sx: number, sy: number): string | null {
    const [mx, my] = this.screenToMap(sx, sy);
    const x = Math.floor(mx);
    const y = Math.floor(my);
    if (x < 0 || y < 0 || x >= this.map.width || y >= this.map.height) return null;
    const p = this.map.pixels[y * this.map.width + x];
    return p >= 0 ? this.map.provinces[p] : null;
  }

  private armyAt(sx: number, sy: number): string | null {
    let best: string | null = null;
    let bd = 16;
    for (const p of this.armyScreenPositions()) {
      const d = Math.hypot(p.x - sx, p.y - sy);
      if (d < bd) {
        bd = d;
        best = p.id;
      }
    }
    return best;
  }

  private bindEvents() {
    const c = this.canvas;
    const local = (e: MouseEvent) => {
      const r = c.getBoundingClientRect();
      return [e.clientX - r.left, e.clientY - r.top] as [number, number];
    };
    c.addEventListener('wheel', (e) => {
      e.preventDefault();
      const [sx, sy] = local(e);
      const [mx, my] = this.screenToMap(sx, sy);
      const f = Math.exp(-e.deltaY * 0.0015);
      this.zoom = Math.max(0.35, Math.min(8, this.zoom * f));
      this.ox = mx - sx / this.zoom;
      this.oy = my - sy / this.zoom;
    }, { passive: false });
    c.addEventListener('mousedown', (e) => {
      if (e.button !== 0 && e.button !== 1) return;
      const [sx, sy] = local(e);
      this.dragStart = { x: sx, y: sy, ox: this.ox, oy: this.oy };
      this.dragging = false;
    });
    window.addEventListener('mousemove', (e) => {
      if (!this.dragStart) return;
      const [sx, sy] = local(e);
      const dx = sx - this.dragStart.x;
      const dy = sy - this.dragStart.y;
      if (Math.abs(dx) + Math.abs(dy) > 4) this.dragging = true;
      if (this.dragging) {
        this.ox = this.dragStart.ox - dx / this.zoom;
        this.oy = this.dragStart.oy - dy / this.zoom;
        hideTip();
      }
    });
    window.addEventListener('mouseup', (e) => {
      if (!this.dragStart) return;
      const wasDrag = this.dragging;
      this.dragStart = null;
      this.dragging = false;
      if (wasDrag || e.button !== 0 || e.target !== c) return;
      const [sx, sy] = local(e);
      const army = this.armyAt(sx, sy);
      if (army) return this.host.selectArmy(army);
      const p = this.provinceAt(sx, sy);
      if (p) this.host.selectProvince(p);
    });
    c.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      const [sx, sy] = local(e);
      const p = this.provinceAt(sx, sy);
      if (p && this.host.selectedArmy()) this.host.moveSelectedArmy(p);
    });
    c.addEventListener('mousemove', (e) => {
      if (this.dragStart) return;
      const [sx, sy] = local(e);
      const p = this.provinceAt(sx, sy);
      const idx = p ? (this.map.index.get(p) ?? -1) : -1;
      this.hover = idx;
      showFloatingTip(p ? this.host.provinceTooltip(p) : null, e.clientX, e.clientY);
    });
    c.addEventListener('mouseleave', () => {
      this.hover = -1;
      hideTip();
    });
  }
}

function boxBlur(src: Float32Array, W: number, H: number, r: number): Float32Array<ArrayBuffer> {
  const tmp = new Float32Array(src.length);
  const out = new Float32Array(src.length);
  const k = 2 * r + 1;
  for (let y = 0; y < H; y++) {
    let acc = 0;
    const row = y * W;
    for (let x = -r; x <= r; x++) acc += src[row + Math.min(W - 1, Math.max(0, x))];
    for (let x = 0; x < W; x++) {
      tmp[row + x] = acc / k;
      acc += src[row + Math.min(W - 1, x + r + 1)] - src[row + Math.max(0, x - r)];
    }
  }
  for (let x = 0; x < W; x++) {
    let acc = 0;
    for (let y = -r; y <= r; y++) acc += tmp[Math.min(H - 1, Math.max(0, y)) * W + x];
    for (let y = 0; y < H; y++) {
      out[y * W + x] = acc / k;
      acc += tmp[Math.min(H - 1, y + r + 1) * W + x] - tmp[Math.max(0, y - r) * W + x];
    }
  }
  return out;
}

function parseRgba(s: string): [number, number, number, number] {
  const m = /rgba?\(([^)]+)\)/.exec(s);
  if (!m) return [255, 255, 255, 255];
  const [r, g, b, a = '1'] = m[1].split(',').map((x) => x.trim());
  return [Number(r), Number(g), Number(b), Math.round(Number(a) * 255)];
}
