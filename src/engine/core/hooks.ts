/**
 * Шина хуков. Через неё движок оповещает моды о событиях мира
 * («персонаж умер», «началась война», «наступил новый месяц»...),
 * а моды могут вмешиваться: отменять действия (veto) или
 * добавлять свои значения (collect).
 *
 * Ошибка в обработчике одного мода не роняет игру — она перехватывается
 * и передаётся в onError.
 */
export type HookHandler = (payload: any) => any;

interface Entry {
  fn: HookHandler;
  priority: number;
  owner?: string;
}

export class HookBus {
  private handlers = new Map<string, Entry[]>();
  onError: (err: unknown, hook: string, owner?: string) => void = (err, hook, owner) =>
    console.error(`[hook ${hook}${owner ? ` @${owner}` : ''}]`, err);

  on(name: string, fn: HookHandler, opts: { priority?: number; owner?: string } = {}): () => void {
    const list = this.handlers.get(name) ?? [];
    list.push({ fn, priority: opts.priority ?? 0, owner: opts.owner });
    list.sort((a, b) => b.priority - a.priority);
    this.handlers.set(name, list);
    return () => this.off(name, fn);
  }

  off(name: string, fn: HookHandler): void {
    const list = this.handlers.get(name);
    if (!list) return;
    this.handlers.set(
      name,
      list.filter((e) => e.fn !== fn),
    );
  }

  has(name: string): boolean {
    return (this.handlers.get(name)?.length ?? 0) > 0;
  }

  emit(name: string, payload: any): void {
    const list = this.handlers.get(name);
    if (!list) return;
    for (const e of list) {
      try {
        e.fn(payload);
      } catch (err) {
        this.onError(err, name, e.owner);
      }
    }
  }

  /** Возвращает false, если хотя бы один обработчик вернул false. */
  veto(name: string, payload: any): boolean {
    const list = this.handlers.get(name);
    if (!list) return true;
    for (const e of list) {
      try {
        if (e.fn(payload) === false) return false;
      } catch (err) {
        this.onError(err, name, e.owner);
      }
    }
    return true;
  }

  /** Собирает все не-undefined результаты обработчиков. */
  collect<T>(name: string, payload: any): T[] {
    const out: T[] = [];
    const list = this.handlers.get(name);
    if (!list) return out;
    for (const e of list) {
      try {
        const r = e.fn(payload);
        if (r !== undefined) out.push(r);
      } catch (err) {
        this.onError(err, name, e.owner);
      }
    }
    return out;
  }

  names(): string[] {
    return [...this.handlers.keys()];
  }
}
