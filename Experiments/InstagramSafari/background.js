"use strict";

browser.runtime.onMessage.addListener((message) => {
  const types = ["noxa.instagram.filterState", "noxa.youtube.filterState"];
  if (!types.includes(message?.type)) return undefined;
  return browser.runtime.sendNativeMessage("LycheeCorp.Noxa", message)
    .then((response) => ({ enabled: response?.enabled === true }))
    .catch(() => ({ enabled: false }));
});
