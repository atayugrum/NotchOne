// Daily totals by country and referrer only: no IP address, cookie or other identifier is stored.
const bots = /bot|crawl|spider|slurp|preview|facebookexternalhit|curl|wget|python|headless/i;
const days = 30;

export function record(context, metric, value) {
  const day = new Date().toISOString().slice(0, 10);
  const write = context.env.DB.prepare(
    "INSERT INTO counts (day, metric, value, n) VALUES (?, ?, ?, 1) " +
      "ON CONFLICT (day, metric, value) DO UPDATE SET n = n + 1",
  ).bind(day, metric, value).run().catch(() => {});
  context.waitUntil(write);
}

export const country = (request) => request.cf?.country ?? "XX";

/// A page opened by a person, not an asset or a crawler.
export function isVisit(request, response) {
  const { pathname } = new URL(request.url);
  return request.method === "GET" && response.status === 200
    && (request.headers.get("accept") ?? "").includes("text/html")
    && !/\.[a-z0-9]+$/i.test(pathname.replace(/\.html$/, ""))
    && !bots.test(request.headers.get("user-agent") ?? "");
}

export function referrer(request) {
  try {
    const host = new URL(request.headers.get("referer")).hostname.replace(/^www\./, "");
    const own = new URL(request.url).hostname.replace(/^www\./, "");
    return host === own ? null : host.slice(0, 60);
  } catch {
    return "direct";
  }
}

async function sameKey(given, expected) {
  const encode = (text) => crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  const [a, b] = await Promise.all([encode(given), encode(expected)]);
  return crypto.subtle.timingSafeEqual(a, b);
}

export async function isAuthorized(request, env) {
  const given = (request.headers.get("authorization") ?? "").replace(/^Bearer /, "");
  return Boolean(env.STATS_KEY) && Boolean(given) && sameKey(given, env.STATS_KEY);
}

/// Downloads and update checks counted on pages.dev, kept in KV by the Pages functions.
async function pagesDevTotals(env, dayList) {
  const rows = await Promise.all(dayList.map(async (day) => ({
    day,
    download: Number(await env.COUNTS.get(`download:${day}`) ?? 0),
    check: Number(await env.COUNTS.get(`check:${day}`) ?? 0),
  })));
  return rows;
}

const ranked = (rows, metric) => rows
  .filter((row) => row.metric === metric)
  .reduce((totals, row) => totals.set(row.value, (totals.get(row.value) ?? 0) + row.n), new Map());

const list = (totals) => [...totals]
  .map(([name, n]) => ({ name, n }))
  .sort((a, b) => b.n - a.n)
  .slice(0, 12);

export async function summary(env) {
  const dayList = Array.from({ length: days }, (_, index) =>
    new Date(Date.now() - (days - 1 - index) * 86_400_000).toISOString().slice(0, 10));
  const { results } = await env.DB.prepare("SELECT day, metric, value, n FROM counts WHERE day >= ?")
    .bind(dayList[0]).all();
  const legacy = await pagesDevTotals(env, dayList);
  const daily = dayList.map((day, index) => {
    const sum = (metric) => results
      .filter((row) => row.day === day && row.metric === metric)
      .reduce((total, row) => total + row.n, 0);
    return {
      day,
      visits: sum("visit"),
      downloads: sum("download") + legacy[index].download,
      checks: sum("check") + legacy[index].check,
    };
  });
  const total = (key) => daily.reduce((sum, row) => sum + row[key], 0);
  const downloadCountries = ranked(results, "download");
  const unknown = legacy.reduce((sum, row) => sum + row.download, 0);
  if (unknown) downloadCountries.set("pages.dev", unknown);
  return {
    totals: { visits: total("visits"), downloads: total("downloads"), checks: total("checks") },
    daily,
    visitCountries: list(ranked(results, "visit")),
    downloadCountries: list(downloadCountries),
    referrers: list(ranked(results, "referrer")),
  };
}
