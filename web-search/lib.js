import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

// Resolve the SearXNG base URL. Order: SEARXNG_URL env var, then a
// config.json in the skill directory, then throw. The returned URL has any
// trailing slash removed so request paths can be appended cleanly.
export function resolveEndpoint(env, skillDir) {
	let url = env.SEARXNG_URL;
	if (!url) {
		const cfgPath = join(skillDir, "config.json");
		if (existsSync(cfgPath)) {
			let parsed;
			try {
				parsed = JSON.parse(readFileSync(cfgPath, "utf8"));
			} catch {
				throw new Error(`config.json is not valid JSON: ${cfgPath}`);
			}
			url = parsed.searxng_url;
		}
	}
	if (!url) {
		throw new Error(
			"No SearXNG endpoint configured. Set the SEARXNG_URL environment " +
				"variable, or copy config.example.json to config.json and set searxng_url.",
		);
	}
	return url.replace(/\/+$/, "");
}

const CATEGORIES = ["general", "news", "images", "videos"];
const TIME_RANGES = ["day", "week", "month", "year"];
const SAFE_LEVELS = ["0", "1", "2"];

// Parse the CLI argument array (everything after `node search.js`) into a
// validated options object. Throws Error on an unknown flag or bad value.
// Non-flag arguments are joined with spaces into the query.
export function parseArgs(argv) {
	const opts = {
		query: "",
		count: 10,
		category: "general",
		time: null,
		lang: "all",
		safe: "0",
		json: false,
	};
	const positional = [];
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (a === "--json") {
			opts.json = true;
		} else if (a === "--count") {
			const n = Number(argv[++i]);
			if (!Number.isInteger(n) || n < 1) {
				throw new Error("--count must be a positive integer");
			}
			opts.count = n;
		} else if (a === "--category") {
			const v = argv[++i];
			if (!CATEGORIES.includes(v)) {
				throw new Error(`--category must be one of: ${CATEGORIES.join(", ")}`);
			}
			opts.category = v;
		} else if (a === "--time") {
			const v = argv[++i];
			if (!TIME_RANGES.includes(v)) {
				throw new Error(`--time must be one of: ${TIME_RANGES.join(", ")}`);
			}
			opts.time = v;
		} else if (a === "--lang") {
			opts.lang = argv[++i];
		} else if (a === "--safe") {
			const v = argv[++i];
			if (!SAFE_LEVELS.includes(v)) {
				throw new Error("--safe must be 0, 1, or 2");
			}
			opts.safe = v;
		} else if (a.startsWith("--")) {
			throw new Error(`unknown flag: ${a}`);
		} else {
			positional.push(a);
		}
	}
	opts.query = positional.join(" ").trim();
	return opts;
}

// Build the SearXNG JSON search request URL. `base` is the trailing-slash-free
// endpoint from resolveEndpoint; `opts` is the object from parseArgs. The URL
// API handles all parameter encoding.
export function buildSearchUrl(base, opts) {
	const u = new URL(base + "/search");
	u.searchParams.set("q", opts.query);
	u.searchParams.set("format", "json");
	u.searchParams.set("categories", opts.category);
	u.searchParams.set("language", opts.lang);
	u.searchParams.set("safesearch", opts.safe);
	if (opts.time) u.searchParams.set("time_range", opts.time);
	return u.toString();
}

// Render SearXNG's `results` array. Takes the first `count` entries and
// returns either a human-readable text block or a JSON array string.
// Missing fields on a result are tolerated and become empty strings.
export function formatResults(results, count, asJson) {
	const top = results.slice(0, count).map((r, i) => ({
		rank: i + 1,
		title: r.title || "",
		url: r.url || "",
		snippet: (r.content || "").trim(),
		engine: r.engine || "",
	}));
	if (asJson) return JSON.stringify(top, null, 2);
	return top.map((r) => `${r.rank}. ${r.title}\n   ${r.url}\n   ${r.snippet}`).join("\n\n");
}
