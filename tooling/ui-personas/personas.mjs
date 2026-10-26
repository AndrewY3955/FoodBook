import { chromium } from 'playwright-core';
import { randomUUID } from 'node:crypto';

const N = Number(process.argv[2] ?? 8);
const URL = process.env.APP_URL ?? 'http://127.0.0.1:8081/';
const PHOTOS = process.env.PHOTO_DIR ?? `${process.env.TEMP}\\fb-photos`;
const photoFor = (i, k) => `${PHOTOS}\\photo-${(i + k) % 8}.jpg`;
const DEL = (process.env.DELETE_EVERY ?? '3');
const CUISINES = ['Italian', 'Thai', 'Mexican', 'Japanese', 'Indian', 'French'];
const THEMES = ['Cream', 'Herb', 'Tomato', 'Ocean', 'Night'];
const ACCENTS = ['#C0392B', '#27AE60', '#2980B9', '#8E44AD'];
const pick = (a) => a[Math.floor(Math.random() * a.length)];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];

async function persona(browser, i) {
  const name = `UI Cook ${i}`;
  const email = `ui-${randomUUID()}@example.test`;
  const password = `Aa1!${randomUUID()}z`;
  const title = `UI Persona ${i} ${randomUUID().slice(0, 6)}`;
  const log = { i, email, title, steps: [], error: null };
  const ctx = await browser.newContext({ viewport: { width: Number(process.env.WIDTH ?? 930), height: 850 } });
  const p = await ctx.newPage();
  const step = async (label, fn) => {
    try {
      await fn();
      log.steps.push(label);
    } catch (e) {
      log.error = `${label}: ${String(e.message).split('\n')[0]}`;
      await p.screenshot({ path: `${process.env.TEMP}\\fb-ui\\fail-${i}.png` }).catch(() => {});
      throw e;
    }
  };
  const pickFile = async (trigger, file) => {
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const [chooser] = await Promise.all([
          p.waitForEvent('filechooser', { timeout: 30000 }),
          click(trigger),
        ]);
        await chooser.setFiles(file);
        return;
      } catch (e) {
        if (attempt === 2) throw e;
        await sleep(1200);
      }
    }
  };
  const click = async (locator) => {
    const target = locator.first();
    await target.scrollIntoViewIfNeeded().catch(() => {});
    await target.click({ force: true, timeout: 20000 });
  };
  const type = async (locator, text) => {
    await click(locator);
    await p.keyboard.press('Control+A');
    await p.keyboard.type(text, { delay: 15 });
  };
  try {
    await sleep(i * 700);
    await step('open', async () => {
      await p.goto(URL);
      await p.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 30000 });
      await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
      await p.getByRole('button', { name: 'Create an account' }).waitFor({ timeout: 20000 });
    });
    await step('signup', async () => {
      await click(p.getByRole('button', { name: 'Create an account' }));
      await type(p.getByRole('textbox', { name: 'What should we call you?' }), name);
      await type(p.getByRole('textbox', { name: 'Email' }), email);
      await type(p.getByRole('textbox', { name: 'Password' }), password);
      await click(p.getByRole('button', { name: 'Create account' }));
      await p.getByRole('button', { name: 'Add recipe' }).waitFor({ timeout: 30000 });
    });
    await step('open-form', async () => {
      await sleep(1500);
      await click(p.getByRole('button', { name: 'Add recipe' }));
      await click(p.getByRole('menuitem', { name: 'Write it out' }));
      await p.getByRole('textbox', { name: 'Title' }).waitFor({ timeout: 15000 });
    });
    await step('fill-basics', async () => {
      await type(p.getByRole('textbox', { name: 'Title' }), title);
      await click(p.getByRole('button', { name: 'Add a step' }));
      await sleep(500);
      await click(p.getByRole('button', { name: 'Add a step' }));
      await sleep(500);
      await type(p.getByRole('textbox', { name: 'What happens now?' }).first(), 'Prep everything.');
      await type(p.getByRole('textbox', { name: 'What happens now?' }).first(), 'Cook it through.');
    });
    await step('ingredient', async () => {
      await click(p.getByRole('textbox', { name: 'Add an ingredient' }));
      await p.keyboard.type('Garlic', { delay: 20 });
      await click(p.getByRole('button', { name: /^Garlic/ }).first());
      await type(p.getByRole('textbox', { name: 'Qty' }), '3');
    });
    await step('cuisine', async () => {
      await click(p.getByRole('button', { name: /^Cuisine/ }));
      await click(p.getByRole('menuitem', { name: pick(CUISINES) }));
    });
    await step('diet-nutrition', async () => {
      await click(p.getByRole('button', { name: /Diet & nutrition facts/ }));
      await click(p.getByRole('checkbox', { name: 'High protein' }));
      await click(p.getByRole('checkbox', { name: 'Gluten free' }));
      await type(p.getByRole('textbox', { name: 'Calories' }), '450');
      await type(p.getByRole('textbox', { name: 'Protein (g)' }), '32');
    });
    await step('look-and-feel', async () => {
      await click(p.getByRole('checkbox', { name: pick(THEMES) }));
      await click(p.getByRole('button', { name: `Accent colour ${pick(ACCENTS)}` }));
    });
    await step('images', async () => {
      final_bg: {
        const add = p.getByRole('button', { name: 'Add a background' });
        const change = p.getByRole('button', { name: 'Change background' });
        const trigger = await add.count() > 0 ? add : change;
        await pickFile(trigger, photoFor(i, 0));
      }
      await sleep(1200);
      await pickFile(p.getByRole('button', { name: 'Add a photo' }), photoFor(i, 1));
      await sleep(1500);
      for (const k of [2, 3]) {
        await pickFile(p.getByRole('button', { name: 'Add a photo' }), photoFor(i, k));
        await sleep(1500);
      }
      await sleep(1200);
    });
    await step('publish+save', async () => {
      await click(p.getByRole('switch', { name: /Share publicly/ }));
      await click(p.getByRole('button', { name: 'Save' }));
      const t0 = Date.now(); await p.getByRole('button', { name: new RegExp(title) }).waitFor({ timeout: 300000 }); log.saveMs = Date.now() - t0;
    });
    if (process.env.SHOT) await step('shot', async () => {
      await click(p.getByRole('button', { name: new RegExp(title) }));
      await p.getByRole('button', { name: 'Start cooking' }).waitFor({ timeout: 20000 });
      await sleep(2500);
      await p.screenshot({ path: process.env.SHOT });
    });
    await step('discover', async () => {
      await click(p.getByRole('button', { name: 'Discover' }));
      await p.getByRole('button', { name: /^Shared / }).first().waitFor({ timeout: 20000 });
      const cuisine = pick(CUISINES);
      await click(p.getByRole('button', { name: /Browse by cuisine/ }));
      await click(p.getByText(cuisine, { exact: true }));
      await sleep(1500);
      await click(p.getByRole('button', { name: /Diet & nutrition/ }));
      await click(p.getByRole('checkbox', { name: 'High protein' }));
      await sleep(1500);
    });
    await step('open-someone-elses', async () => {
      const value = pick(['American', 'Italian', 'Thai', 'Mexican']);
      await click(p.getByText(value, { exact: true }));
      await sleep(1500);
      const cards = p.getByRole('button', { name: /^Shared / });
      const n = await cards.count();
      if (n === 0) { log.note = 'category empty (valid)'; return; }
      await click(cards.nth(Math.floor(Math.random() * n)));
      await p.getByRole('button', { name: 'Start cooking' }).waitFor({ timeout: 20000 });
    });
    await step('fork', async () => {
      if (log.note) return;
      await click(p.getByRole('button', { name: 'Show menu' }));
      const items = await p.getByRole('menuitem').allInnerTexts();
      log.menu = items;
      const fork = p.getByRole('menuitem', { name: /fork|copy|save/i }).first();
      await click(fork);
      await sleep(2500);
    });
    if (i % Number(DEL) === 0) await step('delete-account', async () => {
      await p.getByRole('button', { name: 'Back' }).first().click({ force: true, timeout: 3000 }).catch(() => {});
      await sleep(1500);
      await click(p.getByRole('button', { name: 'Delete account' }));
      await click(p.getByRole('button', { name: 'Delete everything' }));
      await p.getByRole('button', { name: 'Create an account' }).waitFor({ timeout: 60000 });
      log.deleted = true;
    });
    log.ok = true;
  } catch {
    log.ok = false;
  } finally {
    await ctx.close();
  }
  results.push(log);
}

const browser = await chromium.launch({ executablePath: 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe', headless: true });
await Promise.all(Array.from({ length: N }, (_, i) => persona(browser, i)));
await browser.close();
for (const r of results.sort((a, b) => a.i - b.i)) {
  console.log(r.ok ? 'OK  ' : 'FAIL', r.i, r.title, r.ok ? (r.note ?? '') : r.error, r.menu ? JSON.stringify(r.menu) : '', 'saveMs=' + r.saveMs);
}
console.log(JSON.stringify(results.map((r) => r.email)));
process.exit(results.every((r) => r.ok) ? 0 : 1);
