"use strict";

// Toolbar popup for the "Open in Spud" Safari Web Extension.
//
// On a known Lemmy instance (detected by the content script's presence in the
// tab) it offers a single "Open in Spud" button that hands the current page to
// the app via the same resolve deep link the in-page banner uses. On any other
// page it shows an inactive "Not a Lemmy instance" message. The popup never
// duplicates the host allowlist: the content script is the source of truth.
//
// Classic script (not a module) so it both loads in Safari and is require()-able
// by the node test; the browser-only wiring is guarded.

// Pure: decide the popup state from the content script's probe reply. A truthy
// { known: true } reply means a known Lemmy instance; null/undefined (no content
// script) means it is not.
function popupStateFromProbe(result) {
    return result && result.known ? "known" : "unknown";
}

// Localized string with an English fallback when i18n is unavailable. Mirrors
// content.js's localized() (the two script contexts cannot share a module).
function localized(key, fallback) {
    try {
        const message = globalThis.browser && globalThis.browser.i18n
            ? globalThis.browser.i18n.getMessage(key)
            : "";
        return message || fallback;
    } catch (e) {
        return fallback;
    }
}

// Queries the active tab and probes its content script. Resolves to the tab and
// the resulting popup state. A tab with no content script (unknown host, or a
// non-injectable page) rejects the sendMessage, which we treat as "unknown".
async function probeActiveTab() {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    const tab = tabs[0];
    if (!tab) {
        return { tab: null, state: "unknown" };
    }
    let result = null;
    try {
        result = await browser.tabs.sendMessage(tab.id, { type: "spud-probe" });
    } catch (e) {
        result = null;
    }
    return { tab: tab, state: popupStateFromProbe(result) };
}

function render(state) {
    document.getElementById("known-state").hidden = state !== "known";
    document.getElementById("unknown-state").hidden = state === "known";
    document.getElementById("open-button").textContent = localized("popup_open", "Open in Spud");
    document.getElementById("unknown-message").textContent = localized("popup_not_lemmy", "Not a Lemmy instance");
    document.getElementById("spud-popup").classList.remove("loading");
}

async function openInSpud(tabId) {
    const errorEl = document.getElementById("error-message");
    errorEl.hidden = true;
    try {
        await browser.tabs.sendMessage(tabId, { type: "spud-open" });
        window.close();
    } catch (e) {
        errorEl.textContent = localized("popup_error", "Couldn't open - try again");
        errorEl.hidden = false;
    }
}

async function init() {
    const probed = await probeActiveTab();
    render(probed.state);
    if (probed.state === "known" && probed.tab) {
        document.getElementById("open-button").addEventListener("click", function () {
            openInSpud(probed.tab.id);
        });
    }
}

// Browser-only entry point. Guarded so requiring this file in node (for the
// helper test) has no side effects.
if (typeof window !== "undefined" && typeof document !== "undefined") {
    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init);
    } else {
        init();
    }
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { popupStateFromProbe };
}
