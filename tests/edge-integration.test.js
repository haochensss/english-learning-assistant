const http = require("http");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { chromium } = require("playwright");

const projectRoot = path.resolve(__dirname, "..");
const extensionPath = path.join(projectRoot, "edge-extension");
const edgePath = "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function triggerTestSelection(page) {
  await page.evaluate(() => {
    const node = document.getElementById("sample").firstChild;
    const range = document.createRange();
    range.selectNodeContents(node);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    document.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
  });
}

async function selectTestText(page) {
  await triggerTestSelection(page);
  await page.locator("#english-learning-assistant-buttons").waitFor({ state: "attached" });
}

async function captureAssistant(page, hostId, computedStyles = []) {
  const session = await page.context().newCDPSession(page);
  try {
    const snapshot = await session.send("DOMSnapshot.captureSnapshot", {
      computedStyles,
      includePaintOrder: true,
      includeDOMRects: true
    });
    const document = snapshot.documents[0];
    const strings = snapshot.strings;
    const nodes = document.nodes;
    const layout = document.layout;
    const attributesAt = (index) => {
      const values = nodes.attributes[index] || [];
      const result = {};
      for (let i = 0; i < values.length; i += 2) result[strings[values[i]]] = strings[values[i + 1]];
      return result;
    };
    const hostIndex = nodes.nodeName.findIndex((_, index) => attributesAt(index).id === hostId);
    if (hostIndex < 0) return null;
    const isDescendant = (index) => {
      let parent = nodes.parentIndex[index];
      while (parent >= 0) {
        if (parent === hostIndex) return true;
        parent = nodes.parentIndex[parent];
      }
      return false;
    };
    const descendantIndexes = nodes.nodeName
      .map((_, index) => index)
      .filter(isDescendant);
    const textAt = (index) => descendantIndexes
      .filter((candidate) => {
        let parent = nodes.parentIndex[candidate];
        while (parent >= 0 && parent !== index && parent !== hostIndex) parent = nodes.parentIndex[parent];
        return parent === index && strings[nodes.nodeName[candidate]] === "#text";
      })
      .map((candidate) => strings[nodes.nodeValue[candidate]] || "")
      .join("")
      .trim();
    const layoutEntry = (index) => {
      const position = layout.nodeIndex.indexOf(index);
      if (position < 0) return null;
      const styles = {};
      (layout.styles[position] || []).forEach((value, styleIndex) => {
        styles[computedStyles[styleIndex]] = strings[value];
      });
      return { bounds: layout.bounds[position], styles };
    };
    const elements = descendantIndexes
      .filter((index) => strings[nodes.nodeName[index]] !== "#text")
      .map((index) => ({
        index,
        backendNodeId: nodes.backendNodeId[index],
        name: strings[nodes.nodeName[index]].toLowerCase(),
        attributes: attributesAt(index),
        text: textAt(index),
        layout: layoutEntry(index)
      }));
    return { elements };
  } finally {
    await session.detach();
  }
}

function byClass(snapshot, className) {
  return snapshot.elements.find((element) =>
    (element.attributes.class || "").split(/\s+/).includes(className));
}

async function clickElement(page, element) {
  assert(element && element.backendNodeId, "Element has no backend node id");
  const session = await page.context().newCDPSession(page);
  try {
    const resolved = await session.send("DOM.resolveNode", { backendNodeId: element.backendNodeId });
    await session.send("Runtime.callFunctionOn", {
      objectId: resolved.object.objectId,
      functionDeclaration: "function() { this.click(); }",
      awaitPromise: true
    });
  } finally {
    await session.detach();
  }
}

async function clickElementWithPointer(page, element) {
  assert(element && element.layout && element.layout.bounds, "Element has no visible bounds");
  const [x, y, width, height] = element.layout.bounds;
  await page.mouse.click(x + width / 2, y + height / 2);
}

async function waitForSnapshot(page, hostId, predicate, timeout = 120000) {
  const started = Date.now();
  while (Date.now() - started < timeout) {
    const snapshot = await captureAssistant(page, hostId);
    if (snapshot && predicate(snapshot)) return snapshot;
    await page.waitForTimeout(100);
  }
  throw new Error(`Timed out waiting for ${hostId}`);
}

