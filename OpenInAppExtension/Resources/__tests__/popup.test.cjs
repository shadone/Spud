"use strict";

// Pure-helper tests for the "Open in Spud" toolbar popup. Run with:
//   node OpenInAppExtension/Resources/__tests__/popup.test.cjs

const assert = require("node:assert");
const { popupStateFromProbe } = require("../popup.js");

// A truthy { known: true } reply means the active tab is a known Lemmy instance.
assert.strictEqual(popupStateFromProbe({ known: true }), "known");

// No content script / no reply -> not a known instance.
assert.strictEqual(popupStateFromProbe(null), "unknown");
assert.strictEqual(popupStateFromProbe(undefined), "unknown");
assert.strictEqual(popupStateFromProbe({}), "unknown");
assert.strictEqual(popupStateFromProbe({ known: false }), "unknown");

console.log("popup.js helper tests passed");
