const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const script = fs.readFileSync(path.join(__dirname, "youtube-filter.js"), "utf8");
const backgroundScript = fs.readFileSync(path.join(__dirname, "background.js"), "utf8");

async function runAt(pathname, hostname = "m.youtube.com", enabled = true) {
  const elements = new Map();
  const intervals = new Map();
  const listeners = new Map();
  let mutationObserver;
  let authorized = enabled;
  let paused = 0;
  const requests = [];
  const makeElement = (tagName) => ({
    tagName,
    style: {},
    children: [],
    append(...children) { this.children.push(...children); },
    appendChild(child) {
      this.children.push(child);
      child.isConnected = true;
      if (child.id) elements.set(child.id, child);
    },
    setAttribute() {},
    remove() {
      this.isConnected = false;
      elements.delete(this.id);
    }
  });
  const document = {
    body: makeElement("body"),
    head: makeElement("head"),
    documentElement: makeElement("html"),
    createElement: makeElement,
    getElementById: (id) => elements.get(id),
    querySelectorAll: () => [{ pause() { paused += 1; } }],
    addEventListener() {}
  };
  const location = { pathname, hostname };
  vm.runInNewContext(script, {
    browser: { runtime: { sendMessage: async (message) => {
      requests.push(message);
      return { enabled: authorized };
    } } },
    document,
    location,
    MutationObserver: class {
      constructor(callback) { mutationObserver = callback; }
      observe() {}
    },
    window: { addEventListener(name, callback) { listeners.set(name, callback); } },
    setInterval(callback, milliseconds) { intervals.set(milliseconds, callback); }
  });
  await new Promise(setImmediate);
  return {
    document,
    requests,
    get paused() { return paused; },
    overlay: () => elements.get("noxa-youtube-route-block"),
    navigate(nextPath) {
      location.pathname = nextPath;
      listeners.get("yt-navigate-finish")?.();
      return elements.get("noxa-youtube-route-block");
    },
    async setAuthorized(nextValue) {
      authorized = nextValue;
      intervals.get(60_000)?.();
      await new Promise(setImmediate);
      return elements.get("noxa-youtube-route-block");
    },
    mutate() { mutationObserver(); }
  };
}

test("Shorts pages are covered and their video is paused", async () => {
  for (const route of ["/shorts/abc123", "/shorts/", "/shorts"]) {
    const page = await runAt(route);
    assert.ok(page.overlay(), `${route} should be covered`);
    assert.equal(page.overlay().children[0].children[2].href, "/");
    assert.ok(page.paused > 0);
  }
});

test("regular videos, search, subscriptions and channels stay available", async () => {
  for (const route of ["/", "/watch", "/results", "/feed/subscriptions", "/@creator", "/@creator/shorts-tips"]) {
    assert.equal((await runAt(route)).overlay(), undefined, `${route} should stay available`);
  }
});

test("works on the desktop site too", async () => {
  assert.ok((await runAt("/shorts/abc", "www.youtube.com")).overlay());
});

test("Shorts shelves and links are hidden by the stylesheet", async () => {
  const page = await runAt("/");
  const css = page.document.head.children[0].textContent;
  for (const selector of ['a[href^="/shorts/"]', "ytm-reel-shelf-renderer", "ytd-reel-shelf-renderer"]) {
    assert.ok(css.includes(selector), selector);
  }
});

test("navigating into Shorts without a reload is covered", async () => {
  const page = await runAt("/");
  assert.equal(page.overlay(), undefined);
  assert.ok(page.navigate("/shorts/xyz"));
  assert.equal(page.navigate("/watch"), undefined);
});

test("the script ignores other hosts and fails closed without paid access", async () => {
  const other = await runAt("/shorts/abc", "example.com");
  assert.equal(other.overlay(), undefined);
  assert.equal(other.requests.length, 0);
  const youtube = await runAt("/shorts/abc");
  assert.equal(youtube.requests[0].type, "noxa.youtube.filterState");
  assert.equal((await runAt("/shorts/abc", "m.youtube.com", false)).overlay(), undefined);
});

test("an open Shorts page is uncovered when Noxa access is revoked", async () => {
  const page = await runAt("/shorts/abc");
  assert.ok(page.overlay());
  assert.equal(await page.setAuthorized(false), undefined);
});

test("background forwards YouTube requests and fails closed", async () => {
  let listener;
  const runtime = {
    onMessage: { addListener: (callback) => { listener = callback; } },
    sendNativeMessage: async () => { throw new Error("native handler unavailable"); }
  };
  vm.runInNewContext(backgroundScript, { browser: { runtime } });
  assert.equal((await listener({ type: "noxa.youtube.filterState" })).enabled, false);
  runtime.sendNativeMessage = async () => ({ enabled: true });
  assert.equal((await listener({ type: "noxa.youtube.filterState" })).enabled, true);
  assert.equal(listener({ type: "something.else" }), undefined);
});
