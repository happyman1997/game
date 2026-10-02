/**
 * Универсальный реестр «id → объект». Почти всё расширяемое в движке
 * (триггеры, эффекты, системы, алгоритмы наследования, режимы карты)
 * хранится в таких реестрах, поэтому мод может добавить или заменить
 * любой элемент одной строкой.
 */
export class Registry<T> {
  private map = new Map<string, T>();
  private owners = new Map<string, string>();

  constructor(public readonly kind: string) {}

  register(id: string, item: T, owner?: string): this {
    this.map.set(id, item);
    if (owner) this.owners.set(id, owner);
    return this;
  }

  get(id: string): T | undefined {
    return this.map.get(id);
  }

  require(id: string): T {
    const v = this.map.get(id);
    if (v === undefined) throw new Error(`${this.kind}: "${id}" не зарегистрирован`);
    return v;
  }

  has(id: string): boolean {
    return this.map.has(id);
  }

  delete(id: string): boolean {
    this.owners.delete(id);
    return this.map.delete(id);
  }

  ownerOf(id: string): string | undefined {
    return this.owners.get(id);
  }

  ids(): string[] {
    return [...this.map.keys()];
  }

  values(): T[] {
    return [...this.map.values()];
  }

  entries(): [string, T][] {
    return [...this.map.entries()];
  }

  get size(): number {
    return this.map.size;
  }
}
