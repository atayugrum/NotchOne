import { panel } from "./panel.js";
import { country, isAuthorized, isVisit, record, referrer, summary } from "./stats.js";

// Serves the site and counts downloads, update checks and visits. /panel is the private dashboard.
const secureHeaders = {
  "Cache-Control": "no-store",
  "X-Robots-Tag": "noindex, nofollow",
  "X-Frame-Options": "DENY",
  "Referrer-Policy": "no-referrer",
};

async function download(context) {
  const { request, env } = context;
  const feed = await env.ASSETS.fetch(new URL("/update.json", request.url));
  const release = feed.ok ? await feed.json() : null;
  // The installer for people; the app's own updates use the zip.
  const name = release?.assets?.find((asset) => asset.name.endsWith(".dmg"))?.name;
  if (!name) return new Response("Download not available", { status: 404 });
  record(context, "download", country(request));
  return Response.redirect(new URL(`/downloads/${name}`, request.url), 302);
}

async function panelData({ request, env }) {
  if (!(await isAuthorized(request, env))) {
    await new Promise((resolve) => setTimeout(resolve, 800));
    return Response.json({ error: "unauthorized" }, { status: 401, headers: secureHeaders });
  }
  return Response.json(await summary(env), { headers: secureHeaders });
}

function panelPage() {
  return new Response(panel, {
    headers: {
      ...secureHeaders,
      "Content-Type": "text/html; charset=utf-8",
      "Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'none'",
    },
  });
}

async function site(context) {
  const { request, env } = context;
  const response = await env.ASSETS.fetch(request);
  if (isVisit(request, response)) {
    record(context, "visit", country(request));
    const source = referrer(request);
    if (source) record(context, "referrer", source);
  }
  return response;
}

export default {
  fetch(request, env, ctx) {
    const context = { request, env, waitUntil: (work) => ctx.waitUntil(work) };
    const { pathname } = new URL(request.url);
    if (pathname === "/panel") return panelPage();
    if (pathname === "/panel/data" && request.method === "POST") return panelData(context);
    if (pathname === "/download") return download(context);
    if (pathname === "/update.json") {
      record(context, "check", country(request));
      return env.ASSETS.fetch(request);
    }
    return site(context);
  },
};
