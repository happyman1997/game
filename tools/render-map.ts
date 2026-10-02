/**
 * Рисует растр провинций в PNG (для проверки геометрии карты модов).
 *   npx tsx tools/render-map.ts [out.png]
 */
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { createDefaultFormats } from '../src/engine/core/formats';
import { hashString } from '../src/engine/core/rng';
import { normalizeContent } from '../src/engine/content/normalize';
import { buildMap } from '../src/engine/map/build';
import { loadMods } from '../src/engine/mods/loader';
import { loadNodeModPackages } from '../src/engine/mods/nodeSource';
import { encodePng } from './png';

const out = process.argv[2] ?? 'screenshots/map-raster.png';
const res = await loadMods(await loadNodeModPackages('mods'), createDefaultFormats());
for (const i of res.issues) console.log(i.level, i.mod, i.file ?? '', i.message);
normalizeContent(res.content);
const t0 = Date.now();
const m = buildMap(res.content);
console.log(`map ${m.width}x${m.height}, ${m.provinces.length} provinces, ${Date.now() - t0}ms`);
const rgba = new Uint8Array(m.width * m.height * 4);
for (let i = 0; i < m.pixels.length; i++) {
  const p = m.pixels[i];
  let r = 40, g = 70, b = 110;
  if (p >= 0) {
    const h = hashString(m.provinces[p]);
    r = 80 + (h & 0x7f); g = 80 + ((h >> 8) & 0x7f); b = 60 + ((h >> 16) & 0x5f);
    if (m.impassable[p]) { r = g = b = 90; }
    const x = i % m.width;
    if ((x < m.width - 1 && m.pixels[i + 1] !== p) || (i + m.width < m.pixels.length && m.pixels[i + m.width] !== p)) { r = g = b = 20; }
  }
  rgba.set([r, g, b, 255], i * 4);
}
for (let p = 0; p < m.provinces.length; p++) {
  const cx = Math.round(m.centers[p * 2]); const cy = Math.round(m.centers[p * 2 + 1]);
  for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
    const i = (cy + dy) * m.width + cx + dx;
    if (i >= 0 && i < m.pixels.length) rgba.set([255, 255, 255, 255], i * 4);
  }
}
const small = [...m.areas].map((a, i) => [m.provinces[i], a] as const).filter(([, a]) => a < 300);
console.log('small provinces:', small);
const isolated = m.provinces.filter((p, i) => !m.impassable[i] && (m.neighbors.get(p)?.length ?? 0) === 0);
console.log('no neighbors:', isolated);
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, encodePng(m.width, m.height, rgba));
console.log('saved', out);
