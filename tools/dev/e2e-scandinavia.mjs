// Проверка Скандинавии в Chromium: node tools/dev/e2e-scandinavia.mjs
import { chromium } from 'playwright';
import { existsSync, mkdirSync } from 'node:fs';

mkdirSync('screenshots', { recursive: true });
const exe = ['/opt/pw-browsers/chromium-1194/chrome-linux/chrome', '/opt/pw-browsers/chromium/chrome-linux/chrome'].find(existsSync);
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
const errors = [];
page.on('console', (m) => { if (m.type() === 'error' && !m.text().includes('ERR_CERT')) errors.push(m.text()); });
page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
const shot = async (n) => { await page.screenshot({ path: `screenshots/s-${n}.png` }); console.log('shot', n); };
const closeEvents = async (max = 10) => {
  for (let i = 0; i < max; i++) {
    const opt = await page.$('.event-modal .event-option:not([disabled])');
    if (!opt) return;
    await opt.click();
    await page.waitForTimeout(150);
  }
};
const t0 = Date.now();
await page.goto('http://localhost:5173/', { waitUntil: 'networkidle' });
await page.waitForSelector('.main-menu');
console.log('menu in', Date.now() - t0, 'ms');
await page.click('text=Новая игра');
await shot('00-bookmark');
const t1 = Date.now();
await page.click('.bm-char:has-text("Харальд")');
await page.waitForSelector('.game-screen', { timeout: 60000 });
console.log('game in', Date.now() - t1, 'ms');
await page.waitForTimeout(800);
await shot('01-harald-start');
await closeEvents();
await page.evaluate(() => { window.CAD.app.map.focus('c_aarhus', 0.9); window.CAD.app.closePanel(); });
await page.waitForTimeout(400);
await shot('02-scandinavia-map');
await page.evaluate(() => { window.CAD.app.map.focus('c_york', 0.45); });
await page.waitForTimeout(400);
await shot('03-whole-map');
await page.click('.tab-btn[data-tab=decisions]');
await page.waitForTimeout(300);
await shot('04-decisions');
// культуры
await page.click('.mode-btn >> nth=4');
await page.waitForTimeout(500);
await shot('05-culture-map');
await page.click('.mode-btn >> nth=5');
await page.waitForTimeout(500);
await shot('06-faith-map');
await page.click('.mode-btn >> nth=0');
// время: месяц
await page.keyboard.press('5');
await page.keyboard.press('Space');
for (let i = 0; i < 12; i++) { await page.waitForTimeout(500); await closeEvents(); const rq = await page.$('.event-modal .event-option'); if (rq) await rq.click(); }
await page.evaluate(() => { window.CAD.app.paused = true; });
await page.waitForTimeout(300);
await closeEvents();
await shot('07-after-time');
console.log('date', await page.evaluate(() => window.CAD.app.game.date));
console.log('errors:', errors.length ? errors.join('\n') : 'none');
await browser.close();
