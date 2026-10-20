# Instagram Safari filter prototype

This is an isolated Safari Web Extension prototype. It is not embedded in the Noxa iOS app, enabled for customers, or presented as working protection in the app.

It requests access only to `instagram.com` and `www.instagram.com`. The content script hides links to `/reel/`, `/reels/`, and `/explore/`, and covers those direct routes with a way back to the main feed. The main feed, messages, search, and profiles are left available by route. Instagram can change its markup and navigation behavior at any time, and the script has not been checked against logged-in Safari on a physical iPhone. Reels embedded in the feed may still be visible.

Before integrating this into Noxa, validate signed-in and signed-out pages, direct links, navigation after login, feed, messages, search, profiles, localization, extension permission loss, and Reels embedded in the feed. Then package it as an iOS Safari Web Extension in the existing Noxa app and add a user-facing permission and status flow. A successful script test alone must not be presented as confirmed filtering.

Apple's packaging and permission documentation: https://developer.apple.com/documentation/safariservices/packaging-a-web-extension-for-safari and https://developer.apple.com/documentation/safariservices/managing-safari-web-extension-permissions