async function main() {
  assert(fs.existsSync(edgePath), `Microsoft Edge not found: ${edgePath}`);
  const tempBase = path.resolve(os.tmpdir());
  const profilePath = fs.mkdtempSync(path.join(tempBase, "english-assistant-edge-test-"));
  assert(path.resolve(profilePath).startsWith(tempBase + path.sep), "Unsafe test profile path");

  const server = http.createServer((_request, response) => {
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    response.end(`<!doctype html><meta charset="utf-8"><title>English Assistant Test</title>
      <main style="margin:120px;font:24px Segoe UI"><p id="sample">Hello from the integration test.</p></main>`);
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;

  let context;
  try {
    context = await chromium.launchPersistentContext(profilePath, {
      executablePath: edgePath,
      headless: false,
      viewport: { width: 1100, height: 720 },
      args: [
        `--disable-extensions-except=${extensionPath}`,
        `--load-extension=${extensionPath}`,
        "--no-first-run",
        "--disable-default-apps",
        "--window-position=-32000,-32000"
      ]
    });
    await context.addInitScript(() => {
      const originalAttachShadow = Element.prototype.attachShadow;
      Element.prototype.attachShadow = function(init) {
        return originalAttachShadow.call(this, { ...init, mode: "open" });
      };
    });
    await context.grantPermissions(["clipboard-read", "clipboard-write"], { origin });

    let worker = context.serviceWorkers()[0];
    if (!worker) worker = await context.waitForEvent("serviceworker", { timeout: 10000 });
    const version = await worker.evaluate(() => chrome.runtime.getManifest().version);
    assert(version === "1.8.0", `Unexpected extension version: ${version}`);

    const page = await context.newPage();
    await page.goto(origin, { waitUntil: "domcontentloaded" });
    await selectTestText(page);

    const toolbarSnapshot = await captureAssistant(page, "english-learning-assistant-buttons", [
      "background-color", "border-radius", "border-top-color"
    ]);
    const toolbarPosition = await page.evaluate(() => {
      const selection = window.getSelection().getRangeAt(0).getBoundingClientRect();
      const host = document.getElementById("english-learning-assistant-buttons");
      return {
        gap: parseFloat(host.style.top) - selection.bottom
      };
    });
    assert(Math.abs(toolbarPosition.gap - 8) <= 1,
      `Toolbar is not directly below the selection: ${toolbarPosition.gap}px`);
    const bar = byClass(toolbarSnapshot, "bar");
    const buttons = toolbarSnapshot.elements.filter((element) => element.name === "button");
    assert(buttons.length === 4, `Toolbar does not contain four segments: ${buttons.length}`);
    const labels = buttons.map((button) => button.text);
    assert(labels[0].includes("朗读"), "Read label missing");
    assert(labels[1].includes("中↔英 翻译"), "Translate label missing");
    assert(labels[2].includes("语速：正常"), "Initial speed label missing");
    assert(buttons[1].attributes.class === "primary", "Translate segment is not primary");
    const closeSvg = toolbarSnapshot.elements.find((element) => element.name === "svg" &&
      element.index > buttons[3].index);
    const styles = {
      background: bar.layout.styles["background-color"],
      borderRadius: bar.layout.styles["border-radius"],
      borderColor: bar.layout.styles["border-top-color"],
      primaryBackground: buttons[1].layout.styles["background-color"],
      closeBackground: closeSvg.layout.styles["background-color"]
    };
    assert(styles.background === "rgb(21, 29, 43)", `Wrong toolbar background: ${styles.background}`);
    assert(styles.borderRadius === "11px", `Wrong toolbar radius: ${styles.borderRadius}`);
    const toolbarRenderedHeight = bar.layout.bounds[3];
    assert(toolbarRenderedHeight >= 51 && toolbarRenderedHeight <= 54,
      `Wrong rendered toolbar height: ${toolbarRenderedHeight}px`);
    assert(styles.borderColor === "rgb(52, 65, 88)", `Wrong toolbar border: ${styles.borderColor}`);
    assert(styles.primaryBackground === "rgb(82, 111, 231)", `Wrong primary background: ${styles.primaryBackground}`);
    assert(styles.closeBackground === "rgb(38, 49, 67)", `Wrong close icon background: ${styles.closeBackground}`);

    await clickElement(page, buttons[2]);
    const slowSnapshot = await waitForSnapshot(page, "english-learning-assistant-buttons",
      (snapshot) => snapshot.elements.some((element) => element.name === "button" &&
        element.text.includes("语速：慢速")));
    const slowButtons = slowSnapshot.elements.filter((element) => element.name === "button");
    await clickElementWithPointer(page, slowButtons[3]);
    await page.waitForFunction(() => !document.getElementById("english-learning-assistant-buttons"));
    await page.waitForTimeout(100);
    assert(await page.locator("#english-learning-assistant-buttons").count() === 0,
      "Toolbar reappeared after a real pointer click on close");

    await selectTestText(page);
    const secondToolbar = await captureAssistant(page, "english-learning-assistant-buttons");
    const secondButtons = secondToolbar.elements.filter((element) => element.name === "button");
    assert(secondButtons[2].text.includes("语速：慢速"), "Speed setting did not persist");
    await clickElement(page, secondButtons[1]);
    const resultSnapshot = await waitForSnapshot(page, "english-learning-assistant-result",
      (snapshot) => Boolean(byClass(snapshot, "card")));
    assert(!byClass(resultSnapshot, "error"), "Translation returned an error card");
    const styledResult = await captureAssistant(page, "english-learning-assistant-result", ["width"]);
    const resultCard = byClass(styledResult, "card");
    const resultCardCssWidth = parseFloat(resultCard.layout.styles.width);
    assert(resultCardCssWidth >= 280 && resultCardCssWidth <= 400,
      `Wrong adaptive result card width: ${resultCardCssWidth}px`);
    const resultPosition = await page.evaluate(() => {
      const selection = window.getSelection().getRangeAt(0).getBoundingClientRect();
      const host = document.getElementById("english-learning-assistant-result");
      const width = parseFloat(host.style.width);
      const left = parseFloat(host.style.left);
      return {
        offsetBelow: parseFloat(host.style.top) - selection.bottom,
        centerOffset: (left + width / 2) - (selection.left + selection.width / 2)
      };
    });
    assert(Math.abs(resultPosition.offsetBelow - 48) <= 1,
      `Result card is not anchored below the selection: ${resultPosition.offsetBelow}px`);
    assert(Math.abs(resultPosition.centerOffset) <= 1,
      `Result card is not centered on the selection: ${resultPosition.centerOffset}px`);
    const textElement = byClass(resultSnapshot, "text");
    const translatedText = textElement.text.trim();
    assert(translatedText.length > 0, "Translation result is empty");

    await clickElement(page, byClass(resultSnapshot, "copy"));
    const copiedSnapshot = await waitForSnapshot(page, "english-learning-assistant-result",
      (snapshot) => Boolean(byClass(snapshot, "copied")));
    assert(byClass(copiedSnapshot, "copy").text.includes("已复制"), "Copy button state did not update");
    const clipboardText = await page.evaluate(() => navigator.clipboard.readText());
    assert(clipboardText === translatedText, "Copied translation does not match the result");

    await clickElement(page, byClass(copiedSnapshot, "read"));
    await waitForSnapshot(page, "english-learning-assistant-result", (snapshot) => {
      const read = byClass(snapshot, "read");
      return read && !("disabled" in read.attributes) && read.text.includes("朗读译文");
    });

    const finalResult = await captureAssistant(page, "english-learning-assistant-result");
    await clickElement(page, byClass(finalResult, "close"));
    await page.waitForFunction(() => !document.getElementById("english-learning-assistant-result"));

    await worker.evaluate(() => new Promise((resolve) => chrome.storage.sync.set({ enabled: false }, resolve)));
    await page.waitForTimeout(100);
    await triggerTestSelection(page);
    await page.waitForTimeout(200);
    assert(await page.locator("#english-learning-assistant-buttons").count() === 0,
      "Disabled extension still showed the toolbar");
    await worker.evaluate(() => new Promise((resolve) => chrome.storage.sync.set({ enabled: true }, resolve)));
    await page.waitForTimeout(100);
    await selectTestText(page);
    const enabledToolbar = await captureAssistant(page, "english-learning-assistant-buttons");
    await clickElement(page, enabledToolbar.elements.filter((element) => element.name === "button")[3]);

    console.log(JSON.stringify({
      pass: true,
      version,
      labels,
      styles,
      toolbarRenderedHeight,
      resultCardCssWidth,
      toolbarGap: toolbarPosition.gap,
      resultOffsetBelow: resultPosition.offsetBelow,
      translatedText,
      speedCycle: "normal-to-slow",
      copy: true,
      speech: true,
      close: true,
      enabledToggle: true
    }, null, 2));
  } finally {
    if (context) await context.close();
    await new Promise((resolve) => server.close(resolve));
    if (fs.existsSync(profilePath)) {
      const resolved = path.resolve(profilePath);
      assert(resolved.startsWith(tempBase + path.sep), "Refusing to remove unsafe profile path");
      fs.rmSync(resolved, { recursive: true, force: true });
    }
  }
}

main().catch((error) => {
  console.error(error.stack || error.message || String(error));
  process.exitCode = 1;
});
