// Daily downloads and update checks for the last 30 days: /stats?key=<STATS_KEY>
export async function onRequestGet(context) {
  const { COUNTS, STATS_KEY } = context.env;
  const key = new URL(context.request.url).searchParams.get("key");
  if (!COUNTS || !STATS_KEY || key !== STATS_KEY) return new Response("Not found", { status: 404 });
  const days = Array.from({ length: 30 }, (_, index) => new Date(Date.now() - index * 86_400_000).toISOString().slice(0, 10));
  const rows = await Promise.all(days.map(async (day) => ({
    day,
    downloads: Number(await COUNTS.get(`download:${day}`) ?? 0),
    checks: Number(await COUNTS.get(`check:${day}`) ?? 0),
  })));
  const total = rows.reduce((sum, row) => sum + row.downloads, 0);
  return Response.json({ downloadsLast30Days: total, days: rows }, { headers: { "Cache-Control": "no-store" } });
}
