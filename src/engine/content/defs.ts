/**
 * Типы определений контента (то, что пишут моды в YAML/JSON).
 * Скриптовые блоки (триггеры/эффекты/значения) имеют тип ScriptBlock —
 * их интерпретирует скриптовый движок.
 */
import type { TextValue } from '../core/localization';
import type { Tier } from '../types';

export type ScriptBlock = any;
export type ValueExpr = number | string | Record<string, any>;

export interface Cost {
  gold?: ValueExpr;
  prestige?: ValueExpr;
  piety?: ValueExpr;
}

export interface SkillDef {
  id: string;
  name?: TextValue;
  icon?: string;
  color?: string;
  order?: number;
}

export interface TraitDef {
  id: string;
  name?: TextValue;
  desc?: TextValue;
  category: string;
  icon?: string;
  /** Модификаторы характеристик: diplomacy, fertility, monthly_prestige, ... */
  modifiers?: Record<string, number>;
  opposites?: string[];
  /** Мнение носителей этой черты о носителях других черт. */
  compatibility?: Record<string, number>;
  /** Наследуется ли (врождённые черты). */
  genetic?: boolean;
  inherit_chance?: number;
  /** Шанс получить при рождении, 0..1. */
  birth_chance?: number;
  /** Вес при случайном выборе личностных черт. */
  weight?: number;
  /** Для образования: навык и уровень. */
  education?: { skill: string; level: number };
  /** Личность ИИ: aggression, boldness, compassion, greed, honor, rationality, sociability, vengefulness, zeal, energy. */
  ai?: Record<string, number>;
  /** Сколько стресса получает персонаж, действуя вопреки черте (используется в событиях). */
  stress?: number;
  hidden?: boolean;
  /** Черта проходит сама по себе через N дней (болезни, раны). */
  duration_days?: number;
  /** Ежемесячный шанс смерти от черты. */
  monthly_death_chance?: number;
  /** Ежемесячный шанс исчезновения черты. */
  monthly_cure_chance?: number;
  [k: string]: any;
}

export interface CultureDef {
  id: string;
  name?: TextValue;
  group?: string;
  color: string;
  male_names: string[];
  female_names: string[];
  dynasty_names?: string[];
  skin?: [number, number];
  hair?: [number, number];
  succession_law?: string;
  modifiers?: Record<string, number>;
  [k: string]: any;
}

export interface FaithDef {
  id: string;
  name?: TextValue;
  religion?: string;
  color: string;
  icon?: string;
  doctrines?: Record<string, any>;
  virtues?: string[];
  sins?: string[];
  modifiers?: Record<string, number>;
  [k: string]: any;
}

export interface TerrainDef {
  id: string;
  name?: TextValue;
  color: string;
  /** Бонус обороны защитника (0.2 = +20%). */
  defense: number;
  /** Множитель времени перехода. */
  movement: number;
  /** Высота для рельефа карты 0..1. */
  height: number;
  development_growth?: number;
}

export interface HoldingDef {
  id: string;
  name?: TextValue;
  icon?: string;
  tax: number;
  levy: number;
  fort: number;
}

export interface BuildingDef {
  id: string;
  name?: TextValue;
  desc?: TextValue;
  icon?: string;
  holding?: string;
  requires?: string[];
  cost: Cost;
  days: number;
  /** Модификаторы провинции: tax_mult, levy_mult, fort, development_growth, ... */
  modifiers: Record<string, number>;
  /** Модификаторы владельца (персонажа). */
  owner_modifiers?: Record<string, number>;
  trigger?: ScriptBlock;
}

export interface ProvinceDef {
  id: string;
  name?: TextValue;
  lat?: number;
  lon?: number;
  pos?: [number, number];
  duchy?: string;
  terrain: string;
  culture: string;
  faith: string;
  development: number;
  holdings: string[];
  buildings?: string[];
  impassable?: boolean;
  color?: string;
  [k: string]: any;
}

export interface TitleDef {
  id: string;
  name?: TextValue;
  tier: Tier;
  liege?: string;
  color: string;
  capital?: string;
  coa?: any;
  /** Можно ли создать титул (дополнительное условие, скоуп — претендент). */
  can_create?: ScriptBlock;
  /** Титул создаётся только через решение/скрипт. */
  no_create?: boolean;
  /** Сгенерированное графство из провинции. */
  province?: string;
  [k: string]: any;
}

export interface SuccessionLawDef {
  id: string;
  name?: TextValue;
  desc?: TextValue;
  algorithm: string;
  gender: 'male_only' | 'male_preference' | 'equal' | 'female_preference' | 'female_only';
  can_change?: ScriptBlock;
  change_cost?: Cost;
  ai_will_do?: ValueExpr;
}

export interface CasusBelliDef {
  id: string;
  name?: TextValue;
  desc?: TextValue;
  icon?: string;
  /** Поставщик целей войны (реестр cbTargets): claim, de_jure, independence, holy_war... */
  targets: string;
  is_valid?: ScriptBlock;
  cost?: Cost;
  on_declare?: ScriptBlock;
  on_victory?: ScriptBlock;
  on_white_peace?: ScriptBlock;
  on_defeat?: ScriptBlock;
  ai_will_do?: ValueExpr;
  truce_years?: number;
  war_name?: TextValue;
  /** Повод не предлагается в обычном объявлении войны (только из скриптов и механик). */
  manual?: boolean;
}

