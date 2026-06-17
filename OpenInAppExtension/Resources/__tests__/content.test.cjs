"use strict";

// Pure-helper tests for the "Open in Spud" content script. Run with:
//   node OpenInAppExtension/Resources/__tests__/content.test.cjs

const assert = require("node:assert");
const { lemmyDeepLink, isLemmyContentPath } = require("../content.js");

// Path detection: only /post, /comment, /c, /u with a following segment.
assert.strictEqual(isLemmyContentPath("/post/123"), true);
assert.strictEqual(isLemmyContentPath("/comment/9"), true);
assert.strictEqual(isLemmyContentPath("/c/news"), true);
assert.strictEqual(isLemmyContentPath("/c/news@beehaw.org"), true);
assert.strictEqual(isLemmyContentPath("/u/alice"), true);
assert.strictEqual(isLemmyContentPath("/about"), false);
assert.strictEqual(isLemmyContentPath("/"), false);
assert.strictEqual(isLemmyContentPath("/post"), false);

// Deep-link mapping: page URL wrapped in the resolve deep link.
assert.strictEqual(
    lemmyDeepLink("https://lemmy.world/post/123"),
    "info.ddenis.spud://internal/resolve?url=" + encodeURIComponent("https://lemmy.world/post/123")
);
assert.strictEqual(
    lemmyDeepLink("https://beehaw.org/comment/9"),
    "info.ddenis.spud://internal/resolve?url=" + encodeURIComponent("https://beehaw.org/comment/9")
);

console.log("content.js helper tests passed");
