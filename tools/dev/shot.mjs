// Скриншоты игры в Chromium: node tools/dev/shot.mjs <сценарий>
import { chromium } from 'playwright';
import { existsSync } from 'node:fs';

const exe = ['/opt/pw-browsers/chromium-1194/chrome-linux/chrome', '/opt/pw-browsers/chromium/chrome-linux/chrome'].find(existsSync);
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
const errors = [];
page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') errors.push(`${m.type()}: ${m.text()}`); });
page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}\n${e.stack}`));
await page.goto('http://localhost:5173/', { waitUntil: 'networkidle' });
await page.waitForSelector('.main-menu', { timeout: 60000 });
await page.screenshot({ path: 'screenshots/01-menu.png' });
const scenario = process.argv[2] ?? 'basic';
if (scenario !== 'menu') {
  await page.click('text=Новая игра');
  await page.waitForSelector('.bookmark-card');
  await page.screenshot({ path: 'screenshots/02-bookmarks.png' });
  await page.click('.bm-char >> nth=0');
  await page.waitForSelector('.game-screen', { timeout: 60000 });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: 'screenshots/03-game.png' });
  // закрыть стартовое событие
  const opt = await page.$('.event-option');
  if (opt) { await opt.click(); await page.waitForTimeout(300); }
  await page.screenshot({ path: 'screenshots/04-after-event.png' });
  for (const tab of ['realm', 'military', 'wars', 'decisions']) {
    await page.click(`.tab-btn[data-tab=${tab}]`);
    await page.waitForTimeout(300);
    await page.screenshot({ path: `screenshots/05-tab-${tab}.png` });
  }
  // клик по провинции
  await page.mouse.click(800, 450);
  await page.waitForTimeout(400);
  await page.screenshot({ path: 'screenshots/06-province.png' });
  // запустить время
  await page.keyboard.press('Space');
  await page.keyboard.press('5');
  await page.waitForTimeout(6000);
  await page.screenshot({ path: 'screenshots/07-running.png' });
}
console.log(errors.slice(0, 30).join('\n') || 'no console errors');
await browser.close();