export interface InteractionDef {
  id: string;
  name?: TextValue;
  desc?: TextValue;
  icon?: string;
  category?: string;
  /** Взаимодействие с самим собой (например, «Поднять налоги»). */
  self?: boolean;
  is_shown?: ScriptBlock;
  is_valid?: ScriptBlock;
  cost?: Cost;
  secondary_actor?: { list: string | string[]; trigger?: ScriptBlock; title?: TextValue };
  /** Поставщик вариантов выбора (реестр interactionTargets). */
  target?: { provider: string; title?: TextValue };
  auto_accept?: boolean | ScriptBlock;
  ai_accept?: ValueExpr;
  on_accept?: ScriptBlock;
  on_decline?: ScriptBlock;
  /** Кто решает: recipient (по умолчанию), guardian — сюзерен безземельного получателя, или id из registries.interactionDeciders (payer — плательщик выкупа). */
  decider?: string;
  /** Можно ли надавить крюком (по умолчанию — да, если есть ai_accept). */
  hookable?: boolean;
  /** Взаимодействие с пленником: never (по умолчанию) — недоступно, only — только с пленником, allowed — с любым. */
  prisoner?: 'never' | 'only' | 'allowed';
  /** Запускает интригу этого типа вместо обычного исполнения. */
  scheme?: string;
  ai_will_do?: ValueExpr;
  /** Кого ИИ рассматривает как получателя: список-ссылка (vassals, liege, rulers_nearby...). */
  ai_targets?: string | string[];
  ai_frequency_months?: number;
  cooldown?: { days?: number; months?: number; years?: number };
  accept_text?: TextValue;
  decline_text?: TextValue;
  [k: string]: any;
}

export interface SchemeDef {
  id: string;
  name?: TextValue;
  desc?: TextValue;
  icon?: string;
  category: 'hostile' | 'personal' | 'political';
  skill: string;
  is_valid?: ScriptBlock;
  /** Прогресс в месяц (0..100). */
  progress: ValueExpr;
  /** Шанс успеха в процентах. */
  success_chance: ValueExpr;
  /** Ежемесячный шанс раскрытия в процентах. */
  discovery_chance?: ValueExpr;
  on_success?: ScriptBlock;
  on_failure?: ScriptBlock;
  on_discovered?: ScriptBlock;
  ai_will_do?: ValueExpr;
  [k: string]: any;
}

export interface DecisionDef {
  id: string;
  name?: TextValue;
  desc?: TextValue;
  icon?: string;
  is_shown?: ScriptBlock;
  is_valid?: ScriptBlock;
  cost?: Cost;
  effect?: ScriptBlock;
  ai_will_do?: ValueExpr;
  ai_check_months?: number;
  cooldown?: { days?: number; months?: number; years?: number };
  major?: boolean;
  [k: string]: any;
}

export interface EventOptionDef {
  name?: TextValue;
  trigger?: ScriptBlock;
  effect?: ScriptBlock;
  ai_chance?: ValueExpr;
  tooltip?: TextValue;
}

export interface EventDef {
  id: string;
  title?: TextValue;
  desc?: TextValue | { trigger?: ScriptBlock; desc: TextValue }[];
  icon?: string;
  theme?: string;
  trigger?: ScriptBlock;
  weight?: ValueExpr;
  cooldown?: { days?: number; months?: number; years?: number };
  once?: boolean;
  hidden?: boolean;
  /** Только по вызову trigger_event / on_action, не в случайном пуле. */
  triggered_only?: boolean;
  immediate?: ScriptBlock;
  options?: EventOptionDef[];
  after?: ScriptBlock;
  [k: string]: any;
}

export interface OnActionDef {
  id: string;
  effect?: ScriptBlock;
  events?: string[];
  random_events?: { chance?: ValueExpr; events: Record<string, ValueExpr> | { event: string; weight?: ValueExpr }[] };
}

export interface OpinionModifierDef {
  id: string;
  name?: TextValue;
  value: number;
  /** Убывание по модулю за месяц. */
  decay?: number;
  /** Срок жизни в годах. */
  years?: number;
  months?: number;
  stacking?: boolean;
}

export interface ModifierDef {
  id: string;
  name?: TextValue;
  desc?: TextValue;
  icon?: string;
  modifiers: Record<string, number>;
  good?: boolean;
}

export interface MapModeDef {
  id: string;
  name?: TextValue;
  icon?: string;
  /** Скоуп — провинция. Значение, по которому красится карта. */
  value?: ValueExpr;
  min?: number;
  max?: number;
  gradient?: string[];
  order?: number;
}

export interface BookmarkDef {
  id: string;
  name?: TextValue;
  desc?: TextValue;
  date: string;
  /** титул → персонаж */
  holders: Record<string, string>;
  playable?: string[];
  /** персонаж → сюзерен (если отличается от автоматического по де-юре) */
  vassal_of?: Record<string, string | null>;
  generate_missing?: boolean;
  claims?: Record<string, string[]>;
  [k: string]: any;
}

export interface CharacterDef {
  id: string;
  name: string;
  nickname?: string;
  female?: boolean;
  birth: string;
  death?: string;
  dynasty?: string;
  culture: string;
  faith: string;
  father?: string;
  mother?: string;
  spouse?: string | string[];
  traits?: string[];
  skills?: Record<string, number>;
  gold?: number;
  prestige?: number;
  piety?: number;
  claims?: string[];
  court?: string;
  dna?: Partial<{ skin: number; hair: number; eyes: number; face: number }>;
  [k: string]: any;
}

export interface DynastyDef {
  id: string;
  name?: TextValue;
  culture?: string;
  prestige?: number;
  coa?: any;
}
