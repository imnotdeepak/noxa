(() => {
  "use strict";

  const host = location.hostname.toLowerCase();
  if (host !== "instagram.com" && host !== "www.instagram.com") return;

  const hiddenLinkSelector = [
    'a[href^="/reel/"]',
    'a[href^="/reels/"]',
    'a[href^="/explore/"]',
    'a[href^="https://www.instagram.com/reel/"]',
    'a[href^="https://www.instagram.com/reels/"]',
    'a[href^="https://www.instagram.com/explore/"]'
  ].join(",");

  const style = document.createElement("style");
  style.textContent = `${hiddenLinkSelector} { display: none !important; }`;
  (document.head || document.documentElement).appendChild(style);

  function isBlockedPath(pathname) {
    return /^\/(?:reel|reels|explore)(?:\/|$)/i.test(pathname);
  }

  function updateRoute() {
    if (!document.body) return;
    const blocked = isBlockedPath(location.pathname);
    let overlay = document.getElementById("noxa-instagram-route-block");
    if (!blocked) {
      overlay?.remove();
      return;
    }
    if (overlay) return;

    overlay = document.createElement("div");
    overlay.id = "noxa-instagram-route-block";
    overlay.setAttribute("role", "main");
    overlay.style.cssText = [
      "position:fixed", "inset:0", "z-index:2147483647", "background:#07150f",
      "color:#fff", "display:flex", "align-items:center", "justify-content:center",
      "padding:24px", "box-sizing:border-box", "font:16px -apple-system,BlinkMacSystemFont,sans-serif"
    ].join(";");
    const panel = document.createElement("div");
    panel.style.cssText = "max-width:340px;text-align:center;line-height:1.5";
    const heading = document.createElement("h1");
    heading.textContent = "This part of Instagram is paused";
    heading.style.cssText = "font-size:24px;line-height:1.2";
    const description = document.createElement("p");
    description.textContent = "Noxa keeps the main feed available while hiding Reels and Explore in Safari.";
    const returnLink = document.createElement("a");
    returnLink.href = "/";
    returnLink.textContent = "Return to Instagram feed";
    returnLink.style.cssText = "color:#a8d84a;text-decoration:underline";
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
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });
  window.addEventListener("popstate", updateRoute);
  window.addEventListener("pageshow", updateRoute);
  setInterval(() => {
    if (location.pathname !== previousPath) {
      previousPath = location.pathname;
      updateRoute();
    }
  }, 500);
})();
