/**
 * Типы игрового состояния. Всё состояние — обычные JSON-объекты без классов,
 * поэтому сохранение игры — это просто JSON.stringify(state).
 */
import type { RngState } from './core/rng';

export type ScopeType = 'character' | 'title' | 'province' | 'dynasty' | 'war' | 'scheme' | 'army' | 'faction' | 'none';

/** Ссылка на объект мира — так «скоупы» хранятся в событиях и контекстах. */
export interface ScopeRef {
  type: ScopeType;
  id: string;
}

export type Tier = 'county' | 'duchy' | 'kingdom' | 'empire';
export const TIERS: Tier[] = ['county', 'duchy', 'kingdom', 'empire'];
export function tierRank(t: Tier | undefined | null): number {
  return t ? TIERS.indexOf(t) + 1 : 0;
}

export interface OpinionEntry {
  mod: string;
  value: number;
  expires?: number;
}

export interface TimedModifier {
  id: string;
  expires?: number;
}

export interface Hook {
  target: string;
  strong?: boolean;
  expires?: number;
}

export interface Character {
  id: string;
  /** Имя: сырой вариант (Harold); перевод берётся из ключа локализации name.Harold. */
  name: string;
  nickname?: string;
  female: boolean;
  birth: number;
  death?: number;
  deathReason?: string;
  killer?: string;
  dynasty?: string;
  culture: string;
  faith: string;
  traits: string[];
  skills: Record<string, number>;
  gold: number;
  prestige: number;
  piety: number;
  stress: number;
  health: number;
  father?: string;
  mother?: string;
  spouses: string[];
  formerSpouses: string[];
  children: string[];
  /** Для правителей — сюзерен; для безземельных — владелец двора, где они живут. */
  liege?: string;
  /** Удерживаемые титулы, от старшего к младшему. Первый — основной. */
  titles: string[];
  capital?: string;
  claims: string[];
  opinions: Record<string, OpinionEntry[]>;
  modifiers: TimedModifier[];
  hooks: Hook[];
  flags: Record<string, number>;
  vars: Record<string, any>;
  pregnancy?: { father: string; due: number };
  /** Генетика для портретов: значения 0..1. */
  dna: { skin: number; hair: number; eyes: number; face: number };
  successionLaw?: string;
  /** Доля доступных ополчений (0..1), восстанавливается после войн. */
  levyRatio: number;
  /** Образ жизни: фокус, опыт по образам жизни, открытые перки. */
  lifestyle?: LifestyleState;
  /** Совет правителя: должность → место. */
  council?: Record<string, CouncilSeat>;
  /** Заключение: кто держит в темнице. */
  prison?: PrisonState;
  /** Профессиональные войска (отряды). */
  regiments?: Regiment[];
}

export interface LifestyleState {
  focus?: string;
  /** Когда фокус был выбран (для перерыва между сменами). */
  focusSince?: number;
  xp: Record<string, number>;
  perks: string[];
}

export interface CouncilSeat {
  holder?: string;
  task?: string;
  since?: number;
}

export interface PrisonState {
  by: string;
  since: number;
  /** Двор, к которому персонаж принадлежал до заключения. */
  home?: string;
  war?: string;
}

export interface Regiment {
  id: string;
  type: string;
  size: number;
}

export interface Faction {
  id: string;
  type: string;
  /** Против кого (сюзерен). */
  target: string;
  leader: string;
  members: string[];
  claimant?: string;
  discontent: number;
  created: number;
  /** Ультиматум предъявлен (ждём ответа игрока). */
  ultimatum?: boolean;
}

export interface Dynasty {
  id: string;
  name: string;
  culture?: string;
  prestige: number;
  founder?: string;
  coa?: any;
}

export interface TitleState {
  id: string;
  holder?: string;
  history: { holder: string; from: number }[];
}

export interface ProvinceState {
  id: string;
  culture: string;
  faith: string;
  development: number;
  buildings: string[];
  construction?: { building: string; done: number; by: string };
  /** Персонаж-оккупант (лидер стороны в войне), если провинция захвачена. */
  occupant?: string;
  occupantWar?: string;
  siege?: { army: string; progress: number };
  modifiers: TimedModifier[];
  flags: Record<string, number>;
  vars: Record<string, any>;
}

export interface War {
  id: string;
  cb: string;
  attacker: string;
  defender: string;
  attackers: string[];
  defenders: string[];
  target?: string;
  /** Графства — цели войны (их оккупация важнее всего). */
  targetCounties: string[];
  start: number;
  battleScore: number;
  ticking: number;
  name?: string;
  /** Дополнительные именованные скоупы войны (например, претендент фракции). */
  scopes?: Record<string, ScopeRef>;
  /** Фракция, начавшая войну. */
  faction?: string;
}

export interface Army {
  id: string;
  owner: string;
  war?: string;
  size: number;
  maxSize: number;
  location: string;
  path: string[];
  progress: number;
  commander?: string;
  /** Отступающая армия не вступает в бой, пока не дойдёт до цели. */
  retreating?: boolean;
  /** Профессиональные отряды в составе армии (входят в size). */
  regiments?: Regiment[];
  /** Задача ИИ (кэш), чтобы не пересчитывать путь каждый день. */
  aiTarget?: string;
  aiReplan?: number;
}

export interface Scheme {
  id: string;
  type: string;
  owner: string;
  target: string;
  progress: number;
  start: number;
  discovered: boolean;
}

export interface ScheduledEvent {
  date: number;
  event: string;
  target: ScopeRef;
  scopes: Record<string, ScopeRef>;
}

export interface PendingEvent {
  uid: string;
  event: string;
  target: ScopeRef;
  scopes: Record<string, ScopeRef>;
}

/** Запрос к игроку: ИИ предлагает взаимодействие (брак, вассалитет...). */
export interface PendingRequest {
  uid: string;
  interaction: string;
  actor: string;
  recipient: string;
  secondary?: string;
  target?: ScopeRef;
}

export interface Message {
  date: number;
  text: string;
  kind: 'info' | 'good' | 'bad' | 'war' | 'death' | 'birth' | 'event';
  ref?: ScopeRef;
}

export interface Alliance {
  a: string;
  b: string;
  since: number;
}

export interface Truce {
  a: string;
  b: string;
  until: number;
}

export interface GameState {
  version: number;
  bookmark: string;
  date: number;
  startDate: number;
  rng: RngState;
  nextId: number;
  player?: string;
  /** Династия игрока — на случай, если наследник сменит династию. */
  playerDynasty?: string;
  characters: Record<string, Character>;
  dynasties: Record<string, Dynasty>;
  titles: Record<string, TitleState>;
  provinces: Record<string, ProvinceState>;
  wars: Record<string, War>;
  armies: Record<string, Army>;
  schemes: Record<string, Scheme>;
  alliances: Alliance[];
  truces: Truce[];
  scheduled: ScheduledEvent[];
  pendingEvents: PendingEvent[];
  pendingRequests: PendingRequest[];
  factions: Record<string, Faction>;
  globalFlags: Record<string, number>;
  globalVars: Record<string, any>;
  messages: Message[];
  /** Произвольные сохраняемые данные модов: modData[modId]. */
  modData: Record<string, any>;
  mods: { id: string; version?: string }[];
  gameOver?: { reason: string; date: number };
}
