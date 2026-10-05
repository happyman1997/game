import YAML from 'yaml';

/**
 * Реестр форматов файлов данных. Из коробки поддерживаются YAML и JSON;
 * мод может зарегистрировать свой парсер (например, TOML или
 * Paradox-скрипт) через api.formats.register('txt', parser).
 */
export type Parser = (text: string, path: string) => unknown;

export class FormatRegistry {
  private parsers = new Map<string, Parser>();

  register(ext: string, parser: Parser): void {
    this.parsers.set(ext.toLowerCase().replace(/^\./, ''), parser);
  }

  extOf(path: string): string {
    const m = /\.([^./]+)$/.exec(path);
    return m ? m[1].toLowerCase() : '';
  }

  canParse(path: string): boolean {
    return this.parsers.has(this.extOf(path));
  }

  parse(text: string, path: string): unknown {
    const p = this.parsers.get(this.extOf(path));
    if (!p) throw new Error(`Нет парсера для файла ${path}`);
    return p(text, path);
  }

  extensions(): string[] {
    return [...this.parsers.keys()];
  }
}

function stripJsonComments(text: string): string {
  // Позволяем // и /* */ комментарии в JSON (JSONC), не трогая строки.
  let out = '';
  let inStr = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inStr) {
      out += c;
      if (c === '\\') {
        out += text[++i] ?? '';
      } else if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') {
      inStr = true;
      out += c;
    } else if (c === '/' && text[i + 1] === '/') {
      while (i < text.length && text[i] !== '\n') i++;
      out += '\n';
    } else if (c === '/' && text[i + 1] === '*') {
      i += 2;
      while (i < text.length && !(text[i] === '*' && text[i + 1] === '/')) i++;
      i++;
    } else out += c;
  }
  return out;
}

export function createDefaultFormats(): FormatRegistry {
  const f = new FormatRegistry();
  const yaml: Parser = (text, path) => {
    try {
      return YAML.parse(text, { merge: true, uniqueKeys: true, maxAliasCount: -1 });
    } catch (e: any) {
      throw new Error(`${path}: ${e.message}`);
    }
  };
  f.register('yaml', yaml);
  f.register('yml', yaml);
  f.register('json', (text, path) => {
    try {
      return JSON.parse(stripJsonComments(text));
    } catch (e: any) {
      throw new Error(`${path}: ${e.message}`);
    }
  });
  return f;
}
