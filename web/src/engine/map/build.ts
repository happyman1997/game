/**
 * Построение растровой карты из данных модов.
 *
 * Моддер описывает:
 *  - map: размеры и проекцию (границы в градусах широты/долготы);
 *  - landmasses: контуры суши (списки точек [широта, долгота] или pos в пикселях);
 *  - provinces: «зерно» каждой провинции (lat/lon или pos);
 *  - map_links: морские переправы между провинциями.
 *
 * Движок сам «заливает» сушу от зёрен с шумом (получаются естественные
 * границы), считает соседство, центры и прибрежность. Поэтому добавить
 * провинцию — это одна строка в YAML.
 */
import type { ContentStore } from '../content/store';
import { fbm, hash2 } from '../core/noise';
import { Rng, hashString } from '../core/rng';

export interface MapData {
  width: number;
  height: number;
  /** Индекс провинции для каждого пикселя, -1 — вода. */
  pixels: Int32Array;
  provinces: string[];
  index: Map<string, number>;
  impassable: Uint8Array;
  centers: Float32Array;
  areas: Int32Array;
  coastal: Uint8Array;
  neighbors: Map<string, string[]>;
  /** Только сухопутное соседство (для отрисовки и ИИ). */
  landNeighbors: Map<string, string[]>;
  links: [string, string][];
  project(lat: number, lon: number): [number, number];
}

interface MapSettings {
  width?: number;
  bounds?: { lon: [number, number]; lat: [number, number] };
  ref_lat?: number;
  border_noise?: number;
  coast_roughness?: number;
  seed?: number;
}

type Pt = [number, number];

function fractalize(points: Pt[], roughness: number, minLen: number, rng: Rng): Pt[] {
  const out: Pt[] = [];
  const rec = (a: Pt, b: Pt, depth: number) => {
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const len = Math.hypot(dx, dy);
    if (len < minLen || depth > 12) {
      out.push(b);
      return;
    }
    const off = (rng.next() - 0.5) * len * roughness;
    const mid: Pt = [(a[0] + b[0]) / 2 - (dy / len) * off, (a[1] + b[1]) / 2 + (dx / len) * off];
    rec(a, mid, depth + 1);
    rec(mid, b, depth + 1);
  };
  for (let i = 0; i < points.length; i++) {
    const a = points[i];
    const b = points[(i + 1) % points.length];
    rec(a, b, 0);
  }
  return out;
}

/** Заливка многоугольников по правилу чёт-нечёт, построчно. */
function rasterize(mask: Uint8Array, w: number, h: number, poly: Pt[]) {
  const n = poly.length;
  const xs: number[] = [];
  for (let y = 0; y < h; y++) {
    const cy = y + 0.5;
    xs.length = 0;
    for (let i = 0; i < n; i++) {
      const [x1, y1] = poly[i];
      const [x2, y2] = poly[(i + 1) % n];
      if ((y1 <= cy && y2 > cy) || (y2 <= cy && y1 > cy)) xs.push(x1 + ((cy - y1) / (y2 - y1)) * (x2 - x1));
    }
    if (xs.length < 2) continue;
    xs.sort((a, b) => a - b);
    for (let k = 0; k + 1 < xs.length; k += 2) {
      const from = Math.max(0, Math.ceil(xs[k] - 0.5));
      const to = Math.min(w - 1, Math.floor(xs[k + 1] - 0.5));
      for (let x = from; x <= to; x++) mask[y * w + x] ^= 1;
    }
  }
}

