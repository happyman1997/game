/**
 * Игровой календарь: 365 дней в году, без високосных лет (как в CK3).
 * Дата хранится как целое число дней от 1 января 0 года — это удобно
 * для сериализации и арифметики.
 */
export const MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
export const DAYS_PER_YEAR = 365;
export const DAYS_PER_MONTH = 30;

const MONTH_START: number[] = [];
{
  let acc = 0;
  for (const d of MONTH_DAYS) {
    MONTH_START.push(acc);
    acc += d;
  }
}

export interface DateParts {
  y: number;
  m: number;
  d: number;
}

export function makeDate(y: number, m = 1, d = 1): number {
  return y * DAYS_PER_YEAR + MONTH_START[m - 1] + (d - 1);
}

export function dateParts(n: number): DateParts {
  const y = Math.floor(n / DAYS_PER_YEAR);
  const r = n - y * DAYS_PER_YEAR;
  let m = 0;
  while (m < 11 && r >= MONTH_START[m + 1]) m++;
  return { y, m: m + 1, d: r - MONTH_START[m] + 1 };
}

/** Принимает "1066.9.15", "1066.9", "1066" или число лет. */
export function parseDate(s: string | number): number {
  if (typeof s === 'number') return makeDate(Math.floor(s));
  const parts = String(s).trim().split(/[.\-/]/).map((p) => parseInt(p, 10));
  if (parts.some((p) => Number.isNaN(p))) throw new Error(`Некорректная дата: "${s}"`);
  return makeDate(parts[0], parts[1] ?? 1, parts[2] ?? 1);
}

export function dateToString(n: number): string {
  const { y, m, d } = dateParts(n);
  return `${y}.${m}.${d}`;
}

export function ageAt(birth: number, date: number): number {
  return Math.floor((date - birth) / DAYS_PER_YEAR);
}

export interface DurationSpec {
  days?: number;
  months?: number;
  years?: number;
}

/** Переводит {days, months, years} или число дней в количество дней. */
export function durationDays(spec: DurationSpec | number | undefined | null): number {
  if (spec == null) return 0;
  if (typeof spec === 'number') return Math.round(spec);
  return Math.round((spec.days ?? 0) + (spec.months ?? 0) * DAYS_PER_MONTH + (spec.years ?? 0) * DAYS_PER_YEAR);
}
