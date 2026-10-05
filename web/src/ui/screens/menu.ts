import { parseDate } from '../../engine/core/date';
import { packagesFromFileList } from '../../engine/mods/sources';
import type { ModPackage } from '../../engine/mods/types';
import type { App } from '../app';
import { clear, h } from '../dom';
import { button } from '../widgets';
import { platform } from '../../platform';
import { openLoadDialog, showMessage } from './saves';
import { openSettings, openQuitDialog } from './settings';

function modName(app: App, p: ModPackage): string {
  const n = p.manifest.name;
  return typeof n === 'string' ? n : (n[app.lang] ?? n.en ?? Object.values(n)[0] ?? p.manifest.id);
}
function modDesc(app: App, p: ModPackage): string {
  const n = p.manifest.description;
  if (!n) return '';
  return typeof n === 'string' ? n : (n[app.lang] ?? n.en ?? Object.values(n)[0] ?? '');
}

export function renderMainMenu(app: App): HTMLElement {
  const e = app.engine!;
  const errors = e.issues.filter((i) => i.level === 'error').length;
  const warnings = e.issues.length - errors;
  const root = h('div', { class: 'main-menu' },
    h('div', { class: 'menu-card' },
      h('div', { class: 'menu-crown' }, '👑'),
      h('h1', null, app.t('ui.game_title')),
      h('div', { class: 'menu-sub' }, app.t('ui.game_subtitle')),
      h('div', { class: 'menu-buttons' },
        button(app.t('ui.new_game'), () => openBookmarks(app), { cls: 'btn-big btn-gold' }),
        button(app.t('ui.load_game'), () => openLoadDialog(app), { cls: 'btn-big' }),
        button(`${app.t('ui.mods')} (${e.mods.length})`, () => openModManager(app), { cls: 'btn-big' }),
        button(app.t('ui.settings'), () => openSettings(app), { cls: 'btn-big' }),
        button(app.lang === 'ru' ? 'Language: English' : 'Язык: русский', () => {
          app.setLanguage(app.lang === 'ru' ? 'en' : 'ru');
          app.showMainMenu();
        }, { cls: 'btn-big' }),
        platform.quit ? button(app.t('ui.quit_game'), () => openQuitDialog(app), { cls: 'btn-big' }) : null,
      ),
      platform.version ? h('div', { class: 'menu-version muted' }, `v${platform.version}`) : null,
      h('div', { class: 'menu-mods' },
        app.t('ui.active_mods'), ': ', e.mods.map((m) => modName(app, m)).join(', '),
        errors || warnings ? h('a', { class: ['link', errors ? 'bad' : 'warn'], onclick: () => openIssues(app) }, ` · ${app.t('ui.issues_n', { e: errors, w: warnings })}`) : null,
      ),
    ),
    h('div', { class: 'menu-modal-layer' }),
  );
  return root;
}

export function menuModal(app: App, content: HTMLElement): () => void {
  const layer = document.querySelector('.menu-modal-layer') as HTMLElement | null;
  const backdrop = h('div', { class: 'modal-backdrop' }, h('div', { class: 'modal' }, content));
  const close = () => backdrop.remove();
  backdrop.addEventListener('mousedown', (ev) => {
    if (ev.target === backdrop) close();
  });
  (layer ?? document.body).appendChild(backdrop);
  return close;
}

function openBookmarks(app: App) {
  const e = app.engine!;
  const bms = e.bookmarks();
  const body = h('div', { class: 'bookmarks' }, h('h2', null, app.t('ui.choose_bookmark')));
  let close: () => void = () => {};
  for (const b of bms) {
    const name = e.loc.resolve(b.name ?? `bookmark.${b.id}`);
    const desc = e.loc.resolve(b.desc ?? `bookmark_desc.${b.id}`);
    const y = Math.floor(parseDate(b.date) / 365);
    const card = h('div', { class: 'bookmark-card' },
      h('div', { class: 'bm-year' }, String(y)),
      h('div', { class: 'bm-body' }, h('h3', null, name), h('p', null, desc)),
    );
    const chars = h('div', { class: 'bm-chars' });
    for (const id of b.playable ?? []) {
      const def = e.content.get('characters', id);
      if (!def) continue;
      const nm = e.loc.rawExact(`name.${def.name}`) ?? def.name;
      const dyn = def.nickname ? e.loc.resolve(def.nickname) : def.dynasty ? e.loc.raw(`dynasty.${def.dynasty}`) ?? '' : '';
      const title = Object.entries(b.holders ?? {}).filter(([, c]) => c === id).map(([t]) => t).sort((a, z) => rank(z) - rank(a))[0];
      chars.append(button(h('span', null, h('b', null, `${nm} ${dyn}`), h('br'), h('small', null, title ? e.loc.raw(`${title}_full`) ?? `${e.loc.t(`tier.${e.content.get('titles', title)?.tier}`)} ${e.loc.t(title)}` : '')), () => {
        close();
        app.startNewGame(b.id, id);
      }, { cls: 'bm-char' }));
    }
    chars.append(button(app.t('ui.pick_on_map'), () => {
      close();
      app.startNewGame(b.id);
    }, { cls: 'bm-char pick' }));
    card.append(chars);
    body.append(card);
  }
  if (!bms.length) body.append(h('p', { class: 'bad' }, app.t('ui.no_bookmarks')));
  body.append(h('div', { class: 'modal-buttons' }, button(app.t('ui.cancel'), () => close())));
  close = menuModal(app, body);
}

