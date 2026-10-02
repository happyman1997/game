/**
 * Описание мода (mod.json в корне папки мода).
 */
export interface ModManifest {
  id: string;
  name: string | Record<string, string>;
  version?: string;
  description?: string | Record<string, string>;
  author?: string;
  /** Моды, без которых этот мод не работает (грузятся раньше). */
  dependencies?: string[];
  /** Если указанные моды включены — грузиться после них. */
  load_after?: string[];
  /** Приоритет при прочих равных: меньше — раньше. У core = -100. */
  priority?: number;
  /** Папки с данными относительно корня мода (по умолчанию ["data"]). */
  data?: string[];
  /** Папка локализации (по умолчанию "localization"). */
  localization?: string;
  /** JS/TS-скрипты, экспортирующие init(api). */
  scripts?: string[];
  /** Включён ли мод по умолчанию в менеджере модов. */
  default_enabled?: boolean;
  tags?: string[];
}

/**
 * Источник файлов мода. Благодаря этой абстракции один и тот же загрузчик
 * работает с модами, встроенными в сборку, с папкой, выбранной игроком
 * в браузере, и с файловой системой в Node (тесты, CLI).
 */
export interface ModSource {
  readonly kind: 'bundled' | 'folder' | 'node' | 'memory';
  /** Пути файлов относительно корня мода, через "/". */
  listFiles(): Promise<string[]>;
  readText(path: string): Promise<string>;
  importScript(path: string): Promise<any>;
}

export interface ModPackage {
  manifest: ModManifest;
  source: ModSource;
  /** Человекочитаемое происхождение: "встроенный", "папка", путь... */
  origin: string;
}

export interface ModIssue {
  mod?: string;
  file?: string;
  message: string;
  level: 'error' | 'warning';
}
