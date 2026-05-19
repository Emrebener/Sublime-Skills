#!/usr/bin/env node

import { connect, extractSession, getPage } from "./lib.js";

const { session, rest } = extractSession(process.argv.slice(2));
const url = rest[0];

const b = await connect(session);
const p = await getPage(b);

if (!p) {
	console.error("✗ No active tab found");
	await b.disconnect();
	process.exit(1);
}

let m;
try {
	// Register the LCP observer BEFORE navigation so it is live from the
	// first frame — a one-shot read after load misses LCP.
	await p.evaluateOnNewDocument(() => {
		window.__lcp = null;
		try {
			new PerformanceObserver((list) => {
				for (const e of list.getEntries()) window.__lcp = e.startTime;
			}).observe({ type: "largest-contentful-paint", buffered: true });
		} catch {}
	});

	if (url) {
		await p.goto(url, { waitUntil: "load" });
	} else {
		await p.reload({ waitUntil: "load" });
	}

	// Settle for a late LCP candidate before reading.
	await new Promise((r) => setTimeout(r, 1000));

	m = await p.evaluate(() => {
		const nav = performance.getEntriesByType("navigation")[0] || {};
		const paint = performance.getEntriesByType("paint");
		const fcp = paint.find((e) => e.name === "first-contentful-paint");
		const res = performance.getEntriesByType("resource");
		const slowest = res
			.map((r) => ({ url: r.name, ms: Math.round(r.duration), size: r.transferSize || 0 }))
			.sort((a, b) => b.ms - a.ms)
			.slice(0, 5);
		const totalBytes = res.reduce((s, r) => s + (r.transferSize || 0), 0);
		return {
			ttfb: nav.responseStart ? Math.round(nav.responseStart) : null,
			fcp: fcp ? Math.round(fcp.startTime) : null,
			lcp: window.__lcp != null ? Math.round(window.__lcp) : null,
			dcl: nav.domContentLoadedEventEnd ? Math.round(nav.domContentLoadedEventEnd) : null,
			load: nav.loadEventEnd ? Math.round(nav.loadEventEnd) : null,
			count: res.length,
			totalKB: Math.round(totalBytes / 1024),
			slowest,
		};
	});
} catch (err) {
	console.error(`✗ Trace failed: ${err.message}`);
	await b.disconnect();
	process.exit(1);
}

console.log(`URL: ${p.url()}`);
console.log(`TTFB:                     ${m.ttfb ?? "?"} ms`);
console.log(`First Contentful Paint:   ${m.fcp ?? "?"} ms`);
console.log(`Largest Contentful Paint: ${m.lcp ?? "?"} ms (LCP at capture time)`);
console.log(`DOMContentLoaded:         ${m.dcl ?? "?"} ms`);
console.log(`Load:                     ${m.load ?? "?"} ms`);
console.log(`Subresources:             ${m.count} (${m.totalKB} KB total)`);
console.log("  (the main document is not counted — it is a navigation, not a resource)");
console.log("Slowest requests:");
for (const r of m.slowest) {
	console.log(`  ${r.ms} ms  ${(r.size / 1024).toFixed(1)} KB  ${r.url}`);
}

await b.disconnect();
