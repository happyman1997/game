/**
 * Встроенная библиотека скриптового языка. Регистрируется в реестрах
 * точно так же, как это делают моды, — поэтому любой элемент можно
 * переопределить.
 */
import type { SuccessionLawDef, TraitDef } from '../content/defs';
import { durationDays } from '../core/date';
import { isPlainObject } from '../core/merge';
import type { Engine } from '../engine';
import type { Game } from '../game';
import type { Character, ScopeRef } from '../types';
import {
  addTrait,
  ageOf,
  canMarry,
  createCharacter,
  divorce,
  isAdult,
  isAlive,
  isCloseFamily,
  isParentOf,
  isSibling,
  isTooCloseToMarry,
  marry,
  removeTrait,
  setLiege,
  siblingsOf,
} from '../world/characters';
import { countyLevy, countyTax, domainLimit, monthlyIncome, realmLevy } from '../world/economy';
import { provinceFort } from '../world/military';
import { addOpinion, opinion, removeOpinion } from '../world/opinion';
import { startScheme } from '../world/schemes';
import { charStats, stat } from '../world/stats';
import { heirsOf, killCharacter, lawOf } from '../world/succession';
import {
  becomeUnlanded,
  capitalOf,
  deJureCounties,
  deJureVassalTitles,
  domainCounties,
  isInRealmOf,
  primaryTier,
  provinceController,
  realmCounties,
  realmMembers,
  tierOf,
  topLiege,
  transferTitle,
} from '../world/titles';
import { alliesOf, endWar, enemiesOf, hasTruce, isAllied, isAtWar, isAtWarWith, warsOf } from '../world/war';
import { type ScriptContext, isYes, sameScope } from './context';
import { compare, evalTrigger, evalValue, resolveScope } from './interpreter';

const CHAR: ['character'] = ['character'];
const PROV: ['province'] = ['province'];
const TITLE: ['title'] = ['title'];

function ch(ctx: ScriptContext, s: ScopeRef | null | undefined): Character | undefined {
  return s?.type === 'character' ? ctx.game.char(s.id) : undefined;
}
function cref(id: string | undefined | null): ScopeRef | null {
  return id ? { type: 'character', id } : null;
}
function targetChar(ctx: ScriptContext, scope: ScopeRef, arg: unknown): Character | undefined {
  return ch(ctx, resolveScope(ctx, scope, arg));
}
function num(ctx: ScriptContext, scope: ScopeRef, arg: unknown): number {
  return evalValue(ctx, scope, isPlainObject(arg) && 'value' in arg && Object.keys(arg).length === 1 ? arg.value : arg);
}
function signed(n: number): string {
  const r = Math.round(n * 10) / 10;
  return r > 0 ? `+${r}` : `${r}`;
}

