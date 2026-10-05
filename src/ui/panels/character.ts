import type { InteractionDef, TraitDef } from '../../engine/content/defs';
import { dateParts } from '../../engine/core/date';
import { ageOf, charFullName, siblingsOf, skillIds } from '../../engine/world/characters';
import { acceptance, interactionBlockers, interactionDefs, isInteractionShown, secondaryCandidates, targetOptions } from '../../engine/world/interactions';
import { opinion, opinionBreakdown } from '../../engine/world/opinion';
import { charStats, skill, statBreakdown } from '../../engine/world/stats';
import { heirsOf } from '../../engine/world/succession';
import { titleFullName, topLiege } from '../../engine/world/titles';
import { availableWarTargets } from '../../engine/world/war';
import type { App } from '../app';
import { type Child, esc, fmt, h, signed } from '../dom';
import { breakdownHtml, button, charLink, dynastyCoa, modifiersHtml, portrait, reasonsHtml, section, titleCoa, titleLink } from '../widgets';
import { openInteraction } from './interaction';
import { lifestyleSummary } from './lifestyle';
import { councilBadge } from './council';
import { secretsCharacterSection } from './secrets';
import { openDeclareWar } from './wars';

export function renderCharacterPanel(app: App, id: string): HTMLElement {
  const g = app.game!;
  const c = g.char(id);
  if (!c) return h('div', { class: 'muted' }, app.t('ui.unknown_character'));
  const p = g.player;
  const isMe = p?.id === c.id;
  const alive = c.death === undefined;
  const root = h('div', { class: 'char-panel' });

  // ---------------------------------------------------- шапка
  const age = ageOf(g, c);
  const info: Child[] = [
    h('div', { class: 'char-name' }, charFullName(g, c, true)),
    c.titles[0] ? h('div', { class: 'char-title' }, titleLink(app, c.titles[0])) : h('div', { class: 'muted' }, c.liege ? app.t('ui.courtier_of', { who: app.rankedName(c.liege) }) : app.t('ui.wanderer')),
    h('div', { class: 'muted' },
      alive ? app.t('ui.age_n', { n: age }) : app.t('ui.died', { date: fmtDate(app, c.death!), age, reason: app.t(`ui.death_reason.${c.deathReason ?? 'natural'}`) }),
      ' · ', g.nameOf('cultures', c.culture), ' · ', g.nameOf('faiths', c.faith),
    ),
  ];
  if (c.dynasty) {
    const d = g.state.dynasties[c.dynasty];
    info.push(h('div', { class: 'dyn-line', tip: app.t('ui.dynasty_prestige', { n: fmt(d?.prestige ?? 0) }) }, dynastyCoa(app, c.dynasty, 18), ' ', app.t('ui.dynasty_n', { name: g.nameOf('dynasties', c.dynasty) })));
  } else info.push(h('div', { class: 'muted' }, app.t('ui.lowborn')));
  const badge = councilBadge(app, c);
  if (badge) info.push(badge);
  if (c.prison) info.push(h('div', { class: 'bad prison-line' }, '⛓ ', app.t('ui.in_prison_of', { jailer: '' }), charLink(app, c.prison.by, true)));
  root.append(h('div', { class: 'char-head' }, portrait(app, c, 96, false), h('div', { class: 'char-info' }, ...info), c.titles[0] ? titleCoa(app, c.titles[0], 44) : null));

  if (app.pickMode && alive && c.titles.length) {
    root.append(button(app.t('ui.play_as'), () => app.setPlayer(c.id), { cls: 'btn-big btn-gold' }));
  }

  // ---------------------------------------------------- мнение
  if (p && !isMe && alive) {
    const theirs = opinion(g, c, p);
    const mine = opinion(g, p, c);
    root.append(h('div', { class: 'opinion-row' },
      h('span', { class: ['op', theirs >= 0 ? 'good' : 'bad'], tip: () => `<div class="tip-title">${esc(app.t('ui.opinion_of_you'))}</div>${breakdownHtml(opinionBreakdown(g, c, p))}` }, `${app.t('ui.opinion_of_you')}: ${signed(theirs)}`),
      h('span', { class: ['op', mine >= 0 ? 'good' : 'bad'], tip: () => `<div class="tip-title">${esc(app.t('ui.your_opinion'))}</div>${breakdownHtml(opinionBreakdown(g, p, c))}` }, `${app.t('ui.your_opinion')}: ${signed(mine)}`),
    ));
  }

  // ---------------------------------------------------- навыки и ресурсы
  const skills = h('div', { class: 'skills' });
  for (const s of skillIds(g)) {
    const def = g.content.get('skills', s);
    skills.append(h('div', { class: 'skill', tip: () => `<div class="tip-title">${esc(g.nameOf('skills', s))}</div>${breakdownHtml(statBreakdown(g, c, s).map((x) => ({ label: x.label, value: Math.round(x.value * 10) / 10 })))}` },
      h('span', { class: 'skill-icon', style: { color: def?.color } }, def?.icon ?? '•'), h('span', { class: 'skill-val' }, skill(g, c, s))));
  }
  root.append(skills);
  const st = charStats(g, c);
  root.append(h('div', { class: 'res-row' },
    h('span', { tip: app.t('ui.gold') }, `💰 ${fmt(c.gold)}`),
    h('span', { tip: app.t('ui.prestige') }, `⭐ ${fmt(c.prestige)}`),
    h('span', { tip: app.t('ui.piety') }, `✝ ${fmt(c.piety)}`),
    h('span', { tip: () => `<div class="tip-title">${esc(app.t('ui.health'))}</div>${breakdownHtml(statBreakdown(g, c, 'health'), 1)}` }, `❤ ${fmt(st.health ?? 0, 1)}`),
    h('span', { tip: app.t('ui.stress_tip') }, `😣 ${fmt(c.stress)}`),
  ));

  // ---------------------------------------------------- черты
  const traits = h('div', { class: 'traits' });
  for (const t of c.traits) {
    const def = g.content.get<TraitDef>('traits', t);
    if (!def || def.hidden) continue;
    traits.append(h('span', {
      class: `trait trait-${def.category}`,
      tip: () => `<div class="tip-title">${esc(def.icon ?? '')} ${esc(g.nameOf('traits', t))}</div><div class="muted">${esc(app.t(`ui.trait_category.${def.category}`))}</div>${g.descOf('traits', t) ? `<p>${esc(g.descOf('traits', t))}</p>` : ''}${modifiersHtml(app, def.modifiers)}`,
    }, def.icon ?? '◆'));
  }
  root.append(traits);
  if (c.modifiers.length) {
    root.append(h('div', { class: 'modifiers' }, ...c.modifiers.map((m) => {
      const def = g.content.get('modifiers', m.id);
      const left = m.expires ? Math.max(0, Math.round((m.expires - g.date) / 30)) : null;
      return h('span', { class: ['modifier', def?.good ? 'good' : 'bad'], tip: () => `<div class="tip-title">${esc(g.nameOf('modifiers', m.id))}</div>${left != null ? `<div class="muted">${esc(app.t('ui.months_left', { n: left }))}</div>` : ''}${modifiersHtml(app, def?.modifiers)}` }, `${def?.icon ?? '✦'} ${g.nameOf('modifiers', m.id)}`);
    })));
  }

  const ls = lifestyleSummary(app, c);
  if (ls) root.append(section(app.t('ui.lifestyle'), ls));
  const secrets = secretsCharacterSection(app, c);
  if (secrets) root.append(secrets);

  // ---------------------------------------------------- действия
  if (p && alive && !app.pickMode && !g.state.gameOver) {
    const acts = h('div', { class: 'actions' });
    for (const def of interactionDefs(g)) {
      if (!isInteractionShown(g, def, p, c)) continue;
      acts.append(interactionButton(app, def, p.id, c.id));
    }
    if (!isMe && c.titles.length) {
      const top = topLiege(g, c);
      const targets = availableWarTargets(g, p).filter((t) => t.defender === c.id || t.defender === top.id);
      if (targets.length) acts.append(button(h('span', null, '⚔ ', app.t('ui.declare_war')), () => openDeclareWar(app, targets[0].defender), { cls: 'act-btn war' }));
    }
    if (acts.children.length) root.append(section(app.t(isMe ? 'ui.self_actions' : 'ui.interactions'), acts));
  }

  // ---------------------------------------------------- родство
  const rel = h('div', { class: 'relations' });
  const row = (label: string, ...content: Child[]) => rel.append(h('div', { class: 'rel-row' }, h('span', { class: 'rel-label' }, label), h('span', { class: 'rel-val' }, ...content)));
  if (c.liege) row(app.t(c.titles.length ? 'ui.liege' : 'ui.court'), charLink(app, c.liege, true));
  if (c.titles.length && alive) {
    const heir = heirsOf(g, c)[0];
    row(app.t('ui.heir'), heir ? charLink(app, heir) : h('span', { class: 'bad' }, app.t('ui.no_heir')));
  }
  if (c.spouses.length) row(app.t('ui.spouse'), ...join(c.spouses.map((s) => charLink(app, s))));
  if (c.formerSpouses.length) row(app.t('ui.former_spouses'), ...join(c.formerSpouses.map((s) => charLink(app, s))));
  if (c.father || c.mother) row(app.t('ui.parents'), ...join([c.father, c.mother].filter(Boolean).map((x) => charLink(app, x))));
  if (c.children.length) row(app.t('ui.children'), ...join(c.children.filter((x) => g.char(x)).map((x) => charLink(app, x))));
  const sibs = siblingsOf(g, c);
  if (sibs.length) row(app.t('ui.siblings'), ...join(sibs.map((x) => charLink(app, x.id))));
  if (c.pregnancy) row(app.t('ui.pregnant'), app.t('ui.due', { date: fmtDate(app, c.pregnancy.due) }));
  root.append(section(app.t('ui.family'), rel));

  if (c.titles.length) root.append(section(app.t('ui.titles'), h('div', { class: 'title-list' }, ...c.titles.map((t) => h('div', { class: 'title-row' }, titleCoa(app, t, 20), titleLink(app, t))))));
  if (c.claims.length) root.append(section(app.t('ui.claims'), h('div', { class: 'title-list' }, ...c.claims.map((t) => h('div', { class: 'title-row' }, titleCoa(app, t, 20), titleLink(app, t), ' ', g.state.titles[t]?.holder ? h('span', { class: 'muted' }, '(', charLink(app, g.state.titles[t].holder), ')') : null)))));

  for (const s of g.engine.ui.characterSections.values().sort((a, b) => (a.order ?? 0) - (b.order ?? 0))) {
    try {
      const r = s.render(g, c.id, app);
      if (r) root.append(section(g.loc.resolve(s.title), typeof r === 'string' ? h('div', { html: r }) : r));
    } catch (e) {
      console.error(e);
    }
  }
  return root;
}

