/**
 * Детерминированный генератор случайных чисел (mulberry32).
 * Состояние хранится в простом объекте, чтобы попадать в сохранения.
 */
export interface RngState {
  s: number;
}

export class Rng {
  constructor(public state: RngState) {}

  static fromSeed(seed: number | string): Rng {
    return new Rng({ s: typeof seed === 'number' ? seed | 0 : hashString(seed) });
  }

  next(): number {
    let t = (this.state.s = (this.state.s + 0x6d2b79f5) | 0);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  /** Целое в диапазоне [min, max] включительно. */
  int(min: number, max: number): number {
    return min + Math.floor(this.next() * (max - min + 1));
  }

  float(min: number, max: number): number {
    return min + this.next() * (max - min);
  }

  chance(p: number): boolean {
    return this.next() < p;
  }

  pick<T>(arr: readonly T[]): T | undefined {
    if (arr.length === 0) return undefined;
    return arr[Math.floor(this.next() * arr.length)];
  }

  weighted<T>(items: readonly T[], weight: (item: T) => number): T | undefined {
    let total = 0;
    const ws = items.map((it) => {
      const w = Math.max(0, weight(it) || 0);
      total += w;
      return w;
    });
    if (total <= 0) return undefined;
    let r = this.next() * total;
    for (let i = 0; i < items.length; i++) {
      r -= ws[i];
      if (r < 0) return items[i];
    }
    return items[items.length - 1];
  }

  shuffle<T>(arr: T[]): T[] {
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(this.next() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr;
  }

  /** Приближённо нормальное распределение (сумма трёх равномерных). */
  gauss(mean: number, spread: number): number {
    const u = (this.next() + this.next() + this.next()) / 3 - 0.5;
    return mean + u * 2 * spread;
  }
}

/** FNV-1a хеш строки — для детерминированных «случайных» величин (гербы, портреты). */
export function hashString(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h | 0;
}
