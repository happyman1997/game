/**
 * Реестр расширений интерфейса. Живёт в движке (без зависимостей от DOM),
 * чтобы моды могли регистрировать элементы UI из своих скриптов.
 * Браузерный интерфейс читает эти реестры при отрисовке.
 */
import { Registry } from './core/registry';
import type { TextValue } from './core/localization';
import type { Game } from './game';

export type RGB = [number, number, number];

export interface MapModeSpec {
  id: string;
  name: TextValue;
  icon?: string;
  order?: number;
  /** Цвет провинции; null — серый. */
  color(game: Game, provinceId: string): RGB | string | null;
  legend?(game: Game): { color: RGB | string; label: string }[];
  /** Подпись в подсказке при наведении. */
  tooltip?(game: Game, provinceId: string): string | null;
}

/** Кнопка на нижней панели, открывающая собственное окно мода. */
export interface PanelSpec {
  id: string;
  name: TextValue;
  icon: string;
  order?: number;
  /** Возвращает HTMLElement или HTML-строку. ui — объект интерфейса (см. src/ui/app.ts). */
  render(game: Game, ui: any): any;
}

/** Дополнительный раздел в окне персонажа или провинции. */
export interface SectionSpec {
  id: string;
  title: TextValue;
  order?: number;
  render(game: Game, id: string, ui: any): any;
}

/** Виджет в верхней панели ресурсов. */
export interface TopBarWidget {
  id: string;
  order?: number;
  render(game: Game): { icon?: string; text: string; tooltip?: string } | null;
}

/** Куда ведёт щелчок по оповещению. */
export interface AlertAction {
  /** Вкладка нижней панели: lifestyle, realm, military, wars, intrigue, decisions, log или mod:<id>. */
  tab?: string;
  character?: string;
  title?: string;
  province?: string;
}

export interface Alert {
  icon: string;
  text: string;
  /** good — возможность, bad — угроза, info — к сведению. */
  kind?: 'good' | 'bad' | 'info';
  action?: AlertAction;
}

/**
 * Оповещение в верхней панели (как в CK3: «можно открыть перк», «пустое
 * место в совете», «фракция грозит мятежом»). Проверяется раз в игровой день.
 */
export interface AlertSpec {
  id: string;
  order?: number;
  check(game: Game): Alert | Alert[] | null | undefined;
}

export class UIRegistry {
  readonly mapModes = new Registry<MapModeSpec>('режим карты');
  readonly panels = new Registry<PanelSpec>('панель');
  readonly characterSections = new Registry<SectionSpec>('раздел персонажа');
  readonly provinceSections = new Registry<SectionSpec>('раздел провинции');
  readonly topBar = new Registry<TopBarWidget>('виджет');
  readonly alerts = new Registry<AlertSpec>('оповещение');
  /** Иконки тем событий: theme → эмодзи/символ. */
  readonly eventThemes = new Registry<{ icon: string; color: string }>('тема события');
}
