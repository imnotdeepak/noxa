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
  let authorized = enabled;
  const makeElement = (tagName) => ({
    tagName,
    style: {},
    children: [],
    append(...children) { this.children.push(...children); },
    appendChild(child) {
      this.children.push(child);
      if (child.id) elements.set(child.id, child);
    },
    setAttribute() {},
    remove() { elements.delete(this.id); }
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
    browser: { runtime: { sendMessage: async () => ({ enabled: authorized }) } },
    document,
    location: { pathname, hostname },
    MutationObserver: class { observe() {} },
    window: { addEventListener() {} },
    setInterval(callback, milliseconds) { intervals.set(milliseconds, callback); }
  });
  await new Promise(setImmediate);
  return {
    document,
    overlay: elements.get("noxa-instagram-route-block"),
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
  for (const route of ["/", "/direct/inbox/", "/accounts/edit/", "/myprofile/"]) {
    assert.equal((await runAt(route)).overlay, undefined, `${route} should stay available`);
  }
});

test("the script ignores other hosts and fails closed without paid access", async () => {
  assert.equal((await runAt("/reels/", "example.com")).overlay, undefined);
  assert.equal((await runAt("/reels/", "www.instagram.com", false)).overlay, undefined);
});

test("an open Reels page is uncovered when Noxa access is revoked", async () => {
  const page = await runAt("/reels/");
  assert.ok(page.overlay);
  assert.equal(await page.setAuthorized(false), undefined);
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
