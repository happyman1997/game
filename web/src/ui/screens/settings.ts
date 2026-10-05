/**
 * Настройки игры и выход. Набор настроек зависит от платформы: полноэкранный
 * режим, масштаб интерфейса и папки есть только в настольной версии.
 */
import { serializeGame } from '../../engine/save';
import { platform, type FolderKind } from '../../platform';
import type { App } from '../app';
import { h } from '../dom';
import { button } from '../widgets';
import { menuModal } from './menu';
import { writeSave } from './saves';

const ZOOMS = [0.8, 0.9, 1, 1.1, 1.25, 1.5];

function open(app: App, body: HTMLElement): () => void {
  return app.game ? app.modal(body) : menuModal(app, body);
}

function row(label: string, control: HTMLElement, hint?: string): HTMLElement {
  return h('label', { class: 'settings-row' }, h('span', { class: 'settings-label' }, label, hint ? h('small', { class: 'muted' }, hint) : null), control);
}

function select(id: string, options: [string, string][], value: string, onchange: (v: string) => void): HTMLSelectElement {
  const el = h('select', { id, class: 'select', onchange: (e: Event) => onchange((e.target as HTMLSelectElement).value) },
    ...options.map(([v, label]) => h('option', { value: v, selected: v === value }, label))) as HTMLSelectElement;
  return el;
}

export function openSettings(app: App, onClose?: () => void) {
  let close: () => void = () => {};
  const done = () => {
    close();
    onClose?.();
  };
  const body = h('div', { class: 'settings' }, h('h2', null, app.t('ui.settings')));
  const list = h('div', { class: 'settings-list' });
  body.append(list);

  list.append(row(app.t('ui.setting_language'), select('set-lang', [['ru', 'Русский'], ['en', 'English']], app.lang, (v) => {
    app.setLanguage(v);
    done();
    if (app.game) openSettings(app, onClose);
    else {
      app.showMainMenu();
      openSettings(app);
    }
  })));

  list.append(row(app.t('ui.setting_autosave'), select('set-autosave', [
    ['yearly', app.t('ui.autosave_yearly')],
    ['half_year', app.t('ui.autosave_half_year')],
    ['off', app.t('ui.autosave_off')],
  ], platform.settings.get<string>('autosave', 'yearly'), (v) => platform.settings.set('autosave', v))));

  if (platform.setFullscreen) {
    const cb = h('input', { id: 'set-fullscreen', type: 'checkbox', checked: platform.isFullscreen?.() ?? false, onchange: (e: Event) => platform.setFullscreen!((e.target as HTMLInputElement).checked) }) as HTMLInputElement;
    platform.onFullscreenChange?.((on) => {
      cb.checked = on;
    });
    list.append(row(app.t('ui.setting_fullscreen'), cb, 'F11'));
  }
  if (platform.setZoom) {
    const cur = platform.getZoom?.() ?? 1;
    const opts = ZOOMS.includes(cur) ? ZOOMS : [...ZOOMS, cur].sort((a, b) => a - b);
    list.append(row(app.t('ui.setting_zoom'), select('set-zoom', opts.map((z) => [String(z), `${Math.round(z * 100)}%`]), String(cur), (v) => platform.setZoom!(Number(v))), 'Ctrl + / Ctrl −'));
  }
  if (platform.openFolder) {
    const folders: [FolderKind, string][] = [['saves', 'ui.open_saves_folder'], ['mods', 'ui.open_mods_folder'], ['builtin_mods', 'ui.open_builtin_mods_folder']];
    body.append(h('div', { class: 'settings-folders' },
      ...folders.map(([k, label]) => button(app.t(label), () => platform.openFolder!(k), { cls: 'btn-small', tip: platform.folderPath?.(k) }))));
  }
  if (platform.version) body.append(h('p', { class: 'muted small' }, `${app.t('ui.game_title')} v${platform.version}`));
  body.append(h('div', { class: 'modal-buttons' }, button(app.t('ui.close'), done, { cls: 'btn-gold' })));
  close = open(app, body);
}

/** Выход из игры. Посреди партии предлагает сохраниться. */
export function openQuitDialog(app: App) {
  const quit = () => platform.quit?.();
  if (!app.game?.state.player) return quit();
  let close: () => void = () => {};
  const body = h('div', { class: 'quit-dialog' },
    h('h2', null, app.t('ui.quit_game')),
    h('p', null, app.t('ui.quit_confirm')),
    h('div', { class: 'modal-buttons' },
      button(app.t('ui.save_and_quit'), () => {
        close();
        writeSave(app, 'autosave', serializeGame(app.game!)).then(quit, (e) => app.toast(`${app.t('ui.save_failed')}: ${(e as Error).message}`, 'bad'));
      }, { cls: 'btn-gold' }),
      button(app.t('ui.quit_without_saving'), () => {
        close();
        quit();
      }),
      button(app.t('ui.cancel'), () => close()),
    ),
  );
  close = open(app, body);
}
