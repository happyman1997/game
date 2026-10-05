import {
  type CouncilTaskDef,
  appointCouncillor,
  councilCandidates,
  councilPositionOf,
  councilPositions,
  dismissCouncillor,
  isPositionShown,
  setCouncilTask,
  taskMonthlyChance,
  tasksOf,
} from '../../engine/features/council';
import { evalModifiers } from '../../engine/features/feature';
import { makeContext } from '../../engine/script/context';
import { describeEffect } from '../../engine/script/interpreter';
import type { Character } from '../../engine/types';
import { ageOf, charFullName } from '../../engine/world/characters';
import { opinion } from '../../engine/world/opinion';
import { skill } from '../../engine/world/stats';
import type { App } from '../app';
import { esc, h, signed } from '../dom';
import { button, charLink, descLinesHtml, modifiersHtml, portrait, section } from '../widgets';

/** Раздел «Совет» во вкладке владений игрока. */
export function renderCouncilSection(app: App, liege: Character): HTMLElement | null {
  const g = app.game!;
  const positions = councilPositions(g).filter((p) => isPositionShown(g, liege, p));
  if (!positions.length) return null;
  const mine = g.isPlayer(liege.id);
  const list = h('div', { class: 'council' });
  for (const pos of positions) {
    const seat = liege.council?.[pos.id];
    const holder = g.char(seat?.holder);
    const skillDef = g.content.get('skills', pos.skill);
    const row = h('div', { class: 'council-row' });
    row.append(
      h('div', { class: 'council-pos', tip: () => `<div class="tip-title">${esc(g.nameOf('council_positions', pos.id))}</div><p>${esc(g.descOf('council_positions', pos.id))}</p>` },
        h('span', { class: 'council-icon' }, pos.icon ?? '•'), ' ', g.nameOf('council_positions', pos.id)),
      holder
        ? h('div', { class: 'council-holder' }, portrait(app, holder, 34), h('div', null, charLink(app, holder.id), h('div', { class: 'muted' }, `${skillDef?.icon ?? ''} ${skill(g, holder, pos.skill)}`)))
        : h('div', { class: 'council-holder muted' }, app.t('ui.vacant')),
    );
    if (mine) {
      row.append(h('div', { class: 'council-btns' },
        button(app.t(holder ? 'ui.replace' : 'ui.appoint'), () => openCouncillorPicker(app, liege, pos.id), { cls: 'btn-small' }),
        holder ? button(app.t('ui.dismiss'), () => { dismissCouncillor(g, liege, pos.id); app.markDirty(true); }, { cls: 'btn-small btn-red' }) : null,
      ));
    }
    // задачи
    const tasks = h('div', { class: 'council-tasks' });
    for (const t of tasksOf(g, pos.id)) {
      const active = seat?.task === t.id;
      tasks.append(button(h('span', null, `${t.icon ?? '•'} `, g.nameOf('council_tasks', t.id)), () => {
        if (!mine || active) return;
        setCouncilTask(g, liege, pos.id, t.id);
        app.markDirty(true);
      }, { cls: `btn-small council-task ${active ? 'active' : ''}`, disabled: !mine && !active, tip: () => taskTooltip(app, liege, pos.id, t, holder) }));
    }
    row.append(tasks);
    list.append(row);
  }
  return section(app.t('ui.council'), h('p', { class: 'hint' }, app.t('ui.council_hint')), list);
}

function taskTooltip(app: App, liege: Character, posId: string, t: CouncilTaskDef, holder: Character | undefined): string {
  const g = app.game!;
  let html = `<div class="tip-title">${esc(t.icon ?? '')} ${esc(g.nameOf('council_tasks', t.id))}</div><p>${esc(g.descOf('council_tasks', t.id))}</p>`;
  if (holder) {
    const ctx = makeContext(g, { type: 'character', id: holder.id }, { liege: { type: 'character', id: liege.id }, councillor: { type: 'character', id: holder.id } });
    html += modifiersHtml(app, evalModifiers(ctx, ctx.root, t.liege_modifiers));
    if (t.monthly_effect) {
      const chance = liege.council?.[posId]?.task === t.id ? taskMonthlyChance(g, liege, posId) : undefined;
      if (chance != null) html += `<div class="muted">${esc(app.t('ui.task_monthly_chance', { n: Math.round(chance * 10) / 10 }))}</div>`;
      html += descLinesHtml(describeEffect(ctx, ctx.root, t.monthly_effect));
    }
  }
  return html;
}

function openCouncillorPicker(app: App, liege: Character, posId: string) {
  const g = app.game!;
  const pos = g.content.get('council_positions', posId)!;
  const cands = councilCandidates(g, liege, posId).filter((c) => c.id !== liege.council?.[posId]?.holder);
  const body = h('div', { class: 'interaction' }, h('h3', null, app.t('ui.choose_councillor', { position: g.nameOf('council_positions', posId) })));
  const list = h('div', { class: 'cand-list' });
  let close: () => void = () => {};
  for (const c of cands) {
    const other = councilPositionOf(g, c);
    list.append(h('div', {
      class: 'cand',
      onclick: () => {
        appointCouncillor(g, liege, posId, c.id);
        close();
        app.markDirty(true);
      },
    },
    portrait(app, c, 36, false),
    h('div', null, h('div', null, charFullName(g, c, true)), h('div', { class: 'muted' }, app.t('ui.age_n', { n: ageOf(g, c) }), other ? ` · ${g.nameOf('council_positions', other.position)}` : '')),
    h('span', { class: 'cand-skill' }, `${g.content.get('skills', pos.skill)?.icon ?? ''} ${skill(g, c, pos.skill)}`),
    h('span', { class: opinion(g, c, liege) >= 0 ? 'good' : 'bad' }, signed(opinion(g, c, liege))),
    ));
  }
  if (!cands.length) list.append(h('div', { class: 'muted' }, app.t('ui.no_council_candidates')));
  body.append(list, h('div', { class: 'modal-buttons' }, button(app.t('ui.cancel'), () => close())));
  close = app.modal(body, { cls: 'ia-modal' });
}

/** Строка «Маршал при дворе …» для окна персонажа. */
export function councilBadge(app: App, c: Character): HTMLElement | null {
  const g = app.game!;
  const pos = councilPositionOf(g, c);
  if (!pos) return null;
  const def = g.content.get('council_positions', pos.position);
  return h('div', { class: 'council-badge' }, `${def?.icon ?? ''} `, app.t('ui.councillor_of', { position: g.nameOf('council_positions', pos.position), liege: '' }), charLink(app, pos.liege.id, true));
}
