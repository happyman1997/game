import { chromium } from 'playwright';
import { existsSync } from 'node:fs';
const exe = ['/opt/pw-browsers/chromium-1194/chrome-linux/chrome', '/opt/pw-browsers/chromium/chrome-linux/chrome'].find(existsSync);
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
const errors = [];
page.on('console', (m) => { if (m.type() === 'error' && !m.text().includes('ERR_CERT')) errors.push(m.text()); });
page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}\n${e.stack}`));
const shot = (n) => page.screenshot({ path: `screenshots/mods-${n}.png` });
const closeEvents = async () => { for (let i = 0; i < 10; i++) { const o = await page.$('.event-modal .event-option'); if (!o) return; await o.click(); await page.waitForTimeout(120); } };
await page.goto('http://localhost:5173/', { waitUntil: 'networkidle' });
await page.waitForSelector('.main-menu');
await page.click('text=Новая игра');
await page.click('text=Выбрать любого правителя на карте…');
await page.waitForSelector('.game-screen');
await page.waitForTimeout(800);
await shot('01-pick');
const pos = await page.evaluate(() => window.CAD.app.map.screenOf('c_dublin'));
await page.mouse.click(pos[0], pos[1]);
await page.waitForTimeout(300);
await page.click('.prov-panel .char-link >> nth=0');
await page.waitForTimeout(300);
await shot('02-pick-char');
await page.click('text=Играть за этого персонажа');
await page.waitForTimeout(500);
await closeEvents();
// эпидемия рядом с игроком
await page.evaluate(() => {
  const g = window.CAD.app.game;
  const ctx = window.CAD.engine.script; void ctx;
  const { makeContext } = window.CAD.world.characters; void makeContext;
  window.CAD.app.paused = true;
});
await page.evaluate(() => {
  const app = window.CAD.app; const g = app.game;
  // запускаем вспышку эффектом из мода
  const run = (prov) => {
    const ctx = { game: g, root: { type: 'province', id: prov }, scopes: {}, values: {}, depth: 0 };
    g.engine.script.effects.get('start_disease').apply(ctx, ctx.root, 'bubonic_plague');
  };
  run('c_dublin'); run('c_mide'); run('c_york');
  app.markDirty(true);
});
await page.waitForTimeout(300);
await shot('02b-plague-event');
await closeEvents();
const modes = await page.$$('.mode-btn');
await modes[modes.length - 1].click();
await page.waitForTimeout(600);
await shot('03-plague-mode');
const tabs = await page.$$('.tab-btn');
await tabs[tabs.length - 1].click();
await page.waitForTimeout(300);
await shot('04-plague-panel');
await page.click('.tab-btn[data-tab=decisions]');
await page.waitForTimeout(300);
await shot('05-decisions');
// английский
await page.click('.menu-btn');
await page.click('text=English');
await page.waitForTimeout(300);
await page.evaluate(() => window.CAD.app.openCharacter(window.CAD.app.game.state.player));
await page.waitForTimeout(300);
await shot('06-english');
console.log(errors.join('\n') || 'no console errors');
await browser.close();
