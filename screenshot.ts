import { chromium } from '@playwright/test';
import {
  GROUPS,
} from './src/data';
import fs from 'node:fs';
import config from './vite.config.ts';

const host = 'http://localhost:5173';
const dst = 'public/';

function resolve(src: string): string {
  if (config.base) {
    return config.base + src;
  }
  else {
    return src;
  }
}

let i = 1;
for (const group of GROUPS) {
  for (const sample of group.items) {
    const url = host + resolve(`wasm/${sample.name}.html`)
    ++i;

    const browser = await chromium.launch(); // or 'chromium', 'firefox'
    const context = await browser.newContext();
    const page = await context.newPage();
    page.setViewportSize({ "width": 300, "height": 157 });

    try {
      await page.goto(url);
      await page.waitForLoadState('networkidle')
      await page.screenshot({ path: `${dst}/wasm/${sample.name}.jpg` });
      await browser.close();
    } catch (ex) {
      console.error(ex);
    }

    // inject html to ogp
    const path = `${dst}/wasm/${sample.name}.html`
    if (fs.existsSync(path)) {
      let src = fs.readFileSync(path, 'utf8');
      fs.writeFileSync(path, src.replace('<meta charset=utf-8>', `<meta charset=utf-8>
<meta property="og:title" content="${sample.name}">
<meta property="og:type" content="website">
<meta property="og:url" content="https://ousttrue.github.io/rowmath/wasm/${sample.name}.html">
<meta property="og:image" content="https://ousttrue.github.io/rowmath/wasm/${sample.name}.jpg">
<meta property="og:site_name" content="rowmath wasm examples">
<meta property="og:description" content="${sample.name}">
`));
    }
  }
}

process.exit(0)
