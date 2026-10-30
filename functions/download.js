import { count } from "./_counter.js";

// Counts a download, then sends the visitor to the zip named in the update feed.
export async function onRequestGet(context) {
  const feed = await context.env.ASSETS.fetch(new URL("/update.json", context.request.url));
  const release = feed.ok ? await feed.json() : null;
  const name = release?.assets?.[0]?.name;
  if (!name) return new Response("Download not available", { status: 404 });
  count(context, "download");
  return Response.redirect(new URL(`/downloads/${name}`, context.request.url), 302);
}
