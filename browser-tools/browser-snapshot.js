#!/usr/bin/env node

import { connect, extractSession, getPage } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const includeAll = rest.includes("--all");

const b = await connect(session);
const p = await getPage(b);
if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

const tree = await p.evaluate((includeAll) => {
	let counter = 0;
	const INTERACTIVE = new Set(["A", "BUTTON", "INPUT", "SELECT", "TEXTAREA"]);
	const LANDMARK = new Set([
		"FORM", "NAV", "MAIN", "HEADER", "FOOTER", "ASIDE", "SECTION",
		"H1", "H2", "H3", "H4", "H5", "H6", "UL", "OL",
	]);

	function visible(el) {
		const s = getComputedStyle(el);
		if (s.display === "none" || s.visibility === "hidden" || s.opacity === "0") return false;
		const r = el.getBoundingClientRect();
		return r.width > 0 && r.height > 0;
	}
	function role(el) {
		const explicit = el.getAttribute("role");
		if (explicit) return explicit;
		const tag = el.tagName;
		if (tag === "A" && el.hasAttribute("href")) return "link";
		if (tag === "BUTTON") return "button";
		if (tag === "INPUT") {
			const t = (el.getAttribute("type") || "text").toLowerCase();
			if (t === "checkbox") return "checkbox";
			if (t === "radio") return "radio";
			if (t === "submit" || t === "button") return "button";
			return "textbox";
		}
		if (tag === "SELECT") return "combobox";
		if (tag === "TEXTAREA") return "textbox";
		if (/^H[1-6]$/.test(tag)) return "heading";
		return tag.toLowerCase();
	}
	function name(el) {
		const aria = el.getAttribute("aria-label");
		if (aria) return aria.trim();
		if (el.id) {
			const lbl = document.querySelector(`label[for="${CSS.escape(el.id)}"]`);
			if (lbl) return lbl.textContent.trim();
		}
		const closestLabel = el.closest("label");
		if (closestLabel) return closestLabel.textContent.trim().replace(/\s+/g, " ");
		if (el.tagName === "INPUT" && el.getAttribute("placeholder")) {
			return el.getAttribute("placeholder").trim();
		}
		if (el.tagName === "IMG") return (el.getAttribute("alt") || "").trim();
		const text = el.textContent.trim().replace(/\s+/g, " ");
		return text.length > 80 ? text.slice(0, 80) + "…" : text;
	}
	function interesting(el) {
		if (INTERACTIVE.has(el.tagName)) return true;
		if (el.hasAttribute("role")) return true;
		if (el.hasAttribute("tabindex")) return true;
		if (el.isContentEditable) return true;
		if (includeAll && LANDMARK.has(el.tagName)) return true;
		return false;
	}

	const lines = [];
	function walk(el, depth) {
		let nextDepth = depth;
		if (interesting(el) && visible(el)) {
			const ref = "e" + ++counter;
			el.setAttribute("data-ct-ref", ref);
			const r = role(el);
			const n = name(el);
			let state = "";
			if (el.disabled) state += " disabled";
			if (el.checked) state += " checked";
			lines.push("  ".repeat(depth) + `${r}${n ? ` "${n}"` : ""}${state} [ref=${ref}]`);
			nextDepth = depth + 1;
		}
		for (const child of el.children) walk(child, nextDepth);
	}

	// Clear refs from any previous snapshot so ids do not accumulate.
	document.querySelectorAll("[data-ct-ref]").forEach((e) => e.removeAttribute("data-ct-ref"));
	walk(document.body, 0);
	return lines.join("\n");
}, includeAll);

console.log(`URL: ${p.url()}`);
console.log(tree || "(no interactive elements found)");

await b.disconnect();
