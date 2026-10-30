(() => {
  "use strict";

  const host = location.hostname.toLowerCase();
  if (!["youtube.com", "www.youtube.com", "m.youtube.com"].includes(host)) return;

  // Shorts links, shelves and tabs on the mobile and desktop sites. Regular
  // videos, search, subscriptions and the library are left alone.
  const hiddenSelector = [
    'a[href^="/shorts/"]',
    'a[href^="https://www.youtube.com/shorts/"]',
    'a[href^="https://m.youtube.com/shorts/"]',
    "ytm-reel-shelf-renderer",
    "ytd-reel-shelf-renderer",
    "ytm-shorts-lockup-view-model",
    "ytm-shorts-lockup-view-model-v2",
    "ytd-rich-shelf-renderer[is-shorts]",
    "grid-shelf-view-model:has(a[href^=\"/shorts/\"])",
    "ytm-rich-section-renderer:has(ytm-shorts-lockup-view-model)",
    "ytm-rich-section-renderer:has(a[href^=\"/shorts/\"])",
    "ytd-rich-section-renderer:has(a[href^=\"/shorts/\"])",
    "ytm-video-with-context-renderer:has(a[href^=\"/shorts/\"])",
    "ytd-video-renderer:has(a[href^=\"/shorts/\"])",
    "ytd-rich-item-renderer:has(a[href^=\"/shorts/\"])",
    "ytm-pivot-bar-item-renderer:has(.pivot-shorts)",
    "ytm-pivot-bar-item-renderer:has(a[href^=\"/shorts\"])",
    'ytd-guide-entry-renderer:has(a[title="Shorts"])',
    'ytd-mini-guide-entry-renderer[aria-label="Shorts"]',
    'yt-chip-cloud-chip-renderer:has(a[href^="/shorts"])'
  ].join(",");

  const style = document.createElement("style");
  style.textContent = `${hiddenSelector} { display: none !important; }`;
  let enabled = false;

  async function refreshPermission() {
    let nextEnabled = false;
    try {
      const response = await browser.runtime.sendMessage({
        type: "noxa.youtube.filterState",
        host
      });
      nextEnabled = response?.enabled === true;
    } catch {
      // When Safari or native messaging is unavailable, leave YouTube alone.
    }
    if (nextEnabled === enabled) return;
    enabled = nextEnabled;
    if (enabled) {
      (document.head || document.documentElement).appendChild(style);
    } else {
      style.remove();
    }
    updateRoute();
  }

  function isBlockedPath(pathname) {
    return /^\/shorts(?:\/|$)/i.test(pathname);
  }

  function updateRoute() {
    if (!document.body) return;
    const blocked = enabled && isBlockedPath(location.pathname);
    let overlay = document.getElementById("noxa-youtube-route-block");
    if (!blocked) {
      overlay?.remove();
      return;
    }
    // Shorts autoplay with sound, so pause anything already playing.
    document.querySelectorAll("video").forEach((video) => video.pause());
    if (overlay) return;

    overlay = document.createElement("div");
    overlay.id = "noxa-youtube-route-block";
    overlay.setAttribute("role", "main");
    overlay.style.cssText = [
      "position:fixed", "inset:0", "z-index:2147483647", "background:#030503",
      "color:#fff", "display:flex", "align-items:center", "justify-content:center",
      "padding:24px", "box-sizing:border-box", "font:16px -apple-system,BlinkMacSystemFont,sans-serif"
    ].join(";");
    const panel = document.createElement("div");
    panel.style.cssText = "max-width:340px;text-align:center;line-height:1.5";
    const heading = document.createElement("h1");
    heading.textContent = "Shorts are paused";
    heading.style.cssText = "font-size:24px;line-height:1.2";
    const description = document.createElement("p");
    description.textContent = "Noxa keeps the rest of YouTube available while hiding Shorts in Safari.";
    const returnLink = document.createElement("a");
    returnLink.href = "/";
    returnLink.textContent = "Return to YouTube";
    returnLink.style.cssText = "color:#a8f000;text-decoration:underline";
    panel.append(heading, description, returnLink);
    overlay.appendChild(panel);
    document.body.appendChild(overlay);
  }

  document.addEventListener("DOMContentLoaded", updateRoute, { once: true });
  updateRoute();
  let previousPath = location.pathname;
  const observer = new MutationObserver(() => {
    if (location.pathname !== previousPath) {
      previousPath = location.pathname;
      updateRoute();
    }
    if (enabled && !style.isConnected) {
      (document.head || document.documentElement).appendChild(style);
    }
    if (enabled && isBlockedPath(location.pathname)) {
      updateRoute();
    }
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });
  window.addEventListener("popstate", updateRoute);
  window.addEventListener("pageshow", updateRoute);
  // YouTube navigates without reloading the page.
  window.addEventListener("yt-navigate-finish", updateRoute);
  refreshPermission();
  setInterval(refreshPermission, 60_000);
  setInterval(() => {
    if (location.pathname !== previousPath) {
      previousPath = location.pathname;
      updateRoute();
    }
  }, 500);
})();
