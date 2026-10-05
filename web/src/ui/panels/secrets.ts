import { type SecretTypeDef, knownSecretsOf, secretsOf } from '../../engine/features/secrets';
import type { Character, Secret } from '../../engine/types';
import { canUseHook, hookOn } from '../../engine/world/hooks';
import type { App } from '../app';
import { esc, h } from '../dom';
import { charLink, section } from '../widgets';

function secretChip(app: App, _owner: Character, s: Secret, showKnown: boolean): HTMLElement {
  const g = app.game!;
  const def = g.content.get<SecretTypeDef>('secret_types', s.type);
  return h('div', {
    class: 'secret-row',
    tip: () => `<div class="tip-title">${esc(def?.icon ?? '🤫')} ${esc(g.nameOf('secret_types', s.type))}</div><p>${esc(g.descOf('secret_types', s.type))}</p>`,
  },
  h('span', { class: 'secret-icon' }, def?.icon ?? '🤫'),
  h('span', null, g.nameOf('secret_types', s.type)),
  s.target ? h('span', { class: 'muted' }, ' — ', charLink(app, s.target)) : null,
  showKnown ? h('span', { class: s.known.length ? 'bad' : 'muted' }, ` · ${app.t('ui.secret_known_by_n', { n: s.known.length })}`) : null);
}

function hookKind(app: App, strong?: boolean) {
  return app.t(strong ? 'ui.hook_strong' : 'ui.hook_weak');
}

/** Раздел окна персонажа: известные игроку секреты и крюки. */
export function secretsCharacterSection(app: App, c: Character): HTMLElement | null {
  const g = app.game!;
  const p = g.player;
  if (!p || !g.engine.hasFeature('secrets')) return null;
  const rows: HTMLElement[] = [];
  if (c.id === p.id) {
    for (const s of secretsOf(c)) rows.push(secretChip(app, c, s, true));
  } else {
    const mine = hookOn(g, p, c.id);
    if (mine) {
      const cd = canUseHook(g, p, c.id) ? '' : ` (${app.t('ui.hook_cooldown', { days: (p.flags[`hook_cd:${c.id}`] ?? g.date) - g.date })})`;
      rows.push(h('div', { class: 'hook-line good' }, `🪝 ${app.t('ui.you_have_hook', { kind: hookKind(app, mine.strong) })}${cd}`));
    }
    const theirs = hookOn(g, c, p.id);
    if (theirs) rows.push(h('div', { class: 'hook-line bad' }, `🪝 ${app.t('ui.has_hook_on_you', { kind: hookKind(app, theirs.strong) })}`));
    for (const s of knownSecretsOf(g, c, p.id)) rows.push(secretChip(app, c, s, false));
  }
  return rows.length ? section(app.t('ui.secrets'), ...rows) : null;
}

/** Разделы вкладки интриг: мои секреты, чужие секреты, крюки. */
export function secretsIntrigueSections(app: App): HTMLElement[] {
  const g = app.game!;
  const p = g.player!;
  if (!g.engine.hasFeature('secrets')) return [];
  const out: HTMLElement[] = [];
  const own = secretsOf(p);
  out.push(section(`🤫 ${app.t('ui.my_secrets')}`, ...(own.length ? own.map((s) => secretChip(app, p, s, true)) : [h('div', { class: 'muted' }, app.t('ui.no_secrets'))])));
  const known: HTMLElement[] = [];
  for (const o of g.living()) {
    for (const s of knownSecretsOf(g, o, p.id)) known.push(h('div', { class: 'secret-owner' }, charLink(app, o.id, true), ': ', secretChip(app, o, s, false)));
  }
  if (known.length) out.push(section(`🔎 ${app.t('ui.known_secrets')}`, ...known));
  const myHooks = p.hooks.filter((x) => x.expires === undefined || x.expires > g.date);
  const onMe = g.living().filter((o) => hookOn(g, o, p.id));
  if (myHooks.length || onMe.length) {
    out.push(section(`🪝 ${app.t('ui.hooks')}`,
      ...myHooks.map((x) => h('div', { class: 'hook-line good' }, charLink(app, x.target, true), ` — ${hookKind(app, x.strong)}`)),
      ...onMe.map((o) => h('div', { class: 'hook-line bad' }, charLink(app, o.id, true), ` → ${app.t('ui.hooks_on_me')} (${hookKind(app, hookOn(g, o, p.id)?.strong)})`)),
    ));
  }
  return out;
}
