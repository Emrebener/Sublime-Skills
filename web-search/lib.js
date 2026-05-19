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
