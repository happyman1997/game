// Пример JS-мода «Моровые поветрия».
// Скрипт получает api в init(api): реестры скриптового языка, систем,
// хуков, интерфейса и функции мира (api.world). Состояние мода хранится
// в game.modData('plague', ...) и автоматически попадает в сохранения.

const MOD = 'plague';

/** Состояние эпидемий в партии: { infected: { [provinceId]: { disease, months } }, outbreaks } */
function stateOf(game) {
  return game.modData(MOD, () => ({ infected: {}, outbreaks: 0 }));
}

export function init(api) {
  const { world } = api;

  // ------------------------------------------------ скриптовый язык
  api.script.trigger('province_has_disease', {
    scopes: ['province'],
    doc: 'В провинции эпидемия. Аргумент: yes или id болезни.',
    eval: (ctx, scope, arg) => {
      const e = stateOf(ctx.game).infected[scope.id];
      if (arg === 'no' || arg === false) return !e;
      return !!e && (arg === 'yes' || arg === true || e.disease === arg);
    },
  });
  api.script.trigger('capital_has_disease', {
    scopes: ['character'],
    doc: 'В столице персонажа (или его сюзерена) эпидемия.',
    eval: (ctx, scope, arg) => {
      const c = ctx.game.char(scope.id);
      const cap = c && homeOf(ctx.game, c);
      const yes = !!cap && !!stateOf(ctx.game).infected[cap];
      return arg === 'no' || arg === false ? !yes : yes;
    },
  });
  api.script.effect('start_disease', {
    scopes: ['province'],
    doc: 'Начать эпидемию в провинции: start_disease: bubonic_plague',
    apply: (ctx, scope, arg) => infect(ctx.game, scope.id, typeof arg === 'string' && arg !== 'yes' ? arg : 'bubonic_plague'),
    describe: (ctx, scope) => (ctx.game.loc.lang === 'ru' ? `${ctx.game.scopeName(scope)}: вспышка болезни` : `${ctx.game.scopeName(scope)}: disease outbreak`),
  });
  api.script.value('infected_provinces', {
    doc: 'Число заражённых провинций в мире.',
    get: (ctx) => Object.keys(stateOf(ctx.game).infected).length,
  });

  // ------------------------------------------------ система симуляции
  api.systems.add({
    id: 'plague',
    order: 65,
    onMonth(game) {
      const st = stateOf(game);
      const diseases = game.content.all('diseases');
      // новые вспышки
      for (const d of diseases) {
        if (game.rng.next() < (d.outbreak_chance ?? 0)) {
          const provs = Object.keys(game.state.provinces);
          const p = game.rng.pick(provs);
          if (p && !st.infected[p]) infect(game, p, d.id);
        }
      }
      // распространение, смерти, затухание
      for (const [prov, e] of Object.entries(st.infected)) {
        const d = game.content.get('diseases', e.disease);
        if (!d) {
          delete st.infected[prov];
          continue;
        }
        const quarantined = game.state.provinces[prov]?.modifiers.some((m) => m.id === 'quarantine');
        for (const n of game.engine.neighbors(prov)) {
          if (st.infected[n]) continue;
          const nq = game.state.provinces[n]?.modifiers.some((m) => m.id === 'quarantine');
          const chance = (d.spread_chance ?? 0.1) * (quarantined ? 0.3 : 1) * (nq ? 0.3 : 1);
          if (game.rng.next() < chance) infect(game, n, e.disease);
        }
        const deathChance = (d.monthly_death_chance ?? 0.02) * (quarantined ? 0.4 : 1);
        for (const c of [...game.living()]) {
          if (homeOf(game, c) !== prov || game.rng.next() >= deathChance) continue;
          world.succession.killCharacter(game, c, 'plague');
        }
        e.months += 1;
        if (e.months >= (d.duration_months ?? 12)) {
          delete st.infected[prov];
          const p = game.state.provinces[prov];
          if (p) {
            p.development = Math.max(0, p.development - (d.development_loss ?? 0));
            p.modifiers.push({ id: 'plague_aftermath', expires: game.date + 365 * 2 });
          }
        }
      }
      game.notify('map');
    },
  });

  // ------------------------------------------------ модификатор: страх эпидемии
  api.registries.modifierProviders.register('plague_fear', {
    label: { ru: 'Страх эпидемии', en: 'Fear of pestilence' },
    fn: (game, c) => {
      const cap = homeOf(game, c);
      return cap && stateOf(game).infected[cap] ? { stress_gain_mult: 0.25, fertility: -0.2 } : null;
    },
  });

  // ------------------------------------------------ интерфейс
  api.ui.mapModes.register('plague', {
    id: 'plague',
    name: { ru: 'Эпидемии', en: 'Epidemics' },
    icon: '☠',
    order: 90,
    color: (game, p) => {
      const e = stateOf(game).infected[p];
      if (e) return game.content.get('diseases', e.disease)?.color ?? '#7a1f1f';
      return game.state.provinces[p]?.modifiers.some((m) => m.id === 'plague_aftermath') ? '#6a5a4a' : '#b8b0a0';
    },
    tooltip: (game, p) => {
      const e = stateOf(game).infected[p];
      return e ? `${game.nameOf('diseases', e.disease)} (${e.months})` : null;
    },
  });
  api.ui.topBar.register('plague', {
    id: 'plague',
    order: 10,
    render: (game) => {
      const n = Object.keys(stateOf(game).infected).length;
      if (!n) return null;
      return { icon: '☠', text: String(n), tooltip: game.loc.t('plague.widget_tip', { n }) };
    },
  });
  api.ui.panels.register('plague', {
    id: 'plague',
    name: { ru: 'Эпидемии', en: 'Epidemics' },
    icon: '☠',
    order: 50,
    render: (game, ui) => {
      const st = stateOf(game);
      const rows = Object.entries(st.infected)
        .map(([p, e]) => `<div class="msg" data-prov="${p}">☠ <b>${game.nameOf('provinces', p)}</b> — ${game.nameOf('diseases', e.disease)}, ${game.loc.t('plague.months', { n: e.months })}</div>`)
        .join('');
      const el = document.createElement('div');
      el.innerHTML = `<p class="hint">${game.loc.t('plague.panel_hint')}</p><p>${game.loc.t('plague.outbreaks', { n: st.outbreaks })}</p>${rows || `<p class="muted">${game.loc.t('plague.none')}</p>`}`;
      el.querySelectorAll('[data-prov]').forEach((r) => r.addEventListener('click', () => ui.openProvince(r.getAttribute('data-prov'), true)));
      return el;
    },
  });
  api.ui.provinceSections.register('plague', {
    id: 'plague',
    title: { ru: 'Эпидемия', en: 'Epidemic' },
    render: (game, prov) => {
      const e = stateOf(game).infected[prov];
      return e ? `☠ ${game.nameOf('diseases', e.disease)} — ${game.loc.t('plague.months', { n: e.months })}` : null;
    },
  });

  api.log('мод загружен: болезней —', api.content.all('diseases').length);
}

/** Где живёт персонаж: столица правителя или его двора. */
function homeOf(game, c) {
  if (c.titles.length) return c.capital;
  const l = game.char(c.liege);
  return l?.capital;
}

function infect(game, prov, disease) {
  const st = stateOf(game);
  if (st.infected[prov] || !game.state.provinces[prov]) return;
  st.infected[prov] = { disease, months: 0 };
  st.outbreaks += 1;
  const holder = game.char(game.state.titles[prov]?.holder);
  const player = game.player;
  if (holder && player && (holder.id === player.id || holder.liege === player.id)) {
    game.message(game.loc.t('plague.msg_outbreak', { place: game.nameOf('provinces', prov), disease: game.nameOf('diseases', disease) }), 'bad', { type: 'province', id: prov });
    if (holder.id === player.id && player.capital === prov) game.events.trigger('plague.0001', { type: 'character', id: player.id }, {});
  }
  game.emit('plague.outbreak', { province: prov, disease });
}