function rank(t: string) {
  return t.startsWith('e_') ? 4 : t.startsWith('k_') ? 3 : t.startsWith('d_') ? 2 : 1;
}

export function openModManager(app: App) {
  const body = h('div', { class: 'mod-manager' });
  const all = app.allPackages();
  const enabled = new Set(app.enabled ?? all.filter((p) => p.manifest.default_enabled !== false).map((p) => p.manifest.id));
  let close: () => void = () => {};
  const render = () => {
    clear(body);
    body.append(h('h2', null, app.t('ui.mods')), h('p', { class: 'muted' }, app.t('ui.mods_hint')));
    const list = h('div', { class: 'mod-list' });
    for (const p of app.allPackages()) {
      const m = p.manifest;
      const deps = (m.dependencies ?? []).filter((d) => !enabled.has(d));
      const issues = app.issues().filter((i) => i.mod === m.id);
      list.append(h('label', { class: 'mod-row' },
        h('input', { type: 'checkbox', checked: enabled.has(m.id), onchange: (ev: Event) => {
          if ((ev.target as HTMLInputElement).checked) enabled.add(m.id);
          else enabled.delete(m.id);
          render();
        } }),
        h('div', { class: 'mod-info' },
          h('div', { class: 'mod-name' }, modName(app, p), h('span', { class: 'muted' }, ` ${m.id} · v${m.version ?? '?'} · ${p.origin}`)),
          h('div', { class: 'muted' }, modDesc(app, p)),
          m.dependencies?.length ? h('div', { class: deps.length ? 'bad' : 'muted' }, `${app.t('ui.depends_on')}: ${m.dependencies.join(', ')}`) : null,
          issues.length ? h('div', { class: 'warn' }, app.t('ui.issues_n', { e: issues.filter((i) => i.level === 'error').length, w: issues.filter((i) => i.level !== 'error').length })) : null,
        ),
      ));
    }
    body.append(list);
    const input = h('input', { type: 'file', webkitdirectory: true, multiple: true, style: { display: 'none' }, onchange: async (ev: Event) => {
      const files = (ev.target as HTMLInputElement).files;
      if (!files?.length) return;
      try {
        const pkgs = await packagesFromFileList(files);
        for (const pk of pkgs) {
          app.folderPackages = app.folderPackages.filter((x) => x.manifest.id !== pk.manifest.id);
          app.folderPackages.push(pk);
          enabled.add(pk.manifest.id);
        }
        render();
      } catch (e) {
        showMessage(app, (e as Error).message);
      }
    } }) as HTMLInputElement;
    body.append(input);
    if (platform.folderPath) body.append(h('p', { class: 'muted small' }, app.t('ui.mods_folder_hint', { path: platform.folderPath('mods') })));
    body.append(h('div', { class: 'modal-buttons' },
      platform.openFolder
        ? button(app.t('ui.open_mods_folder'), () => platform.openFolder!('mods'), { tip: platform.folderPath?.('mods') })
        : button(app.t('ui.load_mod_folder'), () => input.click(), { tip: app.t('ui.load_mod_folder_tip') }),
      platform.openFolder
        ? button(app.t('ui.rescan_mods'), async () => {
            await app.reloadMods();
            render();
          }, { tip: app.t('ui.rescan_mods_tip') })
        : null,
      button(app.t('ui.apply_mods'), async () => {
        close();
        app.setEnabledMods(new Set(enabled));
        app.showLoading(app.t('ui.loading_mods'));
        await app.buildEngine();
        app.showMainMenu();
      }, { cls: 'btn-gold' }),
      button(app.t('ui.cancel'), () => close()),
    ));
  };
  render();
  close = menuModal(app, body);
}

export function openIssues(app: App) {
  const issues = app.issues();
  const body = h('div', { class: 'issues' },
    h('h2', null, app.t('ui.mod_issues')),
    issues.length ? h('div', { class: 'issue-list' }, ...issues.map((i) => h('div', { class: `issue ${i.level}` }, `[${i.level}] `, i.mod ? `${i.mod}: ` : '', i.file ? `${i.file}: ` : '', i.message))) : h('p', { class: 'muted' }, app.t('ui.no_issues')),
  );
  let close: () => void = () => {};
  body.append(h('div', { class: 'modal-buttons' }, button(app.t('ui.close'), () => close())));
  close = app.game ? app.modal(body) : menuModal(app, body);
}
