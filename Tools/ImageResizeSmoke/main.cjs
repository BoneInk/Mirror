// Run with Node and Playwright. Uses the actual isolated-world preview script.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const renderer = fs.readFileSync('Sources/Mirror/MarkdownRenderer.swift', 'utf8');
const script = renderer.split('static let previewScript = #"""')[1].split('"""#')[0];
(async () => {
  const browser = await chromium.launch({headless:true, ...(process.env.CHROMIUM_PATH ? {executablePath:process.env.CHROMIUM_PATH} : {})});
  try {
    const page = await browser.newPage();
    const messages = [];
    await page.exposeFunction('recordResize', body => messages.push(body));
    const image = `<img data-mirror-image-key="cGhvdG8uc3Zn" data-mirror-image-occurrence="0" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='200' height='100'%3E%3Crect width='200' height='100' fill='blue'/%3E%3C/svg%3E">`;
    await page.setContent(`<style>:root{--accent:blue;--bg:white}article{width:600px}img{max-width:100%;height:auto}</style><article><p>${image}</p></article>`);
    await page.evaluate(() => {window.webkit={messageHandlers:{mirrorImageResize:{postMessage:window.recordResize}}}});
    await page.evaluate(script);
    await page.locator('img').evaluate(img => img.decode());
    const size = () => page.locator('img').evaluate(img => ({width:img.getBoundingClientRect().width,height:img.getBoundingClientRect().height}));
    const drag = async dx => {
      await page.locator('img').hover({force:true});
      const box=await page.locator('button').boundingBox();
      await page.mouse.move(box.x+10,box.y+10);await page.mouse.down();await page.mouse.move(box.x+10+dx,box.y+10, {steps:5});
    };
    await drag(120);await page.mouse.up();
    await page.waitForFunction(() => document.querySelector('img').getBoundingClientRect().width===320);
    assert.deepEqual(await size(),{width:320,height:160});
    assert.equal(messages.at(-1).width,320);assert.equal(messages.at(-1).occurrence,0);
    await drag(100);await page.keyboard.press('Escape');await page.mouse.up();
    assert.deepEqual(await size(),{width:320,height:160});assert.equal(messages.length,1);
    await drag(-1000);await page.mouse.up();assert.equal((await size()).width,24);
    await page.locator('button').focus();await page.keyboard.press('Shift+ArrowRight');assert.equal((await size()).width,34);
    await drag(1000);await page.mouse.up();assert.equal((await size()).width,600);
    await page.evaluate(() => {document.querySelector('article').innerHTML=document.querySelector('article').innerHTML.replace(/<span class="mirror-image-frame">([\s\S]*?)<button[\s\S]*?<\/button><\/span>/,'$1')});
    await page.waitForFunction(() => document.querySelectorAll('.mirror-image-resize').length===1);
    assert.equal(await page.locator('.mirror-image-frame').count(),1);
    await page.locator('button').focus();await page.keyboard.press('ArrowLeft');assert.equal((await size()).width,599);
    await page.emulateMedia({media:'print'});assert.equal(await page.locator('button').isVisible(),false);
    console.log('image-resize-smoke-ok: drag, aspect ratio, limits, Escape, keyboard, DOM replacement, print');
  } finally {await browser.close()}
})().catch(error => {console.error(error);process.exit(1)});
