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
