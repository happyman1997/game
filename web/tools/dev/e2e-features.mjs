// Сквозная проверка механик в Chromium: node tools/dev/e2e-features.mjs
import { chromium } from 'playwright';
import { existsSync, mkdirSync } from 'node:fs';

mkdirSync('screenshots', { recursive: true });
const exe = ['/opt/pw-browsers/chromium-1194/chrome-linux/chrome', '/opt/pw-browsers/chromium/chrome-linux/chrome'].find(existsSync);
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
const errors = [];
page.on('console', (m) => { if (m.type() === 'error' && !m.text().includes('fonts')) errors.push(`${m.type()}: ${m.text()}`); });
page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}\n${e.stack}`));
const shot = async (n) => { await page.screenshot({ path: `screenshots/f-${n}.png` }); console.log('shot', n); };
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
// играем за Гарольда (у него вассалы, совет, хускарлы)
await page.click('.bm-char:has-text("Гарольд")');
await page.waitForSelector('.game-screen');
await page.waitForTimeout(800);
await closeEvents();
// прокрутим месяц, чтобы ИИ заполнил советы
await page.evaluate(() => { const g = window.CAD.app.game; for (let i = 0; i < 35; i++) g.tick(); window.CAD.app.markDirty(true); });
await page.waitForTimeout(300);
await closeEvents();

await page.click('.tab-btn[data-tab=lifestyle]');
await page.waitForTimeout(300);
await shot('01-lifestyle');
// дать опыт и открыть перк кликом
await page.evaluate(() => { const g = window.CAD.app.game; const p = g.player; const f = g.content.get('focuses', p.lifestyle.focus); p.lifestyle.xp[f.lifestyle] = 5000; window.CAD.app.markDirty(true); });
await page.waitForTimeout(300);
const perk = await page.$('.ls-perk.available');
if (perk) { await perk.click(); await page.waitForTimeout(200); }
await page.hover('.ls-perk.owned >> nth=0');
await page.waitForTimeout(300);
await shot('02-perk-unlocked');
// сменить вкладку образа жизни и фокус
await page.click('.ls-tab >> nth=3');
await page.waitForTimeout(200);
await shot('03-intrigue-lifestyle');

await page.click('.tab-btn[data-tab=realm]');
await page.waitForTimeout(300);
await shot('04-realm-council');
await page.hover('.council-task.active >> nth=0');
await page.waitForTimeout(300);
await shot('05-council-task-tip');
await page.click('.council-btns .btn >> nth=0');
await page.waitForTimeout(300);
await shot('06-councillor-picker');
await page.click('.cand >> nth=0');
await page.waitForTimeout(200);

await page.click('.tab-btn[data-tab=military]');
await page.waitForTimeout(300);
await shot('07-military-regiments');
await page.evaluate(() => { window.CAD.app.game.player.gold = 2000; window.CAD.app.markDirty(true); });
await page.waitForTimeout(200);
await page.click('.reg-buy:not([disabled]) >> nth=0');
await page.waitForTimeout(200);
await page.hover('.regiment-row >> nth=0');
await page.waitForTimeout(300);
await shot('08-regiment-tip');
await page.click('text=Собрать армию');
await page.waitForTimeout(300);
await shot('09-army-with-regiments');

// вассал: заточить
const vassal = await page.evaluate(() => { const g = window.CAD.app.game; const v = g.vassalsOf(g.state.player)[0]; window.CAD.app.openCharacter(v.id); return v.id; });
await page.waitForTimeout(300);
await shot('10-vassal');
const imp = await page.$('button:has-text("Заключить в темницу")');
if (imp) {
  await imp.click();
  await page.waitForTimeout(300);
  await shot('11-imprison-dialog');
  await page.click('.modal .btn-gold');
  await page.waitForTimeout(300);
}
await page.evaluate((id) => window.CAD.app.openCharacter(id), vassal);
await page.waitForTimeout(300);
await shot('12-prisoner');
await page.click('.tab-btn[data-tab=intrigue]');
await page.waitForTimeout(300);
await shot('13-intrigue-prisoners');

// фракция против игрока
await page.evaluate(() => {
  const g = window.CAD.app.game;
  const vs = g.vassalsOf(g.state.player).filter((v) => !v.prison);
  const W = window.CAD.world;
  void W;
  g.state.factions.f_test = { id: 'f_test', type: 'independence_faction', target: g.state.player, leader: vs[0].id, members: vs.slice(0, 4).map((v) => v.id), discontent: 60, created: g.date };
  window.CAD.app.markDirty(true);
});
await page.click('.tab-btn[data-tab=realm]');
await page.waitForTimeout(300);
await page.evaluate(() => document.querySelector('.faction-card')?.scrollIntoView());
await page.waitForTimeout(200);
await shot('14-factions');
// ультиматум игроку
await page.evaluate(() => { const g = window.CAD.app.game; g.state.factions.f_test.discontent = 100; g.state.factions.f_test.leader = g.state.factions.f_test.members[0]; });
await page.evaluate(() => { const g = window.CAD.app.game; for (let i = 0; i < 31; i++) g.tick(); window.CAD.app.markDirty(true); });
await page.waitForTimeout(400);
for (let i = 0; i < 8; i++) {
  const title = await page.$eval('.event-modal', (el) => el.textContent).catch(() => null);
  if (!title) break;
  if (title.includes('Ультиматум')) {
    await shot('15-ultimatum');
    await page.click('.event-modal .event-option >> nth=1');
  } else await page.click('.event-modal .event-option >> nth=0');
  await page.waitForTimeout(250);
}
await page.click('.tab-btn[data-tab=wars]');
await page.waitForTimeout(300);
await shot('16-revolt-war');
// английский язык: вкладка образа жизни
await page.click('.menu-btn');
await page.click('text=English');
await page.waitForTimeout(1500);
await closeEvents();
await page.click('.tab-btn[data-tab=lifestyle]');
await page.waitForTimeout(300);
await shot('17-lifestyle-en');
console.log('errors:', errors.length ? errors.join('\n') : 'none');
await browser.close();
