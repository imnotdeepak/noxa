"use strict";

browser.runtime.onMessage.addListener((message) => {
  if (message?.type !== "noxa.instagram.filterState") return undefined;
  return browser.runtime.sendNativeMessage("LycheeCorp.Noxa", message)
    .then((response) => ({ enabled: response?.enabled === true }))
    .catch(() => ({ enabled: false }));
});