export function registerBuiltins(engine: Engine): void {
  const { triggers, effects, values, links, lists, constants } = engine.script;
  const t = (game: Game, key: string, params?: Record<string, unknown>) => game.loc.t(key, params);

  // ============================================================ константы
  constants.register('county', 1).register('duchy', 2).register('kingdom', 3).register('empire', 4);

  // ============================================================ ссылки
  const link = (name: string, from: any, fn: (ctx: ScriptContext, s: ScopeRef) => ScopeRef | null | undefined, doc: string) =>
    links.register(name, { from, resolve: fn, doc });

  link('liege', CHAR, (ctx, s) => cref(ch(ctx, s)?.liege), 'Сюзерен (или владелец двора для придворных)');
  link('employer', CHAR, (ctx, s) => cref(ch(ctx, s)?.liege), 'Синоним liege');
  link('top_liege', CHAR, (ctx, s) => { const c = ch(ctx, s); return c ? cref(topLiege(ctx.game, c).id) : null; }, 'Верховный сюзерен');
  link('father', CHAR, (ctx, s) => cref(ch(ctx, s)?.father), 'Отец');
  link('mother', CHAR, (ctx, s) => cref(ch(ctx, s)?.mother), 'Мать');
  link('spouse', CHAR, (ctx, s) => cref(ch(ctx, s)?.spouses[0]), 'Супруг(а) (первый)');
  link('killer', CHAR, (ctx, s) => cref(ch(ctx, s)?.killer), 'Убийца');
  link('primary_heir', CHAR, (ctx, s) => { const c = ch(ctx, s); return c ? cref(heirsOf(ctx.game, c)[0]) : null; }, 'Основной наследник');
  link('primary_title', CHAR, (ctx, s) => { const c = ch(ctx, s); return c?.titles[0] ? { type: 'title', id: c.titles[0] } : null; }, 'Основной титул');
  link('capital', CHAR, (ctx, s) => { const c = ch(ctx, s); const cap = c ? capitalOf(ctx.game, c) : undefined; return cap ? { type: 'province', id: cap } : null; }, 'Столица (провинция)');
  link('dynasty', CHAR, (ctx, s) => { const c = ch(ctx, s); return c?.dynasty ? { type: 'dynasty', id: c.dynasty } : null; }, 'Династия');
  link('player', undefined, (ctx) => cref(ctx.game.state.player), 'Персонаж игрока');
  link('holder', ['title', 'province'], (ctx, s) => cref(ctx.game.state.titles[s.id]?.holder), 'Владелец титула/графства');
  link('controller', PROV, (ctx, s) => cref(provinceController(ctx.game, s.id)?.id), 'Кто контролирует провинцию');
  link('county', PROV, (ctx, s) => (ctx.game.state.titles[s.id] ? { type: 'title', id: s.id } : null), 'Графство провинции');
  link('province', TITLE, (ctx, s) => (ctx.game.state.provinces[s.id] ? { type: 'province', id: s.id } : null), 'Провинция графства');
  link('de_jure_liege', TITLE, (ctx, s) => { const l = ctx.game.content.get('titles', s.id)?.liege; return l ? { type: 'title', id: l } : null; }, 'Де-юре сюзеренный титул');
  link('capital_province', TITLE, (ctx, s) => { const c = ctx.game.content.get('titles', s.id)?.capital; return c ? { type: 'province', id: c } : null; }, 'Столица титула');
  link('owner', ['scheme', 'army'], (ctx, s) => cref(s.type === 'scheme' ? ctx.game.state.schemes[s.id]?.owner : ctx.game.state.armies[s.id]?.owner), 'Владелец интриги/армии');
  link('target', ['scheme'], (ctx, s) => cref(ctx.game.state.schemes[s.id]?.target), 'Цель интриги');
  link('attacker', ['war'], (ctx, s) => cref(ctx.game.state.wars[s.id]?.attacker), 'Нападающий');
  link('defender', ['war'], (ctx, s) => cref(ctx.game.state.wars[s.id]?.defender), 'Защитник');
  link('founder', ['dynasty'], (ctx, s) => cref(ctx.game.state.dynasties[s.id]?.founder), 'Основатель династии');

  // ============================================================ списки
  const list = (name: string, from: any, fn: (ctx: ScriptContext, s: ScopeRef) => ScopeRef[], doc: string) =>
    lists.register(name, { from, list: fn, doc });
  const chars = (arr: (Character | undefined)[]) => arr.filter(isAlive).map((c) => ({ type: 'character' as const, id: c.id }));

  list('self', undefined, (_ctx, s) => [s], 'Сам этот объект (удобно для списков кандидатов)');
  list('child', CHAR, (ctx, s) => chars((ch(ctx, s)?.children ?? []).map((id) => ctx.game.char(id))), 'Живые дети');
  list('son', CHAR, (ctx, s) => chars((ch(ctx, s)?.children ?? []).map((id) => ctx.game.char(id)).filter((c) => c && !c.female)), 'Сыновья');
  list('daughter', CHAR, (ctx, s) => chars((ch(ctx, s)?.children ?? []).map((id) => ctx.game.char(id)).filter((c) => c?.female)), 'Дочери');
  list('spouse', CHAR, (ctx, s) => chars((ch(ctx, s)?.spouses ?? []).map((id) => ctx.game.char(id))), 'Супруги');
  list('parent', CHAR, (ctx, s) => { const c = ch(ctx, s); return chars([ctx.game.char(c?.father), ctx.game.char(c?.mother)]); }, 'Родители');
  list('sibling', CHAR, (ctx, s) => { const c = ch(ctx, s); return c ? chars(siblingsOf(ctx.game, c)) : []; }, 'Братья и сёстры');
  list('grandchild', CHAR, (ctx, s) => {
    const c = ch(ctx, s);
    return c ? chars(c.children.flatMap((id) => ctx.game.char(id)?.children ?? []).map((id) => ctx.game.char(id))) : [];
  }, 'Внуки');
  list('close_family', CHAR, (ctx, s) => {
    const c = ch(ctx, s);
    if (!c) return [];
    const g = ctx.game;
    const ids = new Set<string>([...c.children, ...c.spouses, c.father ?? '', c.mother ?? '', ...siblingsOf(g, c).map((x) => x.id)]);
    return chars([...ids].map((id) => g.char(id)));
  }, 'Близкая семья (супруги, дети, родители, братья/сёстры)');
  list('vassal', CHAR, (ctx, s) => chars(ctx.game.vassalsOf(s.id)), 'Прямые вассалы');
  list('realm_vassal', CHAR, (ctx, s) => { const c = ch(ctx, s); return c ? chars(realmMembers(ctx.game, c).filter((x) => x.id !== c.id)) : []; }, 'Все вассалы державы');
  list('courtier', CHAR, (ctx, s) => chars(ctx.game.courtiersOf(s.id)), 'Придворные');
  list('dynasty_member', CHAR, (ctx, s) => { const c = ch(ctx, s); return c?.dynasty ? chars(ctx.game.living().filter((x) => x.dynasty === c.dynasty && x.id !== c.id)) : []; }, 'Живые члены династии');
  list('ally', CHAR, (ctx, s) => chars(alliesOf(ctx.game, s.id).map((id) => ctx.game.char(id))), 'Союзники');
  list('war_enemy', CHAR, (ctx, s) => chars(enemiesOf(ctx.game, s.id).map((id) => ctx.game.char(id))), 'Враги по войнам');
  list('held_title', CHAR, (ctx, s) => (ch(ctx, s)?.titles ?? []).map((id) => ({ type: 'title' as const, id })), 'Титулы');
  list('claim', CHAR, (ctx, s) => (ch(ctx, s)?.claims ?? []).map((id) => ({ type: 'title' as const, id })), 'Претензии');
  list('domain_province', CHAR, (ctx, s) => { const c = ch(ctx, s); return c ? domainCounties(ctx.game, c).map((id) => ({ type: 'province' as const, id })) : []; }, 'Провинции домена');
  list('realm_province', CHAR, (ctx, s) => { const c = ch(ctx, s); return c ? realmCounties(ctx.game, c).map((id) => ({ type: 'province' as const, id })) : []; }, 'Провинции державы');
  list('neighboring_ruler', CHAR, (ctx, s) => {
    const c = ch(ctx, s);
    if (!c) return [];
    const g = ctx.game;
    const top = topLiege(g, c);
    const mine = new Set(realmCounties(g, top));
    const out = new Set<string>();
    for (const p of mine) for (const n of g.engine.neighbors(p)) {
      if (mine.has(n)) continue;
      const h = g.char(g.state.titles[n]?.holder);
      if (h) out.add(topLiege(g, h).id);
    }
    out.delete(c.id);
    return chars([...out].map((id) => g.char(id)));
  }, 'Независимые правители по соседству');
  list('ruler', undefined, (ctx) => chars(ctx.game.rulers()), 'Все правители (глобально)');
  list('independent_ruler', undefined, (ctx) => chars(ctx.game.rulers().filter((r) => !r.liege)), 'Независимые правители');
  list('living_character', undefined, (ctx) => chars(ctx.game.living()), 'Все живые персонажи');
  list('province', undefined, (ctx) => Object.keys(ctx.game.state.provinces).map((id) => ({ type: 'province' as const, id })), 'Все провинции');
  list('war', undefined, (ctx) => Object.keys(ctx.game.state.wars).map((id) => ({ type: 'war' as const, id })), 'Все войны');
  list('neighbor', PROV, (ctx, s) => ctx.game.engine.neighbors(s.id).map((id) => ({ type: 'province' as const, id })), 'Соседние провинции');
  list('de_jure_vassal_title', TITLE, (ctx, s) => deJureVassalTitles(ctx.game, s.id).map((id) => ({ type: 'title' as const, id })), 'Де-юре вассальные титулы');
  list('de_jure_county', TITLE, (ctx, s) => deJureCounties(ctx.game, s.id).map((id) => ({ type: 'title' as const, id })), 'Де-юре графства');

  // ============================================================ значения
  const val = (name: string, scopes: any, fn: (ctx: ScriptContext, s: ScopeRef, arg?: ScopeRef | null) => number, doc: string) =>
    values.register(name, { scopes, get: fn, doc });
  const cv = (name: string, fn: (g: Game, c: Character, arg?: ScopeRef | null, ctx?: ScriptContext) => number, doc: string) =>
    val(name, CHAR, (ctx, s, arg) => { const c = ch(ctx, s); return c ? fn(ctx.game, c, arg, ctx) : 0; }, doc);

  cv('age', (g, c) => ageOf(g, c), 'Возраст');
  cv('gold', (_g, c) => c.gold, 'Золото');
  cv('prestige', (_g, c) => c.prestige, 'Престиж');
  cv('piety', (_g, c) => c.piety, 'Благочестие');
  cv('stress', (_g, c) => c.stress, 'Стресс');
  cv('stress_level', (_g, c) => Math.floor(c.stress / 100), 'Уровень стресса (стресс / 100)');
  cv('health', (g, c) => stat(g, c, 'health'), 'Здоровье');
  cv('fertility', (g, c) => stat(g, c, 'fertility'), 'Плодовитость');
  cv('attraction', (g, c) => stat(g, c, 'attraction_opinion'), 'Привлекательность');
  cv('num_children', (g, c) => c.children.filter((id) => g.isAlive(id)).length, 'Число живых детей');
  cv('num_spouses', (_g, c) => c.spouses.length, 'Число супругов');
  cv('num_vassals', (g, c) => g.vassalsOf(c.id).length, 'Число прямых вассалов');
  cv('num_courtiers', (g, c) => g.courtiersOf(c.id).length, 'Число придворных');
  cv('num_counties', (g, c) => domainCounties(g, c).length, 'Графств в домене');
  cv('realm_size', (g, c) => realmCounties(g, c).length, 'Графств в державе');
  cv('domain_limit', (g, c) => domainLimit(g, c), 'Лимит домена');
  cv('levies', (g, c) => realmLevy(g, c), 'Ополчение державы');
  cv('income', (g, c) => monthlyIncome(g, c), 'Ежемесячный доход');
  cv('tier', (g, c) => primaryTier(g, c), 'Ранг основного титула (0 — нет земель, 1 — граф ... 4 — император)');
  cv('num_claims', (_g, c) => c.claims.length, 'Число претензий');
  cv('num_wars', (g, c) => warsOf(g, c.id).length, 'Число войн');
  cv('num_traits', (_g, c) => c.traits.length, 'Число черт');
  cv('dynasty_prestige', (g, c) => (c.dynasty ? g.state.dynasties[c.dynasty]?.prestige ?? 0 : 0), 'Престиж династии');
  cv('opinion', (g, c, arg) => { const o = arg?.type === 'character' ? g.char(arg.id) : undefined; return o ? opinion(g, c, o) : 0; }, 'Мнение о персонаже: opinion(scope:x)');
  cv('reverse_opinion', (g, c, arg) => { const o = arg?.type === 'character' ? g.char(arg.id) : undefined; return o ? opinion(g, o, c) : 0; }, 'Мнение персонажа-аргумента об этом персонаже');
  cv('levy_ratio', (_g, c) => c.levyRatio, 'Доля восстановленных ополчений');
  for (const k of ['aggression', 'boldness', 'compassion', 'greed', 'honor', 'rationality', 'sociability', 'vengefulness', 'zeal', 'energy']) {
    cv(`ai_${k}`, (g, c) => {
      let v = 0;
      for (const tr of c.traits) v += g.content.get<TraitDef>('traits', tr)?.ai?.[k] ?? 0;
      return v;
    }, `Личность ИИ: ${k}`);
  }
  cv('stat', () => 0, 'Устарело: используйте имя характеристики');

  val('development', PROV, (ctx, s) => ctx.game.state.provinces[s.id]?.development ?? 0, 'Развитие провинции');
  val('tax', PROV, (ctx, s) => countyTax(ctx.game, s.id), 'Налог провинции');
  val('levy', PROV, (ctx, s) => countyLevy(ctx.game, s.id), 'Ополчение провинции');
  val('fort_level', PROV, (ctx, s) => provinceFort(ctx.game, s.id), 'Уровень укреплений');
  val('num_buildings', PROV, (ctx, s) => ctx.game.state.provinces[s.id]?.buildings.length ?? 0, 'Число построек');
  val('num_holdings', PROV, (ctx, s) => ctx.game.content.get('provinces', s.id)?.holdings?.length ?? 0, 'Число владений');
  val('title_tier', TITLE, (ctx, s) => tierOf(ctx.game, s.id), 'Ранг титула');
  val('num_de_jure_counties', TITLE, (ctx, s) => deJureCounties(ctx.game, s.id).length, 'Де-юре графств в титуле');
  val('current_year', undefined, (ctx) => Math.floor(ctx.game.date / 365), 'Текущий год');
  val('days_since_start', undefined, (ctx) => ctx.game.date - ctx.game.state.startDate, 'Дней с начала партии');
  val('war_duration_days', ['war'], (ctx, s) => ctx.game.date - (ctx.game.state.wars[s.id]?.start ?? ctx.game.date), 'Длительность войны');
  val('scheme_progress', ['scheme'], (ctx, s) => ctx.game.state.schemes[s.id]?.progress ?? 0, 'Прогресс интриги');

  // Навыки и любые характеристики регистрируются по данным (skills) — см. registerSkillValues.

  // ============================================================ триггеры
  const trig = (name: string, scopes: any, fn: (ctx: ScriptContext, s: ScopeRef, arg: any) => boolean, doc: string, describe?: (ctx: ScriptContext, s: ScopeRef, arg: any) => string) =>
    triggers.register(name, { scopes, eval: fn, doc, describe });
  const ct = (name: string, fn: (g: Game, c: Character, arg: any, ctx: ScriptContext, s: ScopeRef) => boolean, doc: string, describe?: (ctx: ScriptContext, s: ScopeRef, arg: any) => string) =>
    trig(name, CHAR, (ctx, s, arg) => { const c = ch(ctx, s); return !!c && fn(ctx.game, c, arg, ctx, s); }, doc, describe);
  const yesno = (name: string, fn: (g: Game, c: Character) => boolean, doc: string) =>
    ct(name, (g, c, arg) => fn(g, c) === (arg == null || isYes(arg)), doc, (ctx, _s, arg) => t(ctx.game, `tr.${name}${arg == null || isYes(arg) ? '' : '.not'}`));

  yesno('is_alive', (_g, c) => c.death === undefined, 'Жив');
  yesno('is_female', (_g, c) => c.female, 'Женщина');
  yesno('is_male', (_g, c) => !c.female, 'Мужчина');
  yesno('is_adult', (g, c) => isAdult(g, c), 'Совершеннолетний');
  yesno('is_child', (g, c) => !isAdult(g, c), 'Ребёнок');
  yesno('is_ruler', (_g, c) => c.titles.length > 0, 'Владеет землями');
  yesno('is_landed', (_g, c) => c.titles.length > 0, 'Владеет землями');
  yesno('is_independent', (_g, c) => c.titles.length > 0 && !c.liege, 'Независимый правитель');
  yesno('is_vassal', (_g, c) => c.titles.length > 0 && !!c.liege, 'Вассал');
  yesno('is_courtier', (_g, c) => !c.titles.length && !!c.liege, 'Придворный');
  yesno('is_married', (_g, c) => c.spouses.length > 0, 'В браке');
  yesno('is_pregnant', (_g, c) => !!c.pregnancy, 'Беременна');
  yesno('is_player', (g, c) => g.isPlayer(c.id), 'Персонаж игрока');
  yesno('is_ai', (g, c) => !g.isPlayer(c.id), 'Персонаж ИИ');
  yesno('is_lowborn', (_g, c) => !c.dynasty, 'Безродный');
  yesno('is_at_war', (g, c) => isAtWar(g, c.id), 'Ведёт войну');
  yesno('has_any_claim', (_g, c) => c.claims.length > 0, 'Есть претензии');

  ct('has_trait', (_g, c, arg) => (Array.isArray(arg) ? arg.some((x) => c.traits.includes(x)) : c.traits.includes(String(arg))), 'Есть черта',
    (ctx, _s, arg) => t(ctx.game, 'tr.has_trait', { value: (Array.isArray(arg) ? arg : [arg]).map((x: string) => ctx.game.nameOf('traits', x)).join(' / ') }));
  ct('has_trait_category', (g, c, arg) => c.traits.some((x) => g.content.get<TraitDef>('traits', x)?.category === arg), 'Есть черта категории');
  ct('has_modifier', (_g, c, arg) => c.modifiers.some((m) => m.id === arg), 'Есть модификатор',
    (ctx, _s, arg) => t(ctx.game, 'tr.has_modifier', { value: ctx.game.nameOf('modifiers', arg) }));
  ct('has_flag', (g, c, arg) => { const v = c.flags[String(arg)]; return v !== undefined && (v === 0 || v > g.date); }, 'Есть флаг');
  trig('has_global_flag', undefined, (ctx, _s, arg) => { const v = ctx.game.state.globalFlags[String(arg)]; return v !== undefined && (v === 0 || v > ctx.game.date); }, 'Есть глобальный флаг');
  ct('has_var', (_g, c, arg) => String(arg) in c.vars, 'Есть переменная');
  trig('var', undefined, (ctx, s, arg) => {
    const holder = s.type === 'character' ? ctx.game.char(s.id)?.vars : s.type === 'province' ? ctx.game.state.provinces[s.id]?.vars : undefined;
    const v = Number(holder?.[arg.name] ?? 0);
    return compare(ctx, s, v, arg.value ?? '!= 0');
  }, 'Сравнение переменной: var: { name: x, value: ">= 2" }');
  trig('global_var', undefined, (ctx, s, arg) => compare(ctx, s, Number(ctx.game.state.globalVars[arg.name] ?? 0), arg.value ?? '!= 0'), 'Сравнение глобальной переменной');
  trig('culture', ['character', 'province'], (ctx, s, arg) => {
    const v = s.type === 'character' ? ctx.game.char(s.id)?.culture : ctx.game.state.provinces[s.id]?.culture;
    return Array.isArray(arg) ? arg.includes(v) : v === arg;
  }, 'Культура равна', (ctx, _s, arg) => t(ctx.game, 'tr.culture', { value: ctx.game.nameOf('cultures', arg) }));
  trig('faith', ['character', 'province'], (ctx, s, arg) => {
    const v = s.type === 'character' ? ctx.game.char(s.id)?.faith : ctx.game.state.provinces[s.id]?.faith;
    return Array.isArray(arg) ? arg.includes(v) : v === arg;
  }, 'Вера равна', (ctx, _s, arg) => t(ctx.game, 'tr.faith', { value: ctx.game.nameOf('faiths', arg) }));
  trig('religion', CHAR, (ctx, s, arg) => ctx.game.content.get('faiths', ch(ctx, s)?.faith ?? '')?.religion === arg, 'Религия равна');
  ct('dynasty', (_g, c, arg) => c.dynasty === arg, 'Династия равна');
  ct('same_culture_as', (_g, c, arg, ctx, s) => targetChar(ctx, s, arg)?.culture === c.culture, 'Та же культура');
  ct('same_faith_as', (_g, c, arg, ctx, s) => targetChar(ctx, s, arg)?.faith === c.faith, 'Та же вера', (ctx) => t(ctx.game, 'tr.same_faith_as'));
  ct('same_dynasty_as', (_g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && !!c.dynasty && o.dynasty === c.dynasty; }, 'Та же династия');
  ct('is_spouse_of', (_g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && c.spouses.includes(o.id); }, 'Супруг(а) персонажа');
  ct('is_parent_of', (_g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && isParentOf(c, o); }, 'Родитель персонажа');
  ct('is_child_of', (_g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && isParentOf(o, c); }, 'Ребёнок персонажа');
  ct('is_sibling_of', (_g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && isSibling(c, o); }, 'Брат/сестра персонажа');
  ct('is_close_family_of', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && (isCloseFamily(g, c, o) || c.spouses.includes(o.id)); }, 'Близкая семья');
  ct('is_close_relative_of', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && isTooCloseToMarry(g, c, o); }, 'Слишком близкое родство для брака');
  ct('is_vassal_of', (_g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && c.titles.length > 0 && c.liege === o.id; }, 'Прямой вассал персонажа',
    (ctx) => t(ctx.game, 'tr.is_vassal_of'));
  ct('is_liege_of', (_g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && o.liege === c.id && o.titles.length > 0; }, 'Сюзерен персонажа');
  ct('is_courtier_of', (_g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && !c.titles.length && c.liege === o.id; }, 'Придворный персонажа');
  ct('is_in_realm_of', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && isInRealmOf(g, c, o); }, 'Состоит в державе персонажа');
  ct('is_at_war_with', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && isAtWarWith(g, c.id, o.id); }, 'Воюет с персонажем');
  ct('is_allied_with', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && isAllied(g, c.id, o.id); }, 'Союзник персонажа');
  ct('has_truce_with', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && hasTruce(g, c.id, o.id); }, 'Перемирие с персонажем');
  ct('is_heir_of', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && heirsOf(g, o)[0] === c.id; }, 'Основной наследник персонажа');
  ct('can_marry', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && canMarry(g, c, o); }, 'Может вступить в брак с персонажем',
    (ctx) => t(ctx.game, 'tr.can_marry'));
  ct('has_hook_on', (_g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); return !!o && c.hooks.some((h) => h.target === o.id); }, 'Есть крюк на персонажа');
  ct('has_claim_on', (_g, c, arg, ctx, s) => { const r = resolveScope(ctx, s, arg); return !!r && c.claims.includes(r.id); }, 'Есть претензия на титул');
  ct('holds_title', (_g, c, arg, ctx, s) => { const r = resolveScope(ctx, s, arg); return !!r && c.titles.includes(r.id); }, 'Владеет титулом');
  ct('has_scheme', (g, c, arg, ctx, s) => {
    const tgt = isPlainObject(arg) && arg.target ? resolveScope(ctx, s, arg.target)?.id : undefined;
    const type = isPlainObject(arg) ? arg.type : arg === 'yes' || arg === true ? undefined : arg;
    return Object.values(g.state.schemes).some((x) => x.owner === c.id && (!type || x.type === type) && (!tgt || x.target === tgt));
  }, 'Ведёт интригу: has_scheme: murder или { type, target }');
  ct('is_scheme_target', (g, c, arg) => Object.values(g.state.schemes).some((x) => x.target === c.id && (!arg || arg === 'yes' || arg === true || x.type === arg)), 'Является целью интриги');
  ct('has_opinion_modifier', (_g, c, arg, ctx, s) => {
    const o = targetChar(ctx, s, arg.target);
    return !!o && !!c.opinions[o.id]?.some((e) => e.mod === arg.modifier);
  }, 'Есть модификатор мнения: { target, modifier }');
  ct('has_succession_law', (g, c, arg) => lawOf(g, c)?.id === arg, 'Закон наследования');
  ct('is_primary_heir', (g, c) => !!c.liege && heirsOf(g, g.char(c.liege)!)[0] === c.id, 'Основной наследник своего сюзерена/отца');

  trig('has_building', PROV, (ctx, s, arg) => !!ctx.game.state.provinces[s.id]?.buildings.includes(arg), 'Есть постройка');
  trig('has_holding', PROV, (ctx, s, arg) => !!ctx.game.content.get('provinces', s.id)?.holdings?.includes(arg), 'Есть владение типа');
  trig('terrain', PROV, (ctx, s, arg) => ctx.game.content.get('provinces', s.id)?.terrain === arg, 'Местность');
  trig('is_occupied', PROV, (ctx, s, arg) => !!ctx.game.state.provinces[s.id]?.occupant === (arg == null || isYes(arg)), 'Оккупирована');
  trig('is_coastal', PROV, (ctx, s, arg) => {
    const m = ctx.game.map;
    const i = m.index.get(s.id);
    return (i !== undefined && !!m.coastal[i]) === (arg == null || isYes(arg));
  }, 'Прибрежная');
  trig('has_province_modifier', PROV, (ctx, s, arg) => !!ctx.game.state.provinces[s.id]?.modifiers.some((m) => m.id === arg), 'Есть модификатор провинции');
  trig('has_province_flag', PROV, (ctx, s, arg) => String(arg) in (ctx.game.state.provinces[s.id]?.flags ?? {}), 'Есть флаг провинции');
  trig('is_held', TITLE, (ctx, s, arg) => !!ctx.game.state.titles[s.id]?.holder === (arg == null || isYes(arg)), 'У титула есть владелец');
  trig('tier_is', TITLE, (ctx, s, arg) => ctx.game.content.get('titles', s.id)?.tier === arg, 'Ранг титула: county/duchy/kingdom/empire');

  // ============================================================ эффекты
  const eff = (name: string, scopes: any, apply: (ctx: ScriptContext, s: ScopeRef, arg: any) => void, doc: string, describe?: (ctx: ScriptContext, s: ScopeRef, arg: any) => string | string[] | null) =>
    effects.register(name, { scopes, apply, doc, describe });
  const ce = (name: string, apply: (g: Game, c: Character, arg: any, ctx: ScriptContext, s: ScopeRef) => void, doc: string, describe?: (ctx: ScriptContext, s: ScopeRef, arg: any) => string | string[] | null) =>
    eff(name, CHAR, (ctx, s, arg) => { const c = ch(ctx, s); if (c) apply(ctx.game, c, arg, ctx, s); }, doc, describe);
  const resource = (name: string, field: 'gold' | 'prestige' | 'piety') =>
    ce(name, (g, c, arg, ctx, s) => {
      c[field] += num(ctx, s, arg);
      if (field === 'prestige' && c.dynasty && num(ctx, s, arg) > 0) {
        const d = g.state.dynasties[c.dynasty];
        if (d) d.prestige += num(ctx, s, arg) * (g.defines.economy?.dynasty_prestige_share ?? 0.1);
      }
    }, `Изменить ${field}`, (ctx, s, arg) => t(ctx.game, `fx.${name}`, { value: signed(num(ctx, s, arg)) }));
  resource('add_gold', 'gold');
  resource('add_prestige', 'prestige');
  resource('add_piety', 'piety');
  ce('add_stress', (g, c, arg, ctx, s) => {
    let v = num(ctx, s, arg);
    if (v > 0) v *= Math.max(0, 1 + stat(g, c, 'stress_gain_mult'));
    c.stress = Math.max(0, c.stress + v);
  }, 'Изменить стресс', (ctx, s, arg) => t(ctx.game, 'fx.add_stress', { value: signed(num(ctx, s, arg)) }));
  ce('add_health', (g, c, arg, ctx, s) => { c.health += num(ctx, s, arg); g.statCache.delete(c.id); }, 'Изменить базовое здоровье',
    (ctx, s, arg) => t(ctx.game, 'fx.add_health', { value: signed(num(ctx, s, arg)) }));
  ce('add_dynasty_prestige', (g, c, arg, ctx, s) => { const d = c.dynasty ? g.state.dynasties[c.dynasty] : undefined; if (d) d.prestige += num(ctx, s, arg); }, 'Престиж династии',
    (ctx, s, arg) => t(ctx.game, 'fx.add_dynasty_prestige', { value: signed(num(ctx, s, arg)) }));
  ce('add_skill', (g, c, arg, ctx, s) => { c.skills[arg.skill] = Math.max(0, (c.skills[arg.skill] ?? 0) + num(ctx, s, arg.value ?? 1)); g.statCache.delete(c.id); },
    'Навсегда изменить навык: { skill, value }', (ctx, s, arg) => t(ctx.game, 'fx.add_skill', { skill: ctx.game.nameOf('skills', arg.skill), value: signed(num(ctx, s, arg.value ?? 1)) }));
  ce('add_trait', (g, c, arg) => { addTrait(g, c, String(arg)); }, 'Добавить черту',
    (ctx, s, arg) => (ch(ctx, s)?.traits.includes(arg) ? null : t(ctx.game, 'fx.add_trait', { value: ctx.game.nameOf('traits', arg) })));
  ce('remove_trait', (g, c, arg) => { removeTrait(g, c, String(arg)); }, 'Убрать черту',
    (ctx, s, arg) => (ch(ctx, s)?.traits.includes(arg) ? t(ctx.game, 'fx.remove_trait', { value: ctx.game.nameOf('traits', arg) }) : null));
  ce('add_modifier', (g, c, arg) => {
    const id = typeof arg === 'string' ? arg : arg.id;
    const days = typeof arg === 'string' ? 0 : durationDays(arg);
    c.modifiers = c.modifiers.filter((m) => m.id !== id);
    c.modifiers.push({ id, expires: days ? g.date + days : undefined });
    g.statCache.delete(c.id);
  }, 'Добавить модификатор: id или { id, years/months/days }', (ctx, _s, arg) => {
    const id = typeof arg === 'string' ? arg : arg.id;
    const days = typeof arg === 'string' ? 0 : durationDays(arg);
    const mods = ctx.game.content.get('modifiers', id)?.modifiers ?? {};
    const detail = Object.entries(mods).map(([k, v]) => `${ctx.game.loc.tOr(`stat.${k}`, k)} ${signed(v as number)}`).join(', ');
    return t(ctx.game, days ? 'fx.add_modifier_timed' : 'fx.add_modifier', { value: ctx.game.nameOf('modifiers', id), days: Math.round(days / 30), detail });
  });
  ce('remove_modifier', (g, c, arg) => { c.modifiers = c.modifiers.filter((m) => m.id !== arg); g.statCache.delete(c.id); }, 'Убрать модификатор',
    (ctx, _s, arg) => t(ctx.game, 'fx.remove_modifier', { value: ctx.game.nameOf('modifiers', arg) }));
  const opinionArgs = (ctx: ScriptContext, s: ScopeRef, arg: any) => ({ o: targetChar(ctx, s, arg.target ?? arg.who), mod: arg.modifier ?? 'generic', value: arg.value != null ? num(ctx, s, arg.value) : undefined });
  ce('add_opinion', (g, c, arg, ctx, s) => { const a = opinionArgs(ctx, s, arg); if (a.o) addOpinion(g, c, a.o, a.mod, a.value); },
    'Мнение этого персонажа о target: { target, modifier, value? }', (ctx, s, arg) => {
      const a = opinionArgs(ctx, s, arg);
      const v = a.value ?? ctx.game.content.get('opinion_modifiers', a.mod)?.value ?? 0;
      return a.o ? t(ctx.game, 'fx.add_opinion', { who: ctx.game.scopeName(s), target: ctx.game.scopeName({ type: 'character', id: a.o.id }), value: signed(v), mod: ctx.game.nameOf('opinion_modifiers', a.mod) }) : null;
    });
  ce('reverse_add_opinion', (g, c, arg, ctx, s) => { const a = opinionArgs(ctx, s, arg); if (a.o) addOpinion(g, a.o, c, a.mod, a.value); },
    'Мнение target об этом персонаже: { target, modifier, value? }', (ctx, s, arg) => {
      const a = opinionArgs(ctx, s, arg);
      const v = a.value ?? ctx.game.content.get('opinion_modifiers', a.mod)?.value ?? 0;
      return a.o ? t(ctx.game, 'fx.add_opinion', { who: ctx.game.scopeName({ type: 'character', id: a.o.id }), target: ctx.game.scopeName(s), value: signed(v), mod: ctx.game.nameOf('opinion_modifiers', a.mod) }) : null;
    });
  ce('remove_opinion', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg.target); if (o) removeOpinion(g, c, o, arg.modifier); }, 'Убрать модификатор мнения: { target, modifier }');
  const flagArgs = (g: Game, arg: any) => {
    const name = typeof arg === 'string' ? arg : arg.name ?? arg.flag;
    const days = typeof arg === 'string' ? 0 : durationDays(arg);
    return { name, value: days ? g.date + days : 0 };
  };
  ce('set_flag', (g, c, arg) => { const f = flagArgs(g, arg); c.flags[f.name] = f.value; }, 'Установить флаг: name или { name, days/months/years }', () => null);
  ce('remove_flag', (_g, c, arg) => { delete c.flags[String(arg)]; }, 'Убрать флаг', () => null);
  eff('set_global_flag', undefined, (ctx, _s, arg) => { const f = flagArgs(ctx.game, arg); ctx.game.state.globalFlags[f.name] = f.value; }, 'Глобальный флаг', () => null);
  eff('remove_global_flag', undefined, (ctx, _s, arg) => { delete ctx.game.state.globalFlags[String(arg)]; }, 'Убрать глобальный флаг', () => null);
  const varHolder = (ctx: ScriptContext, s: ScopeRef) =>
    s.type === 'character' ? ctx.game.char(s.id)?.vars : s.type === 'province' ? ctx.game.state.provinces[s.id]?.vars : ctx.game.state.globalVars;
  eff('set_var', undefined, (ctx, s, arg) => { const h = varHolder(ctx, s); if (h) h[arg.name] = typeof arg.value === 'string' && !/[.:]/.test(arg.value) && Number.isNaN(Number(arg.value)) && !ctx.game.engine.script.values.has(arg.value) ? arg.value : evalValue(ctx, s, arg.value ?? 1); }, 'Переменная: { name, value }', () => null);
  eff('change_var', undefined, (ctx, s, arg) => { const h = varHolder(ctx, s); if (h) h[arg.name] = Number(h[arg.name] ?? 0) + evalValue(ctx, s, arg.add ?? arg.value ?? 1); }, 'Изменить переменную: { name, add }', () => null);
  eff('remove_var', undefined, (ctx, s, arg) => { const h = varHolder(ctx, s); if (h) delete h[String(arg)]; }, 'Удалить переменную', () => null);
  eff('set_global_var', undefined, (ctx, s, arg) => { ctx.game.state.globalVars[arg.name] = evalValue(ctx, s, arg.value ?? 1); }, 'Глобальная переменная', () => null);

  ce('death', (g, c, arg, ctx, s) => {
    const reason = isPlainObject(arg) ? arg.reason ?? 'natural' : typeof arg === 'string' && arg !== 'yes' ? arg : 'natural';
    const killer = isPlainObject(arg) && arg.killer ? targetChar(ctx, s, arg.killer)?.id : undefined;
    killCharacter(g, c, reason, killer);
  }, 'Смерть: yes, причина или { reason, killer }', (ctx, s) => t(ctx.game, 'fx.death', { who: ctx.game.scopeName(s) }));
  ce('add_claim', (_g, c, arg, ctx, s) => { const r = resolveScope(ctx, s, arg); if (r?.type === 'title' && !c.claims.includes(r.id)) c.claims.push(r.id); },
    'Претензия на титул', (ctx, s, arg) => { const r = resolveScope(ctx, s, arg); return r ? t(ctx.game, 'fx.add_claim', { value: ctx.game.scopeName(r) }) : null; });
  ce('remove_claim', (_g, c, arg, ctx, s) => { const r = resolveScope(ctx, s, arg); if (r) c.claims = c.claims.filter((x) => x !== r.id); }, 'Убрать претензию');
  ce('marry', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); if (o && canMarry(g, c, o)) marry(g, c, o); }, 'Заключить брак',
    (ctx, s, arg) => { const o = targetChar(ctx, s, arg); return o ? t(ctx.game, 'fx.marry', { a: ctx.game.scopeName(s), b: ctx.game.scopeName({ type: 'character', id: o.id }) }) : null; });
  ce('divorce', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); if (o) divorce(g, c, o); }, 'Развод');
  ce('add_hook', (g, c, arg, ctx, s) => {
    const o = targetChar(ctx, s, arg.target ?? arg);
    if (!o) return;
    c.hooks = c.hooks.filter((h) => h.target !== o.id);
    const days = isPlainObject(arg) ? durationDays(arg) : 0;
    c.hooks.push({ target: o.id, strong: isPlainObject(arg) && isYes(arg.strong), expires: days ? g.date + days : undefined });
  }, 'Крюк на персонажа: path или { target, strong, years }', (ctx, s, arg) => {
    const o = targetChar(ctx, s, arg.target ?? arg);
    return o ? t(ctx.game, 'fx.add_hook', { value: ctx.game.scopeName({ type: 'character', id: o.id }) }) : null;
  });
  ce('remove_hook', (_g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); if (o) c.hooks = c.hooks.filter((h) => h.target !== o.id); }, 'Убрать крюк');
  ce('become_vassal_of', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); if (o && o.id !== c.id && !isInRealmOf(g, o, c)) setLiege(g, c, o.id); }, 'Стать вассалом',
    (ctx, s, arg) => { const o = targetChar(ctx, s, arg); return o ? t(ctx.game, 'fx.become_vassal_of', { who: ctx.game.scopeName(s), liege: ctx.game.scopeName({ type: 'character', id: o.id }) }) : null; });
  ce('become_independent', (g, c) => setLiege(g, c, undefined), 'Стать независимым', (ctx, s) => t(ctx.game, 'fx.become_independent', { who: ctx.game.scopeName(s) }));
  ce('move_to_court', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); if (o && !c.titles.length) setLiege(g, c, o.titles.length ? o.id : o.liege); }, 'Переехать ко двору персонажа',
    (ctx, s, arg) => { const o = targetChar(ctx, s, arg); return o ? t(ctx.game, 'fx.move_to_court', { who: ctx.game.scopeName(s), court: ctx.game.scopeName({ type: 'character', id: o.id }) }) : null; });
  ce('add_courtier', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); if (o && !o.titles.length) setLiege(g, o, c.id); }, 'Принять ко двору');
  ce('gain_title', (g, c, arg, ctx, s) => { const r = resolveScope(ctx, s, arg); if (r?.type === 'title' || r?.type === 'province') transferTitle(g, r.id, c.id); }, 'Получить титул',
    (ctx, s, arg) => { const r = resolveScope(ctx, s, arg); return r ? t(ctx.game, 'fx.gain_title', { who: ctx.game.scopeName(s), value: ctx.game.scopeName({ type: 'title', id: r.id }) }) : null; });
  ce('give_title', (g, c, arg, ctx, s) => {
    const title = resolveScope(ctx, s, arg.title);
    const to = targetChar(ctx, s, arg.to);
    if (!title || !to || !c.titles.includes(title.id)) return;
    transferTitle(g, title.id, to.id);
    if (to.liege !== c.id && to.id !== c.id && !isInRealmOf(g, c, to) && primaryTier(g, to) < primaryTier(g, c)) setLiege(g, to, c.id);
  }, 'Пожаловать титул: { title, to } — получатель становится вассалом', (ctx, s, arg) => {
    const title = resolveScope(ctx, s, arg.title);
    const to = targetChar(ctx, s, arg.to);
    return title && to ? t(ctx.game, 'fx.give_title', { value: ctx.game.scopeName({ type: 'title', id: title.id }), to: ctx.game.scopeName({ type: 'character', id: to.id }) }) : null;
  });
  ce('lose_title', (g, c, arg, ctx, s) => {
    const r = resolveScope(ctx, s, arg);
    if (r && c.titles.includes(r.id)) transferTitle(g, r.id, c.liege);
  }, 'Потерять титул (переходит к сюзерену)');
  ce('take_title', (g, c, arg, ctx, s) => {
    const r = resolveScope(ctx, s, arg.title ?? arg);
    const from = arg.from ? targetChar(ctx, s, arg.from) : undefined;
    if (!r) return;
    const holder = g.state.titles[r.id]?.holder;
    if (from && holder !== from.id) return;
    transferTitle(g, r.id, c.id, { court: c.id });
  }, 'Отобрать титул себе: { title, from? }', (ctx, s, arg) => {
    const r = resolveScope(ctx, s, arg.title ?? arg);
    return r ? t(ctx.game, 'fx.gain_title', { who: ctx.game.scopeName(s), value: ctx.game.scopeName({ type: 'title', id: r.id }) }) : null;
  });
  ce('annex_war_targets', (g, c, _arg, ctx) => {
    const war = ctx.scopes.war ? g.state.wars[ctx.scopes.war.id] : undefined;
    if (!war) return;
    const defender = g.char(war.defender);
    for (const county of war.targetCounties) {
      const h = g.char(g.state.titles[county]?.holder);
      if (!h || (defender && !isInRealmOf(g, h, defender))) continue;
      if (h.id === c.id || isInRealmOf(g, h, c)) continue;
      if (h.id === defender?.id || primaryTier(g, h) >= primaryTier(g, c)) transferTitle(g, county, c.id, { court: c.id });
      else setLiege(g, h, c.id);
    }
    // Титулы защитника, все земли которых теперь у победителя, тоже переходят к нему.
    if (defender && defender.death === undefined) {
      const mine = new Set(realmCounties(g, c));
      for (const tt of [...defender.titles]) {
        if (tierOf(g, tt) < 2) continue;
        const dj = deJureCounties(g, tt);
        if (dj.length && dj.every((x) => mine.has(x) || !g.state.titles[x]?.holder)) transferTitle(g, tt, c.id, { court: c.id });
      }
    }
  }, 'Присоединить цели войны (в контексте войны)', (ctx) => t(ctx.game, 'fx.annex_war_targets'));
  ce('lose_all_titles', (g, c) => { for (const tt of [...c.titles]) transferTitle(g, tt, c.liege); if (!c.titles.length) becomeUnlanded(g, c, c.liege); }, 'Потерять все титулы');
  ce('set_succession_law', (g, c, arg) => { if (g.content.get<SuccessionLawDef>('succession_laws', arg)) c.successionLaw = arg; }, 'Закон наследования',
    (ctx, _s, arg) => t(ctx.game, 'fx.set_succession_law', { value: ctx.game.nameOf('succession_laws', arg) }));
  ce('make_pregnant', (g, c, arg, ctx, s) => { const f = targetChar(ctx, s, arg.father ?? arg); if (f && c.female && !c.pregnancy) c.pregnancy = { father: f.id, due: g.date + (g.defines.character?.pregnancy_days ?? 270) }; }, 'Беременность: { father }', () => null);
  ce('add_alliance', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); if (o && o.id !== c.id && !isAllied(g, c.id, o.id)) g.state.alliances.push({ a: c.id, b: o.id, since: g.date }); }, 'Союз с персонажем',
    (ctx, _s, arg) => { const o = targetChar(ctx, _s, arg); return o ? t(ctx.game, 'fx.add_alliance', { value: ctx.game.scopeName({ type: 'character', id: o.id }) }) : null; });
  ce('break_alliance', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg); if (o) g.state.alliances = g.state.alliances.filter((a) => !((a.a === c.id && a.b === o.id) || (a.a === o.id && a.b === c.id))); }, 'Разорвать союз');
  ce('pay_gold', (_g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg.target); const v = num(ctx, s, arg.value); if (o) { c.gold -= v; o.gold += v; } }, 'Передать золото: { target, value }',
    (ctx, s, arg) => { const o = targetChar(ctx, s, arg.target); return o ? t(ctx.game, 'fx.pay_gold', { value: Math.round(num(ctx, s, arg.value)), to: ctx.game.scopeName({ type: 'character', id: o.id }) }) : null; });
  ce('start_scheme', (g, c, arg, ctx, s) => { const o = targetChar(ctx, s, arg.target); if (o) startScheme(g, arg.type, c, o); }, 'Начать интригу: { type, target }');
  ce('set_nickname', (_g, c, arg) => { c.nickname = String(arg); }, 'Прозвище (ключ локализации или текст)', (ctx, s, arg) => t(ctx.game, 'fx.set_nickname', { who: ctx.game.scopeName(s), value: ctx.game.loc.resolve(arg) }));
  ce('send_message', (g, c, arg, ctx) => {
    if (!g.isPlayer(c.id)) return;
    const text = typeof arg === 'string' ? arg : arg.text;
    g.message(g.text(text, ctx), (isPlainObject(arg) ? arg.kind : undefined) ?? 'event');
  }, 'Сообщение игроку (если этот персонаж — игрок)', () => null);
  ce('create_character', (g, c, arg, ctx, s) => {
    const a = isPlainObject(arg) ? arg : {};
    const court = a.court ? targetChar(ctx, s, a.court) : c;
    let dynasty: string | 'new' | null = null;
    if (a.dynasty === 'new') dynasty = 'new';
    else if (a.dynasty && a.dynasty !== 'none') dynasty = targetChar(ctx, s, a.dynasty)?.dynasty ?? null;
    const age = a.age != null ? evalValue(ctx, s, a.age) : g.rng.int(18, 40);
    const n = createCharacter(g, {
      culture: a.culture ?? c.culture,
      faith: a.faith ?? c.faith,
      female: a.female != null ? (a.female === 'random' ? undefined : isYes(a.female)) : undefined,
      age,
      name: a.name,
      dynasty,
      traits: a.traits,
      liege: court ? (court.titles.length ? court.id : court.liege) : undefined,
    });
    if (a.save_scope_as) ctx.scopes[a.save_scope_as] = { type: 'character', id: n.id };
  }, 'Создать персонажа: { culture, faith, female, age, traits, dynasty: new|none|path, court, save_scope_as }', () => null);
  eff('end_war', undefined, (ctx, s, arg) => {
    const w = ctx.scopes.war ? ctx.game.state.wars[ctx.scopes.war.id] : s.type === 'war' ? ctx.game.state.wars[s.id] : undefined;
    if (w) endWar(ctx.game, w, (isPlainObject(arg) ? arg.outcome : arg) ?? 'white_peace');
  }, 'Завершить войну: victory/white_peace/defeat');
  eff('change_culture', ['character', 'province'], (ctx, s, arg) => {
    if (s.type === 'character') { const c = ch(ctx, s); if (c) c.culture = arg; } else { const p = ctx.game.state.provinces[s.id]; if (p) p.culture = arg; }
  }, 'Сменить культуру', (ctx, s, arg) => t(ctx.game, 'fx.change_culture', { who: ctx.game.scopeName(s), value: ctx.game.nameOf('cultures', arg) }));
  eff('change_faith', ['character', 'province'], (ctx, s, arg) => {
    if (s.type === 'character') { const c = ch(ctx, s); if (c) c.faith = arg; } else { const p = ctx.game.state.provinces[s.id]; if (p) p.faith = arg; }
  }, 'Сменить веру', (ctx, s, arg) => t(ctx.game, 'fx.change_faith', { who: ctx.game.scopeName(s), value: ctx.game.nameOf('faiths', arg) }));
  eff('add_development', PROV, (ctx, s, arg) => { const p = ctx.game.state.provinces[s.id]; if (p) p.development = Math.max(0, p.development + num(ctx, s, arg)); }, 'Изменить развитие',
    (ctx, s, arg) => t(ctx.game, 'fx.add_development', { place: ctx.game.scopeName(s), value: signed(num(ctx, s, arg)) }));
  eff('add_building', PROV, (ctx, s, arg) => { const p = ctx.game.state.provinces[s.id]; if (p && !p.buildings.includes(arg)) { p.buildings.push(arg); ctx.game.statCache.clear(); } }, 'Добавить постройку',
    (ctx, s, arg) => t(ctx.game, 'fx.add_building', { place: ctx.game.scopeName(s), value: ctx.game.nameOf('buildings', arg) }));
  eff('remove_building', PROV, (ctx, s, arg) => { const p = ctx.game.state.provinces[s.id]; if (p) p.buildings = p.buildings.filter((b) => b !== arg); ctx.game.statCache.clear(); }, 'Убрать постройку');
  eff('add_province_modifier', PROV, (ctx, s, arg) => {
    const p = ctx.game.state.provinces[s.id];
    if (!p) return;
    const id = typeof arg === 'string' ? arg : arg.id;
    const days = typeof arg === 'string' ? 0 : durationDays(arg);
    p.modifiers = p.modifiers.filter((m) => m.id !== id);
    p.modifiers.push({ id, expires: days ? ctx.game.date + days : undefined });
    ctx.game.statCache.clear();
  }, 'Модификатор провинции', (ctx, s, arg) => t(ctx.game, 'fx.add_province_modifier', { place: ctx.game.scopeName(s), value: ctx.game.nameOf('modifiers', typeof arg === 'string' ? arg : arg.id) }));
  eff('remove_province_modifier', PROV, (ctx, s, arg) => { const p = ctx.game.state.provinces[s.id]; if (p) p.modifiers = p.modifiers.filter((m) => m.id !== arg); ctx.game.statCache.clear(); }, 'Убрать модификатор провинции');
  eff('set_province_flag', PROV, (ctx, s, arg) => { const p = ctx.game.state.provinces[s.id]; if (p) { const f = flagArgs(ctx.game, arg); p.flags[f.name] = f.value; } }, 'Флаг провинции', () => null);

  // Проверка: тот же скоуп
  trig('is_same_as', undefined, (ctx, s, arg) => sameScope(s, resolveScope(ctx, s, arg)), 'Тот же объект, что и путь');
  // Шанс-триггер для данных (детерминирован RNG партии)
  trig('random_chance', undefined, (ctx, s, arg) => ctx.game.rng.next() * 100 < evalValue(ctx, s, arg), 'Случайный шанс в процентах (используйте осторожно в триггерах)');
  void evalTrigger;
  void charStats;
}

/** Регистрирует навыки и характеристики из данных (skills) как значения. */
export function registerSkillValues(engine: Engine): void {
  for (const s of engine.content.all('skills')) {
    engine.script.values.register(s.id, {
      scopes: ['character'],
      doc: `Навык: ${s.id}`,
      get: (ctx, scope) => {
        const c = ctx.game.char(scope.id);
        return c ? Math.max(0, Math.round(stat(ctx.game, c, s.id))) : 0;
      },
    });
  }
  for (const key of engine.content.singleton('defines').script_stat_values ?? []) {
    if (engine.script.values.has(key)) continue;
    engine.script.values.register(key, {
      scopes: ['character'],
      doc: `Характеристика: ${key}`,
      get: (ctx, scope) => {
        const c = ctx.game.char(scope.id);
        return c ? stat(ctx.game, c, key) : 0;
      },
    });
  }
}
