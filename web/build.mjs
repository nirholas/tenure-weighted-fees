#!/usr/bin/env node
/**
 * Builds this hook's site.
 *
 * Everything on the page comes from `hook.json`, which is generated from the contract, so the page cannot describe
 * the hook as something it is not. No dependencies: run `node web/build.mjs` and publish `web/dist`.
 */
import {cpSync, existsSync, mkdirSync, readFileSync, writeFileSync} from "node:fs";
import {dirname, join} from "node:path";
import {fileURLToPath} from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const DIST = join(HERE, "dist");
const hook = JSON.parse(readFileSync(join(HERE, "..", "hook.json"), "utf8"));

const SITE = "https://tenure-weighted-fees.pages.dev";
const REPO = "https://github.com/nirholas/tenure-weighted-fees";
const CATALOGUE = "https://hookforge.pages.dev";

let page = readFileSync(join(HERE, "src", "index.html"), "utf8");

// A local deploy writes web/local.json. Merge it over the baked-in config so the demo points at the chain the
// person running it actually has, without them editing anything. Spliced by index rather than by regular
// expression: the pattern would have to survive several layers of templating to get here intact, and this cannot
// be got subtly wrong.
const localPath = join(HERE, "local.json");
if (existsSync(localPath)) {
  const openTag = '<script type="application/json" id="deployments">';
  const closeTag = "</" + "script>";
  const from = page.indexOf(openTag);
  const to = from === -1 ? -1 : page.indexOf(closeTag, from);
  if (from !== -1 && to !== -1) {
    const baked = JSON.parse(page.slice(from + openTag.length, to).split("\u003c").join("<"));
    const local = JSON.parse(readFileSync(localPath, "utf8"));
    const merged = {...baked, chains: {...baked.chains, ...local.chains}};
    const encoded = JSON.stringify(merged).split("<").join("\u003c");
    page = page.slice(0, from + openTag.length) + encoded + page.slice(to);
    console.log("merged web/local.json into the page config");
  }
}

mkdirSync(join(DIST, "assets"), {recursive: true});
writeFileSync(join(DIST, "index.html"), page);
cpSync(join(HERE, "src", "site.css"), join(DIST, "assets", "site.css"));
cpSync(join(HERE, "src", "scene.js"), join(DIST, "assets", "scene.js"));
if (existsSync(join(HERE, "src", "demo.js"))) cpSync(join(HERE, "src", "demo.js"), join(DIST, "assets", "demo.js"));
cpSync(join(HERE, "src", "og.png"), join(DIST, "og.png"));
cpSync(join(HERE, "..", "hook.json"), join(DIST, "hook.json"));

writeFileSync(
  join(DIST, "robots.txt"),
  `User-agent: *
Allow: /

Sitemap: ${SITE}/sitemap.xml
`,
);

writeFileSync(
  join(DIST, "sitemap.xml"),
  `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>${SITE}/</loc><lastmod>${new Date().toISOString().slice(0, 10)}</lastmod><priority>1.0</priority></url>
</urlset>
`,
);

writeFileSync(
  join(DIST, "llms.txt"),
  `# ${hook.name}

> ${hook.summary}

A production Uniswap v4 hook. Source: ${REPO}. Part of the HookForge catalogue: ${CATALOGUE}

## How it works
${hook.description}

## Prior art
${hook.priorArt}

## Where it does not help
${hook.limitation}

## Facts
Slug: ${hook.slug}
Contract: ${hook.contract}
Callbacks: ${Object.entries(hook.permissions ?? {}).filter(([, on]) => on).map(([n]) => n).join(", ") || "none"}
Parameters: ${(hook.configure?.fields ?? []).map((f) => f.name + " (" + f.type + ")").join(", ") || "none"}
Dynamic fee required: ${hook.properties?.dynamicFee ? "yes" : "no"}

## Caveats
- Unaudited.
- A deployment with status "deterministic" is a mined CREATE2 address with no code at it yet. Never present one as live.
`,
);

writeFileSync(
  join(DIST, "_headers"),
  `/assets/*
  Cache-Control: public, max-age=31536000, immutable

/hook.json
  Cache-Control: public, max-age=300
  Access-Control-Allow-Origin: *

/llms.txt
  Content-Type: text/plain; charset=utf-8
  Access-Control-Allow-Origin: *

/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
`,
);

console.log("built " + hook.slug + " site into web/dist");
