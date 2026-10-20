const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const script = fs.readFileSync(path.join(__dirname, "instagram-filter.js"), "utf8");

function runAt(pathname, hostname = "www.instagram.com") {
  const elements = new Map();
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
    document,
    location: { pathname, hostname },
    MutationObserver: class { observe() {} },
    window: { addEventListener() {} },
    setInterval() {}
  });
  return { document, overlay: elements.get("noxa-instagram-route-block") };
}

test("direct Reels and Explore routes are covered, including a single reel", () => {
  for (const route of ["/reel/ABC/", "/reels/", "/explore/tags/focus/"]) {
    const { overlay } = runAt(route);
    assert.ok(overlay, `${route} should be covered`);
    assert.equal(overlay.children[0].children[2].href, "/");
  }
});

test("the feed and useful routes stay available", () => {
  for (const route of ["/", "/direct/inbox/", "/accounts/edit/", "/myprofile/"]) {
    assert.equal(runAt(route).overlay, undefined, `${route} should stay available`);
  }
});

test("the script ignores other hosts", () => {
  assert.equal(runAt("/reels/", "example.com").overlay, undefined);
});
