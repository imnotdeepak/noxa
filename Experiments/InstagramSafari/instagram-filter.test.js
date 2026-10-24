const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const script = fs.readFileSync(path.join(__dirname, "instagram-filter.js"), "utf8");
const backgroundScript = fs.readFileSync(path.join(__dirname, "background.js"), "utf8");

async function runAt(pathname, hostname = "www.instagram.com", enabled = true) {
  const elements = new Map();
  const intervals = new Map();
  let mutationObserver;
  let authorized = enabled;
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
  const body = makeElement("body");
  const document = {
    body,
    head: makeElement("head"),
    documentElement: makeElement("html"),
    createElement: makeElement,
    getElementById: (id) => elements.get(id),
    addEventListener() {}
  };
  vm.runInNewContext(script, {
    browser: { runtime: { sendMessage: async (message) => {
      requests.push(message);
      return { enabled: authorized };
    } } },
    document,
    location: { pathname, hostname },
    MutationObserver: class {
      constructor(callback) { mutationObserver = callback; }
      observe() {}
    },
    window: { addEventListener() {} },
    setInterval(callback, milliseconds) { intervals.set(milliseconds, callback); }
  });
  await new Promise(setImmediate);
  return {
    document,
    requests,
    overlay: elements.get("noxa-instagram-route-block"),
    mutate() {
      mutationObserver();
      return elements.get("noxa-instagram-route-block");
    },
    async setAuthorized(nextValue) {
      authorized = nextValue;
      intervals.get(60_000)?.();
      await new Promise(setImmediate);
      return elements.get("noxa-instagram-route-block");
    }
  };
}

test("direct Reels and Explore routes are covered, including a single reel", async () => {
  for (const route of ["/reel/ABC/", "/reels/", "/explore/tags/focus/"]) {
    const { overlay } = await runAt(route);
    assert.ok(overlay, `${route} should be covered`);
    assert.equal(overlay.children[0].children[2].href, "/");
  }
});

test("the feed and useful routes stay available", async () => {
  for (const route of ["/", "/direct/inbox/", "/accounts/edit/", "/myprofile/", "/explore/search", "/explore/search/", "/explore/search/keyword/"]) {
    assert.equal((await runAt(route)).overlay, undefined, `${route} should stay available`);
  }
});

test("search links remain visible while Explore links are hidden", async () => {
  const page = await runAt("/");
  const css = page.document.head.children[0].textContent;
  assert.ok(css.includes(':not([href^="/explore/search/"])'));
  assert.ok(css.includes(':not([href="/explore/search"])'));
  assert.ok(css.includes(':not([href^="https://www.instagram.com/explore/search/"])'));
});

test("the script ignores other hosts and fails closed without paid access", async () => {
  const otherHost = await runAt("/reels/", "example.com");
  assert.equal(otherHost.overlay, undefined);
  assert.equal(otherHost.requests.length, 0);
  const instagram = await runAt("/reels/");
  assert.equal(instagram.requests[0].host, "www.instagram.com");
  assert.equal((await runAt("/reels/", "www.instagram.com", false)).overlay, undefined);
});

test("an open Reels page is uncovered when Noxa access is revoked", async () => {
  const page = await runAt("/reels/");
  assert.ok(page.overlay);
  assert.equal(await page.setAuthorized(false), undefined);
});

test("Instagram cannot leave a blocked route exposed after replacing page nodes", async () => {
  const page = await runAt("/reels/");
  page.overlay.remove();
  assert.equal(page.document.getElementById("noxa-instagram-route-block"), undefined);
  assert.ok(page.mutate());
});

test("hidden Reels links are restored after Instagram replaces the style node", async () => {
  const page = await runAt("/");
  const style = page.document.head.children[0];
  assert.ok(style.textContent.includes('/reel/'));
  style.remove();
  assert.equal(style.isConnected, false);
  page.mutate();
  assert.equal(style.isConnected, true);
});

test("background messaging fails closed when the native subscription check is unavailable", async () => {
  let listener;
  const runtime = {
    onMessage: { addListener: (callback) => { listener = callback; } },
    sendNativeMessage: async () => { throw new Error("native handler unavailable"); }
  };
  vm.runInNewContext(backgroundScript, { browser: { runtime } });
  assert.equal((await listener({ type: "noxa.instagram.filterState" })).enabled, false);
  runtime.sendNativeMessage = async () => ({ enabled: true });
  assert.equal((await listener({ type: "noxa.instagram.filterState" })).enabled, true);
});
