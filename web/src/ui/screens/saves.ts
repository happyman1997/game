/**
 * Сохранения. Где они лежат, решает платформа: в настольной версии — файлы
 * в «Документы/Crown and Dynasty/save games», в браузере — IndexedDB.
 */
import { dateParts } from '../../engine/core/date';
import { serializeGame } from '../../engine/save';
import { charFullName } from '../../engine/world/characters';
import { isDesktop, platform, type SaveMeta } from '../../platform';
import type { App } from '../app';
import { clear, h } from '../dom';
import { button } from '../widgets';

export function quickSaveSlot() {
  return 'quicksave';
}

export async function writeSave(app: App, slot: string, json: string, name?: string): Promise<void> {
  const g = app.game!;
  const p = g.player;
  const { y, m, d } = dateParts(g.date);
  const meta: SaveMeta = {
    slot,
    name: name ?? (slot === 'autosave' ? app.t('ui.autosave') : slot === 'quicksave' ? app.t('ui.quicksave') : slot),
    date: `${d}.${m}.${y}`,
    player: p ? charFullName(g, p, true) : '',
    savedAt: new Date().toLocaleString(),
  };
  await platform.saves.write(meta, json);
}

/** Сообщение поверх текущего экрана (в игре — уведомление, в меню — окно). */
export function showMessage(app: App, text: string) {
  if (app.game) return app.toast(text, 'bad');
  let close: () => void = () => {};
  close = dialog(app, h('div', null, h('p', null, text), h('div', { class: 'modal-buttons' }, button(app.t('ui.close'), () => close()))));
}

function loadJson(app: App, json: string) {
  try {
    const { game, warnings } = app.engine!.loadGame(json);
    app.enterGame(game);
    if (game.state.player) app.openCharacter(game.state.player);
    for (const w of warnings) app.toast(w, 'bad');
  } catch (e) {
    showMessage(app, `${app.t('ui.load_failed')}: ${(e as Error).message}`);
  }
}

function dialog(app: App, content: HTMLElement): () => void {
  if (app.game) return app.modal(content);
  const layer = document.querySelector('.menu-modal-layer') ?? document.body;
  const backdrop = h('div', { class: 'modal-backdrop' }, h('div', { class: 'modal' }, content));
  backdrop.addEventListener('mousedown', (e) => {
    if (e.target === backdrop) backdrop.remove();
  });
  layer.appendChild(backdrop);
  return () => backdrop.remove();
}

export function openSaveDialog(app: App) {
  const input = h('input', { type: 'text', class: 'text-input', value: `save_${Date.now() % 100000}` }) as HTMLInputElement;
  let close: () => void = () => {};
  const body = h('div', { class: 'save-dialog' },
    h('h2', null, app.t('ui.save_game')),
    input,
    h('div', { class: 'modal-buttons' },
      button(app.t('ui.save'), () => {
        const slot = input.value.trim() || 'save';
        close();
        writeSave(app, slot, serializeGame(app.game!), slot)
          .then(() => app.toast(app.t('ui.saved'), 'good'))
          .catch((e) => app.toast(`${app.t('ui.save_failed')}: ${(e as Error).message}`, 'bad'));
      }, { cls: 'btn-gold' }),
      button(app.t('ui.cancel'), () => close()),
    ),
  );
  close = dialog(app, body);
  input.focus();
}

export function openLoadDialog(app: App) {
  const body = h('div', { class: 'load-dialog' });
  let close: () => void = () => {};
  const render = () => {
    clear(body);
    body.append(h('h2', null, app.t('ui.load_game')));
    const list = h('div', { class: 'save-list' }, h('p', { class: 'muted' }, '…'));
    body.append(list);
    platform.saves.list().then((saves) => {
      clear(list);
      if (!saves.length) list.append(h('p', { class: 'muted' }, app.t('ui.no_saves')));
      for (const s of saves) list.append(saveRow(s));
    }, (e) => {
      clear(list);
      list.append(h('p', { class: 'bad' }, String((e as Error)?.message ?? e)));
    });
    const saveRow = (s: SaveMeta) => {
      return h('div', { class: 'save-row' },
        h('div', null, h('b', null, s.name), h('div', { class: 'muted' }, [s.player, s.date, s.savedAt].filter(Boolean).join(' · '))),
        button(app.t('ui.load'), () => {
          close();
          platform.saves.read(s.slot)
            .then((json) => (json ? loadJson(app, json) : showMessage(app, app.t('ui.load_failed'))))
            .catch((e) => showMessage(app, `${app.t('ui.load_failed')}: ${(e as Error).message}`));
        }, { cls: 'btn-small btn-gold' }),
        button('🗑', () => { platform.saves.remove(s.slot).then(render, render); }, { cls: 'btn-small', tip: app.t('ui.delete_save') }),
      );
    };
    const file = h('input', { type: 'file', accept: '.json,application/json', style: { display: 'none' }, onchange: async (e: Event) => {
      const f = (e.target as HTMLInputElement).files?.[0];
      if (!f) return;
      close();
      loadJson(app, await f.text());
    } }) as HTMLInputElement;
    body.append(file, h('div', { class: 'modal-buttons' },
      platform.openFolder ? button(app.t('ui.open_saves_folder'), () => platform.openFolder!('saves'), { tip: platform.folderPath?.('saves') }) : null,
      button(app.t('ui.import_save'), () => file.click()),
      button(app.t('ui.cancel'), () => close()),
    ));
  };
  render();
  close = dialog(app, body);
}

export function exportSave(app: App) {
  if (!app.game || isDesktop) return;
  const blob = new Blob([serializeGame(app.game)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  const { y } = dateParts(app.game.date);
  a.download = `crown-and-dynasty-${y}.json`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}