function join(items: Child[]): Child[] {
  const out: Child[] = [];
  items.forEach((it, i) => {
    if (i) out.push(', ');
    out.push(it);
  });
  return out;
}

export function fmtDate(app: App, n: number): string {
  const { y, m, d } = dateParts(n);
  return `${d} ${app.t(`month.${m}`)} ${y}`;
}

function interactionButton(app: App, def: InteractionDef, actorId: string, recipientId: string): HTMLElement {
  const g = app.game!;
  const actor = g.char(actorId)!;
  const recipient = g.char(recipientId)!;
  const needsChoice = !!def.secondary_actor || !!def.target;
  const blockers = interactionBlockers(g, def, actor, recipient);
  return button(h('span', null, `${def.icon ?? '•'} `, g.nameOf('interactions', def.id)), () => openInteraction(app, def, actorId, recipientId), {
    cls: `act-btn ${def.category ?? ''}`,
    disabled: blockers.length > 0,
    tip: () => {
      let html = `<div class="tip-title">${esc(g.nameOf('interactions', def.id))}</div>`;
      const desc = g.descOf('interactions', def.id);
      if (desc) html += `<p>${esc(desc)}</p>`;
      if (blockers.length) html += reasonsHtml(app, blockers);
      else if (!needsChoice) {
        const acc = acceptance(g, def, actor, recipient);
        if (!acc.auto) html += `<div class="${acc.total > 0 ? 'good' : 'bad'}">${esc(app.t(acc.total > 0 ? 'ui.will_accept' : 'ui.will_decline'))} (${signed(acc.total)})</div>`;
      } else {
        const n = def.secondary_actor ? secondaryCandidates(g, def, actor, recipient).length : targetOptions(g, def, actor, recipient).length;
        html += `<div class="muted">${esc(app.t('ui.options_n', { n }))}</div>`;
      }
      return html;
    },
  });
}

export { titleFullName };
