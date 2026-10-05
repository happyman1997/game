import { createDefaultFormats } from '../src/engine/core/formats';
import { Engine } from '../src/engine/engine';
import { MemoryModSource } from '../src/engine/mods/sources';
import { loadNodeLocale, loadNodeModPackages } from '../src/engine/mods/nodeSource';
import type { ModManifest, ModPackage } from '../src/engine/mods/types';

export function memoryMod(manifest: Partial<ModManifest> & { id: string }, files: Record<string, string>, scripts: Record<string, any> = {}): ModPackage {
  return {
    manifest: { name: manifest.id, ...manifest } as ModManifest,
    source: new MemoryModSource(files, scripts),
    origin: 'memory',
  };
}

let cachedLocale: Record<string, unknown[]> | null = null;
export async function defaultLocale() {
  cachedLocale ??= await loadNodeLocale('../locale', (t, p) => createDefaultFormats().parse(t, p));
  return cachedLocale;
}

export async function realEngine(enabled?: string[]) {
  return Engine.create(await loadNodeModPackages('../mods'), {
    enabled: enabled ? new Set(enabled) : null,
    defaultLocalization: await defaultLocale(),
  });
}

/** Крошечный самодостаточный мир для тестов скриптового языка. */
export const MINI_WORLD = `
defines:
  character: { adult_age: 16 }
skills:
  diplomacy: {}
  martial: {}
  stewardship: {}
  intrigue: {}
  learning: {}
  prowess: {}
traits:
  brave: { category: personality, modifiers: { martial: 2 }, opposites: [craven] }
  craven: { category: personality, opposites: [brave] }
  ill: { category: health, modifiers: { health: -2 } }
cultures:
  testish: { color: "#aa0000", male_names: [Adam, Bran], female_names: [Cara, Dana], dynasty_pattern: name }
faiths:
  old_gods: { color: "#00aa00" }
terrain:
  plains: { color: "#999999", defense: 0, movement: 1, height: 0.1 }
holdings:
  castle: { tax: 1, levy: 100, fort: 1 }
succession_laws:
  primogeniture: { algorithm: primogeniture, gender: male_preference }
landmasses:
  island: { points: [[10, 0], [10, 10], [0, 10], [0, 0]], roughness: 0 }
map:
  width: 200
  bounds: { lon: [0, 10], lat: [0, 10] }
  ref_lat: 5
titles:
  k_test: { tier: kingdom, color: "#3355aa" }
  d_north: { tier: duchy, liege: k_test, color: "#4466bb" }
  d_south: { tier: duchy, liege: k_test, color: "#5577cc" }
provinces:
  c_a: { lat: 8, lon: 2, duchy: d_north, terrain: plains, culture: testish, faith: old_gods, development: 5, holdings: [castle] }
  c_b: { lat: 8, lon: 8, duchy: d_north, terrain: plains, culture: testish, faith: old_gods, development: 5, holdings: [castle] }
  c_c: { lat: 2, lon: 2, duchy: d_south, terrain: plains, culture: testish, faith: old_gods, development: 5, holdings: [castle] }
  c_d: { lat: 2, lon: 8, duchy: d_south, terrain: plains, culture: testish, faith: old_gods, development: 5, holdings: [castle] }
dynasties:
  house_a: {}
characters:
  king: { name: Adam, dynasty: house_a, culture: testish, faith: old_gods, birth: "1000.1.1", traits: [brave], skills: { diplomacy: 5, martial: 6, stewardship: 5, intrigue: 5, learning: 5, prowess: 5 }, gold: 100, spouse: queen }
  queen: { name: Cara, female: true, culture: testish, faith: old_gods, birth: "1005.1.1", skills: { diplomacy: 5, martial: 5, stewardship: 5, intrigue: 5, learning: 5, prowess: 5 } }
  prince: { name: Bran, dynasty: house_a, culture: testish, faith: old_gods, birth: "1020.1.1", father: king, mother: queen }
  duke: { name: Bran, culture: testish, faith: old_gods, birth: "1001.1.1", traits: [craven], gold: 10 }
bookmarks:
  start:
    date: "1030.1.1"
    holders: { k_test: king, d_north: king, c_a: king, c_b: king, d_south: duke, c_c: duke, c_d: duke }
    generate_missing: false
`;

export async function miniEngine(extraFiles: Record<string, string> = {}, scripts: Record<string, any> = {}, manifest: Partial<ModManifest> = {}) {
  const mod = memoryMod({ id: 'mini', ...manifest }, { 'data/world.yaml': MINI_WORLD, ...extraFiles }, scripts);
  return Engine.create([mod], { defaultLocalization: await defaultLocale() });
}
