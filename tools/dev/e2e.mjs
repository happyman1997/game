// Сквозной сценарий в Chromium: node tools/dev/e2e.mjs
import { chromium } from 'playwright';
import { existsSync } from 'node:fs';

const exe = ['/opt/pw-browsers/chromium-1194/chrome-linux/chrome', '/opt/pw-browsers/chromium/chrome-linux/chrome'].find(existsSync);
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
const errors = [];
page.on('console', (m) => { if (m.type() === 'error') errors.push(`${m.type()}: ${m.text()}`); });
page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}\n${e.stack}`));
const shot = (n) => page.screenshot({ path: `screenshots/e2e-${n}.png` });
const closeEvents = async (max = 10) => {
  for (let i = 0; i < max; i++) {
    const opt = await page.$('.event-modal .event-option:not([disabled])');
    if (!opt) return;
    await opt.click();
    await page.waitForTimeout(150);
  }
};
await page.goto('http://localhost:5173/', { waitUntil: 'networkidle' });
await page.waitForSelector('.main-menu');
await page.click('text=Новая игра');
await page.click('.bm-char >> nth=0');
await page.waitForSelector('.game-screen');
await page.waitForTimeout(800);
await closeEvents();
// решения
await page.click('.tab-btn >> nth=5');
await page.waitForTimeout(200);
await shot('01-decisions'); console.log('step', '01-decisions');
const take = await page.$('.decision.major .btn-gold:not([disabled])');
if (take) await take.click();
await page.waitForTimeout(200);
// Гарольд
await page.evaluate(() => window.CAD.app.openCharacter('harold'));
await page.waitForTimeout(300);
await shot('02-harold'); console.log('step', '02-harold');
await page.click('text=Объявить войну');
await page.waitForTimeout(300);
await shot('03-declare'); console.log('step', '03-declare');
await page.click('.cb-card .btn-red >> nth=0');
await page.waitForTimeout(300);
await closeEvents();
// армия
await page.click('.tab-btn >> nth=2');
await page.waitForTimeout(200);
await page.click('text=Собрать армию');
await page.waitForTimeout(300);
const pos = await page.evaluate(() => window.CAD.app.map.screenOf('c_sussex'));
await page.mouse.click(pos[0], pos[1], { button: 'right' });
await page.waitForTimeout(300);
await shot('04-army-moving'); console.log('step', '04-army-moving');
// время
await page.keyboard.press('5');
await page.keyboard.press('Space');
for (let i = 0; i < 16; i++) {
  await page.waitForTimeout(500);
  await closeEvents();
  const rq = await page.$('.event-modal .event-option');
  if (rq) await rq.click();
}
await page.evaluate(() => { window.CAD.app.paused = true; });
await page.waitForTimeout(300);
await closeEvents();
const rq2 = await page.$('.event-modal .event-option');
if (rq2) await rq2.click();
await shot('05-after-time'); console.log('step', '05-after-time');
await page.click('.tab-btn >> nth=3');
await page.waitForTimeout(300);
await shot('06-wars'); console.log('step', '06-wars');
// дипломатическая карта
await page.click('.mode-btn >> nth=1');
await page.waitForTimeout(400);
await shot('07-diplomacy-map'); console.log('step', '07-diplomacy-map');
await page.click('.mode-btn >> nth=0');
// брак
const target = await page.evaluate(() => {
  const g = window.CAD.app.game;
  const c = g.living().find((x) => x.female && !x.spouses.length && x.liege && x.liege !== g.state.player && (g.date - x.birth) / 365 > 16 && (g.date - x.birth) / 365 < 30);
  window.CAD.app.openCharacter(c.id);
  return c.id;
});
await page.waitForTimeout(300);
await shot('08-char-interactions'); console.log('step', '08-char-interactions');
const marry = await page.$('button:not([disabled]):has-text("Устроить брак")');
if (marry) {
  await marry.click();
  await page.waitForTimeout(300);
  await shot('09-marriage-dialog');
  await page.keyboard.press('Escape');
}
// сохранение и загрузка
await page.click('.menu-btn');
await page.click('text=Сохранить игру');
await page.click('.save-dialog .btn-gold');
await page.waitForTimeout(300);
await page.click('.menu-btn');
await page.click('text=Загрузить игру');
await page.waitForTimeout(200);
await shot('10-load-dialog'); console.log('step', '10-load-dialog');
await page.click('.save-row .btn-gold >> nth=0');
await page.waitForTimeout(1500);
await closeEvents();
await shot('11-loaded'); console.log('step', '11-loaded');
// в главное меню и менеджер модов
await page.click('.menu-btn');
await page.click('text=Главное меню');
await page.waitForSelector('.main-menu');
await page.click('text=Моды');
await page.waitForTimeout(300);
await shot('12-mods'); console.log('step', '12-mods');
console.log('marriage target', target);
console.log(errors.slice(0, 30).join('\n') || 'no console errors');
await browser.close();