export function buildMap(content: ContentStore): MapData {
  const s = content.singleton<MapSettings>('map');
  const width = s.width ?? 1000;
  const lon = s.bounds?.lon ?? [-10, 10];
  const lat = s.bounds?.lat ?? [40, 60];
  const k = Math.cos(((s.ref_lat ?? (lat[0] + lat[1]) / 2) * Math.PI) / 180);
  const scale = width / ((lon[1] - lon[0]) * k);
  const height = Math.round((lat[1] - lat[0]) * scale);
  const project = (la: number, lo: number): [number, number] => [(lo - lon[0]) * k * scale, (lat[1] - la) * scale];
  const seed = s.seed ?? 1;
  const N = width * height;

  // 1. Суша
  const land = new Uint8Array(N);
  for (const lm of content.all('landmasses')) {
    const pts: Pt[] = (lm.points ?? []).map((p: number[]) => (lm.pixel ? [p[0], p[1]] : project(p[0], p[1])) as Pt);
    if (pts.length < 3) continue;
    const rough = lm.roughness ?? s.coast_roughness ?? 0.3;
    const poly = rough > 0 ? fractalize(pts, rough, 1.5, new Rng({ s: hashString(lm.id) ^ seed })) : pts;
    const m = new Uint8Array(N);
    rasterize(m, width, height, poly);
    for (let i = 0; i < N; i++) if (m[i]) land[i] = lm.water ? 0 : 1;
  }

  // 2. Провинции и зёрна
  const defs = content.all('provinces');
  const provinces = defs.map((d) => d.id as string);
  const index = new Map(provinces.map((p, i) => [p, i]));
  const impassable = new Uint8Array(provinces.length);
  const seeds: number[] = [];
  defs.forEach((d, i) => {
    if (d.impassable) impassable[i] = 1;
    let [x, y] = d.pos ? [d.pos[0], d.pos[1]] : project(d.lat ?? 0, d.lon ?? 0);
    x = Math.max(0, Math.min(width - 1, Math.round(x)));
    y = Math.max(0, Math.min(height - 1, Math.round(y)));
    if (!land[y * width + x]) {
      // ищем ближайшую сушу по спирали
      let found = -1;
      for (let r = 1; r < 40 && found < 0; r++) {
        for (let dy = -r; dy <= r && found < 0; dy++) {
          for (let dx = -r; dx <= r; dx++) {
            if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
            const nx = x + dx;
            const ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
            if (land[ny * width + nx]) {
              found = ny * width + nx;
              break;
            }
          }
        }
      }
      seeds.push(found);
    } else seeds.push(y * width + x);
  });

  // 3. Заливка от зёрен с шумовой стоимостью (алгоритм Дейкстры с корзинами)
  const pixels = new Int32Array(N).fill(-1);
  const dist = new Int32Array(N).fill(0x7fffffff);
  const noiseAmp = s.border_noise ?? 0.8;
  const cost = new Uint8Array(N);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = y * width + x;
      if (!land[i]) continue;
      const n = fbm(x / 18, y / 18, seed, 3);
      cost[i] = 1 + Math.min(4, Math.floor(n * n * 6 * noiseAmp + hash2(x, y, seed) * 0.8));
    }
  }
  const C = 8;
  const buckets: number[][] = Array.from({ length: C }, () => []);
  let pending = 0;
  seeds.forEach((p, i) => {
    if (p < 0) return;
    dist[p] = 0;
    pixels[p] = i;
    buckets[0].push(p);
    pending++;
  });
  for (let d = 0; pending > 0; d++) {
    const b = buckets[d % C];
    while (b.length) {
      const p = b.pop()!;
      pending--;
      if (dist[p] !== d) continue;
      const x = p % width;
      const owner = pixels[p];
      const tryN = (q: number) => {
        if (!land[q]) return;
        const nd = d + cost[q];
        if (nd < dist[q]) {
          dist[q] = nd;
          pixels[q] = owner;
          buckets[nd % C].push(q);
          pending++;
        }
      };
      if (x > 0) tryN(p - 1);
      if (x < width - 1) tryN(p + 1);
      if (p >= width) tryN(p - width);
      if (p < N - width) tryN(p + width);
    }
  }

  // 4. Острова без зёрен — к ближайшей провинции (через воду)
  {
    let frontier: number[] = [];
    const seen = new Uint8Array(N);
    for (let i = 0; i < N; i++) if (pixels[i] >= 0) {
      frontier.push(i);
      seen[i] = 1;
    }
    const owner = Int32Array.from(pixels);
    let unassigned = 0;
    for (let i = 0; i < N; i++) if (land[i] && pixels[i] < 0) unassigned++;
    while (frontier.length && unassigned > 0) {
      const next: number[] = [];
      for (const p of frontier) {
        const x = p % width;
        const nb = [x > 0 ? p - 1 : -1, x < width - 1 ? p + 1 : -1, p - width, p + width];
        for (const q of nb) {
          if (q < 0 || q >= N || seen[q]) continue;
          seen[q] = 1;
          owner[q] = owner[p];
          if (land[q] && pixels[q] < 0) {
            pixels[q] = owner[p];
            unassigned--;
          }
          next.push(q);
        }
      }
      frontier = next;
    }
  }

  // 5. Площади, прибрежность, соседство
  const P = provinces.length;
  const areas = new Int32Array(P);
  const coastal = new Uint8Array(P);
  const pairCount = new Map<number, number>();
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = y * width + x;
      const a = pixels[i];
      if (a < 0) continue;
      areas[a]++;
      const check = (j: number) => {
        const b = pixels[j];
        if (b < 0) {
          coastal[a] = 1;
          return;
        }
        if (b !== a) {
          const key = a < b ? a * P + b : b * P + a;
          pairCount.set(key, (pairCount.get(key) ?? 0) + 1);
        }
      };
      if (x < width - 1) check(i + 1);
      if (y < height - 1) check(i + width);
      if (x > 0 && pixels[i - 1] < 0) coastal[a] = 1;
      if (y > 0 && pixels[i - width] < 0) coastal[a] = 1;
    }
  }
  const landNeighbors = new Map<string, string[]>(provinces.map((p) => [p, []]));
  for (const [key, n] of pairCount) {
    if (n < 2) continue;
    const a = Math.floor(key / P);
    const b = key % P;
    landNeighbors.get(provinces[a])!.push(provinces[b]);
    landNeighbors.get(provinces[b])!.push(provinces[a]);
  }

  // 6. Центры: точка, максимально удалённая от границы провинции
  const centers = new Float32Array(P * 2);
  {
    const dd = new Int32Array(N).fill(-1);
    let frontier: number[] = [];
    for (let i = 0; i < N; i++) {
      const a = pixels[i];
      if (a < 0) continue;
      const x = i % width;
      const edge =
        x === 0 || x === width - 1 || i < width || i >= N - width ||
        pixels[i - 1] !== a || pixels[i + 1] !== a || pixels[i - width] !== a || pixels[i + width] !== a;
      if (edge) {
        dd[i] = 0;
        frontier.push(i);
      }
    }
    let d = 0;
    while (frontier.length) {
      d++;
      const next: number[] = [];
      for (const p of frontier) {
        const x = p % width;
        for (const q of [x > 0 ? p - 1 : -1, x < width - 1 ? p + 1 : -1, p - width, p + width]) {
          if (q < 0 || q >= N || dd[q] >= 0 || pixels[q] !== pixels[p]) continue;
          dd[q] = d;
          next.push(q);
        }
      }
      frontier = next;
    }
    const best = new Int32Array(P).fill(-1);
    const bestIdx = new Int32Array(P).fill(-1);
    for (let i = 0; i < N; i++) {
      const a = pixels[i];
      if (a >= 0 && dd[i] > best[a]) {
        best[a] = dd[i];
        bestIdx[a] = i;
      }
    }
    for (let a = 0; a < P; a++) {
      const i = bestIdx[a] >= 0 ? bestIdx[a] : seeds[a];
      centers[a * 2] = i >= 0 ? (i % width) + 0.5 : 0;
      centers[a * 2 + 1] = i >= 0 ? Math.floor(i / width) + 0.5 : 0;
    }
  }

  // 7. Переправы и итоговое соседство (без непроходимых провинций)
  const links: [string, string][] = [];
  for (const l of content.all('map_links')) {
    if (index.has(l.a) && index.has(l.b)) links.push([l.a, l.b]);
  }
  const neighbors = new Map<string, string[]>();
  for (const p of provinces) {
    const i = index.get(p)!;
    if (impassable[i]) {
      neighbors.set(p, []);
      continue;
    }
    const set = new Set(landNeighbors.get(p)!.filter((q) => !impassable[index.get(q)!]));
    for (const [a, b] of links) {
      if (a === p && !impassable[index.get(b)!]) set.add(b);
      if (b === p && !impassable[index.get(a)!]) set.add(a);
    }
    neighbors.set(p, [...set]);
  }

  return { width, height, pixels, provinces, index, impassable, centers, areas, coastal, neighbors, landNeighbors, links, project };
}

export function emptyMap(): MapData {
  return {
    width: 1,
    height: 1,
    pixels: new Int32Array(1).fill(-1),
    provinces: [],
    index: new Map(),
    impassable: new Uint8Array(0),
    centers: new Float32Array(0),
    areas: new Int32Array(0),
    coastal: new Uint8Array(0),
    neighbors: new Map(),
    landNeighbors: new Map(),
    links: [],
    project: () => [0, 0],
  };
}
