// Run with Node and Playwright. Exercises the rendered document and preview-only script.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const renderer = fs.readFileSync('Sources/Mirror/MarkdownRenderer.swift', 'utf8');
const script = renderer.split('static let previewScript = #"""')[1].split('"""#')[0];

(async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'MirrorDiagramSmoke-'));
  const fixture = path.join(directory, 'preview.html');
  execFileSync('bash', ['scripts/test-renderer.sh', '--write-html', fixture], {
    stdio:'inherit', env:{...process.env,MIRROR_RENDERER_OUTPUT_DIR:path.join(directory,'build')},
  });
  const html = fs.readFileSync(fixture, 'utf8');
  const browser = await chromium.launch({headless:true, ...(process.env.CHROMIUM_PATH ? {executablePath:process.env.CHROMIUM_PATH} : {})});
  try {
    const page = await browser.newPage({viewport:{width:1000,height:800},locale:'en-US'});
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('**/*', route => route.abort());
    // Bundled Mermaid also contains a literal </head> inside its sanitizer source.
    const headEnd = html.lastIndexOf('</head>');
    await page.setContent(html.slice(0,headEnd) + `<script>${script}</script>` + html.slice(headEnd));
    await page.waitForFunction(() => window.mirrorEnhancementsDone && document.querySelector('.diagram-interactive')).catch(async error => {
      console.error(errors, await page.evaluate(() => ({done:window.mirrorEnhancementsDone,
        installer:typeof window.mirrorInstallDiagram, runtime:typeof mermaid,
        diagrams:[...document.querySelectorAll('.diagram-canvas')].map(node=>node.outerHTML.slice(0,500))})));
      throw error;
    });
    const canvas = page.locator('.diagram-interactive');
    const zoomLabel = page.locator('.diagram-zoom');
    const state = () => canvas.locator('.diagram-content').evaluate(element => {
      const matrix = new DOMMatrix(getComputedStyle(element).transform);
      return {x:matrix.e,y:matrix.f,scale:matrix.a};
    });
    assert.equal(await zoomLabel.textContent(), '100%');
    assert.equal(await page.locator('.diagram-tools').count(), 1);
    assert.equal(await page.locator('.diagram-resize').count(), 0);
    assert.equal(await page.locator('.mirror-image-resize,.mirror-image-frame').count(), 0);
    const images = await page.locator('article img').evaluateAll(nodes => nodes.map(node => node.outerHTML));
    await canvas.scrollIntoViewIfNeeded();
    let initial = await state();
    const viewportHeight = await canvas.evaluate(node => node.clientHeight);
    const frame = page.locator('.diagram-block');
    const frameSize = () => frame.evaluate(node => ({width:node.getBoundingClientRect().width,height:node.querySelector('.diagram-canvas').clientHeight}));
    const originalFrame = await frameSize();
    const edgePoint = async edge => {
      const box = await frame.boundingBox();
      return {x:edge === 'bottom' ? box.x+box.width/2 : box.x+box.width-5,
        y:edge === 'right' ? box.y+box.height/2 : box.y+box.height-5};
    };
    const resizeDrag = async (edge, dx, dy) => {
      const point = await edgePoint(edge);
      await page.mouse.move(point.x,point.y);
      assert.equal(await canvas.evaluate(node=>getComputedStyle(node).cursor),
        edge === 'right' ? 'ew-resize' : edge === 'bottom' ? 'ns-resize' : 'nwse-resize');
      await page.mouse.down();
      await page.mouse.move(point.x+dx,point.y+dy,{steps:5});
    };
    const appearance = () => frame.evaluate(node => {
      const style = getComputedStyle(node);
      return {background:style.background,border:style.border,shadow:style.boxShadow,
        before:getComputedStyle(node,'::before').content,after:getComputedStyle(node,'::after').content};
    });
    const originalAppearance = await appearance();
    await resizeDrag('corner',-120,-40); await page.mouse.up();
    assert.deepEqual(await appearance(),originalAppearance);
    let resizedFrame = await frameSize();
    assert.ok(Math.abs(resizedFrame.width-originalFrame.width+120)<1);
    assert.equal(resizedFrame.height,originalFrame.height-40);
    assert.equal(await zoomLabel.textContent(),'100%');
    const resized = await state();
    await resizeDrag('corner',-40,-20); await page.keyboard.press('Escape'); await page.mouse.up();
    assert.deepEqual(await frameSize(),resizedFrame);
    assert.deepEqual(await state(),resized);
    await resizeDrag('right',60,0); await page.mouse.up();
    assert.ok(Math.abs((await frameSize()).width-resizedFrame.width-60)<1);
    assert.equal((await frameSize()).height,resizedFrame.height);
    resizedFrame = await frameSize();
    // Compare document positions; browser scroll anchoring can change viewport offsets.
    const below = () => frame.evaluate(node=>node.nextElementSibling.getBoundingClientRect().top+window.scrollY);
    const belowBefore = await below();
    await resizeDrag('bottom',0,50); await page.mouse.up();
    assert.deepEqual(await frameSize(),{width:resizedFrame.width,height:resizedFrame.height+50});
    assert.ok(Math.abs((await below())-belowBefore-50)<1);
    await frame.focus(); await page.keyboard.press('ArrowDown');
    assert.equal((await frameSize()).height,resizedFrame.height+51);
    await page.keyboard.press('Shift+ArrowDown');
    assert.equal((await frameSize()).height,resizedFrame.height+61);
    const svgSize = await canvas.locator('svg').evaluate(node=>({width:node.getBoundingClientRect().width,height:node.getBoundingClientRect().height,ratio:node.viewBox.baseVal.width/node.viewBox.baseVal.height}));
    assert.ok(Math.abs(svgSize.width/svgSize.height-svgSize.ratio)<.001);
    await page.getByRole('button',{name:'Reset and fit diagram'}).click();
    assert.deepEqual(await frameSize(),originalFrame);
    assert.deepEqual(await state(),initial);
    // Pointer hover changes only the cursor; it draws no grip, strip, or extra border.
    const bottom = await edgePoint('bottom'); await page.mouse.move(bottom.x,bottom.y);
    assert.deepEqual(await appearance(),originalAppearance);
    await canvas.hover({position:{x:80,y:70}});
    assert.equal(await canvas.evaluate(node=>getComputedStyle(node).cursor),'grab');
    assert.equal(await frame.getAttribute('data-resize-edge'),null);
    const drag = async (dx, dy) => {
      const box = await canvas.boundingBox();
      await page.mouse.move(box.x+box.width/2,box.y+box.height/2);
      await page.mouse.down();
      await page.mouse.move(box.x+box.width/2+dx,box.y+box.height/2+dy,{steps:5});
    };
    await drag(80,35); await page.mouse.up();
    let moved = await state();
    assert.ok(Math.abs(moved.x-initial.x-80)<1 && Math.abs(moved.y-initial.y-35)<1);
    await drag(40,20); await page.keyboard.press('Escape'); await page.mouse.up();
    assert.deepEqual(await state(),moved);
    await page.getByRole('button',{name:'Zoom in diagram',exact:true}).click();
    assert.equal(await zoomLabel.textContent(),'120%');
    assert.equal(await canvas.evaluate(node=>node.clientHeight),viewportHeight);
    await page.getByRole('button',{name:'Reset and fit diagram'}).click();
    assert.deepEqual(await state(),initial);
    await canvas.focus(); await page.keyboard.press('+');
    assert.equal(await zoomLabel.textContent(),'120%');
    await page.keyboard.press('0'); await page.keyboard.press('ArrowRight');
    assert.ok(Math.abs((await state()).x-initial.x+20)<1);
    await page.keyboard.press('0');
    await canvas.hover({position:{x:80,y:70}});
    // A regular wheel scroll must stay available for reading the document.
    assert.equal(await canvas.evaluate(node => {
      const event = new WheelEvent('wheel',{deltaY:25,bubbles:true,cancelable:true});
      node.dispatchEvent(event); return event.defaultPrevented;
    }), false);
    initial = await state();
    await page.keyboard.down('Control'); await page.mouse.wheel(0,-30); await page.keyboard.up('Control');
    await page.waitForFunction(() => document.querySelector('.diagram-zoom').textContent !== '100%');
    let zoomed = await state();
    // Cursor-centered zoom must leave the diagram point under the cursor unchanged.
    assert.ok(Math.abs((80-initial.x)/initial.scale-(80-zoomed.x)/zoomed.scale)<1);
    assert.ok(Math.abs((70-initial.y)/initial.scale-(70-zoomed.y)/zoomed.scale)<1);
    await page.getByRole('button',{name:'Reset and fit diagram'}).click();
    // WebKit's native trackpad gesture path uses an absolute scale from gesture start.
    await canvas.evaluate(node => {
      const rect=node.getBoundingClientRect();
      for(const [type,scale] of [['gesturestart',1],['gesturechange',1.5],['gesturechange',2],['gestureend',2]]) {
        const event=new Event(type,{bubbles:true,cancelable:true});
        Object.assign(event,{scale,clientX:rect.left+80,clientY:rect.top+70}); node.dispatchEvent(event);
      }
    });
    assert.equal(await zoomLabel.textContent(),'200%');
    await page.getByRole('button',{name:'Reset and fit diagram'}).click();
    await canvas.evaluate(node => {
      for(let index=0;index<80;index++) node.dispatchEvent(new KeyboardEvent('keydown',{key:'-',bubbles:true,cancelable:true}));
    });
    assert.equal(await zoomLabel.textContent(),'25%');
    assert.equal(await page.getByRole('button',{name:'Zoom out diagram',exact:true}).isDisabled(),true);
    await canvas.evaluate(node => {
      for(let index=0;index<100;index++) node.dispatchEvent(new KeyboardEvent('keydown',{key:'+',bubbles:true,cancelable:true}));
    });
    assert.equal(await page.getByRole('button',{name:'Zoom in diagram',exact:true}).isDisabled(),true);
    await canvas.dblclick(); assert.equal(await zoomLabel.textContent(),'100%');
    await page.setViewportSize({width:390,height:800});
    await page.waitForFunction(() => {
      const canvas=document.querySelector('.diagram-interactive'), svg=canvas.querySelector('svg');
      return svg.getBoundingClientRect().width <= canvas.clientWidth;
    });
    assert.equal(await zoomLabel.textContent(),'100%');
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
    assert.deepEqual(await page.locator('article img').evaluateAll(nodes=>nodes.map(node=>node.outerHTML)),images);
    if (process.env.DIAGRAM_SCREENSHOT_PATH) {
      await page.evaluate(()=>document.activeElement.blur());
      await page.mouse.move(0,0);
      await page.locator('.diagram-block').screenshot({path:process.env.DIAGRAM_SCREENSHOT_PATH});
    }
    // Print layout must show the complete diagram even after a user zooms and pans.
    await page.getByRole('button',{name:'Zoom in diagram',exact:true}).click();
    await page.emulateMedia({media:'print'});
    assert.equal(await page.locator('.diagram-tools').isVisible(),false);
    assert.equal(await page.locator('.diagram-resize').count(),0);
    assert.equal(await canvas.locator('.diagram-content').evaluate(node=>getComputedStyle(node).transform),'none');
    await page.emulateMedia({media:'screen'});
    // Live content updates install one independent controller per successful diagram.
    await page.evaluate(() => window.mirrorReplaceContent(
      '<div class="diagram-block"><div class="code-header">Mermaid</div><div class="diagram-canvas mermaid">flowchart LR\nA-->B</div></div>'.repeat(2),
      8,'Replacement',0,0,.35,'top',1));
    await page.waitForFunction(() => window.mirrorEnhancementsDone && document.querySelectorAll('.diagram-tools').length===2);
    const labels = page.locator('.diagram-zoom');
    await page.getByRole('button',{name:'Zoom in diagram',exact:true}).first().click();
    assert.deepEqual(await labels.allTextContents(),['120%','100%']);
    await page.evaluate(()=>window.mirrorRenderAll());
    assert.equal(await page.locator('.diagram-tools').count(),2);
    assert.equal(await page.locator('.diagram-resize').count(),0);
    await page.evaluate(()=>window.mirrorReplaceContent(
      '<div class="diagram-block"><div class="code-header">Mermaid</div><div class="diagram-canvas mermaid">flowchart ???</div></div>',
      3,'Invalid diagram',0,0,.35,'top',2));
    await page.waitForFunction(()=>window.mirrorEnhancementsDone && document.querySelector('.mermaid-error'));
    assert.equal(await page.locator('.diagram-tools').count(),0);
    assert.deepEqual(errors,[]);
    // Exported HTML should render complete SVGs without preview controls.
    const exported = await browser.newPage();
    await exported.route('**/*',route=>route.abort());
    await exported.setContent(html);
    await exported.waitForFunction(()=>window.mirrorEnhancementsDone && document.querySelector('.diagram-canvas svg'));
    assert.equal(await exported.locator('.diagram-tools,.diagram-content,.diagram-resize').count(),0);
    console.log('diagram-interaction-smoke-ok: handle-free edge hit testing and cursors, unchanged frame appearance, corner and border resize, layout reflow, auto fit, aspect ratio, resize Escape and keyboard, drag, buttons, cursor zoom, pinch, limits, responsive fit, live replacement, independent diagrams, syntax errors, images, print, export');
  } finally {
    await browser.close(); fs.rmSync(directory,{recursive:true,force:true});
  }
})().catch(error=>{console.error(error);process.exit(1)});
