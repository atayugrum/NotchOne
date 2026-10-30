// The private dashboard. It holds no data: numbers come from /panel/data with the password.
export const panel = `<!doctype html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>NotchOne Panel</title>
<style>
:root {
  color-scheme: light dark;
  --bg: #f6f6f7; --card: #ffffff; --line: #e4e4e8; --ink: #17171a; --soft: #5c5c66; --bar: #2f6fed;
}
@media (prefers-color-scheme: dark) {
  :root { --bg: #0c0c0f; --card: #17171b; --line: #2a2a31; --ink: #f4f4f6; --soft: #a2a2ad; --bar: #6f9dff; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink); font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
main { max-width: 960px; margin: 0 auto; padding: 32px 16px 56px; }
h1 { font-size: 22px; margin: 0; }
h2 { font-size: 15px; margin: 0 0 12px; }
header { display: flex; justify-content: space-between; align-items: baseline; gap: 12px; margin-bottom: 20px; }
header span, .note { color: var(--soft); font-size: 13px; }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 16px; }
.tiles, .lists, .charts { display: grid; gap: 12px; margin-bottom: 12px; }
.tiles { grid-template-columns: repeat(3, 1fr); }
.charts, .lists { grid-template-columns: repeat(auto-fit, minmax(270px, 1fr)); }
.tile b { display: block; font-size: 30px; line-height: 1.15; font-variant-numeric: tabular-nums; }
.tile span { color: var(--soft); font-size: 13px; }
.chart { position: relative; display: flex; align-items: flex-end; gap: 2px; height: 120px; border-bottom: 1px solid var(--line); }
.chart i { flex: 1; height: 100%; display: flex; align-items: flex-end; cursor: default; }
.chart u { display: block; width: 100%; background: var(--bar); border-radius: 4px 4px 0 0; }
.axis { display: flex; justify-content: space-between; color: var(--soft); font-size: 12px; margin-top: 6px; }
.tip { position: fixed; pointer-events: none; display: none; background: var(--ink); color: var(--bg); font-size: 12px; padding: 4px 8px; border-radius: 6px; }
.row { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 2px 10px; margin-bottom: 9px; }
.row span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.row b { font-variant-numeric: tabular-nums; font-weight: 600; }
.row div { grid-column: 1 / -1; height: 6px; }
.row div u { display: block; height: 100%; background: var(--bar); border-radius: 3px; }
form { max-width: 340px; margin: 18vh auto 0; display: grid; gap: 10px; }
input, button { font: inherit; padding: 11px 12px; border-radius: 10px; border: 1px solid var(--line); background: var(--card); color: var(--ink); }
button { background: var(--bar); color: #fff; border: 0; font-weight: 600; cursor: pointer; }
.error { color: var(--soft); font-size: 13px; min-height: 18px; margin: 0; }
button.link { background: none; color: var(--soft); padding: 0; font-weight: 400; font-size: 13px; }
[hidden] { display: none !important; }
@media (max-width: 520px) { .tile b { font-size: 24px; } }
</style>
</head>
<body>
<main>
  <form id="login">
    <h1>NotchOne Panel</h1>
    <input id="password" type="password" placeholder="Şifre" autocomplete="current-password" autofocus aria-label="Şifre">
    <button type="submit">Giriş</button>
    <p class="error" id="error" role="alert"></p>
  </form>
  <section id="board" hidden>
    <header><h1>NotchOne Panel</h1><span>Son 30 gün · <button class="link" id="logout" type="button">Çıkış</button></span></header>
    <div class="tiles">
      <div class="card tile"><b id="visits">0</b><span>Ziyaret</span></div>
      <div class="card tile"><b id="downloads">0</b><span>İndirme</span></div>
      <div class="card tile"><b id="checks">0</b><span>Güncelleme kontrolü</span></div>
    </div>
    <div class="charts">
      <div class="card"><h2>Günlük ziyaret</h2><div class="chart" id="visitChart"></div><div class="axis"><span id="from"></span><span id="to"></span></div></div>
      <div class="card"><h2>Günlük indirme</h2><div class="chart" id="downloadChart"></div><div class="axis"><span id="from2"></span><span id="to2"></span></div></div>
    </div>
    <div class="lists">
      <div class="card"><h2>Ziyaret: ülkeler</h2><div id="visitCountries"></div></div>
      <div class="card"><h2>İndirme: ülkeler</h2><div id="downloadCountries"></div></div>
      <div class="card"><h2>Nereden geldiler</h2><div id="referrers"></div></div>
    </div>
    <p class="note">Veriler günlük toplamdır; IP adresi ya da kişisel bilgi tutulmaz. Tarayıcı olmayan botlar sayılmaz.</p>
  </section>
  <div class="tip" id="tip"></div>
</main>
<script>
const $ = (id) => document.getElementById(id);
const key = "notchone-panel";
const number = new Intl.NumberFormat("tr-TR");
const regions = new Intl.DisplayNames(["tr"], { type: "region" });
const shortDay = (day) => new Date(day + "T12:00:00Z").toLocaleDateString("tr-TR", { day: "numeric", month: "short" });

const label = (name) => {
  if (name === "direct") return "Doğrudan";
  if (name === "pages.dev") return "pages.dev (ülke bilinmiyor)";
  if (/^[A-Z]{2}$/.test(name) && name !== "XX" && name !== "T1") {
    try { return regions.of(name); } catch { return name; }
  }
  return name === "XX" || name === "T1" ? "Bilinmiyor" : name;
};

function bars(element, daily, field, word) {
  const top = Math.max(1, ...daily.map((row) => row[field]));
  element.replaceChildren(...daily.map((row) => {
    const hit = document.createElement("i");
    const bar = document.createElement("u");
    bar.style.height = row[field] ? Math.max(3, row[field] / top * 100) + "%" : "0";
    hit.append(bar);
    const text = shortDay(row.day) + ": " + number.format(row[field]) + " " + word;
    hit.setAttribute("aria-label", text);
    hit.addEventListener("mousemove", (event) => {
      const tip = $("tip");
      tip.textContent = text;
      tip.style.display = "block";
      tip.style.left = Math.min(event.clientX + 12, innerWidth - 150) + "px";
      tip.style.top = event.clientY - 32 + "px";
    });
    hit.addEventListener("mouseleave", () => { $("tip").style.display = "none"; });
    return hit;
  }));
}

function rows(element, items) {
  if (!items.length) {
    const empty = document.createElement("span");
    empty.className = "note";
    empty.textContent = "Henüz veri yok";
    return element.replaceChildren(empty);
  }
  const top = items[0].n;
  element.replaceChildren(...items.map((item) => {
    const row = document.createElement("div");
    row.className = "row";
    const name = document.createElement("span");
    name.textContent = label(item.name);
    name.title = name.textContent;
    const value = document.createElement("b");
    value.textContent = number.format(item.n);
    const track = document.createElement("div");
    const bar = document.createElement("u");
    bar.style.width = Math.max(2, item.n / top * 100) + "%";
    track.append(bar);
    row.append(name, value, track);
    return row;
  }));
}

function show(data) {
  for (const field of ["visits", "downloads", "checks"]) $(field).textContent = number.format(data.totals[field]);
  bars($("visitChart"), data.daily, "visits", "ziyaret");
  bars($("downloadChart"), data.daily, "downloads", "indirme");
  const first = shortDay(data.daily[0].day), last = shortDay(data.daily.at(-1).day);
  $("from").textContent = $("from2").textContent = first;
  $("to").textContent = $("to2").textContent = last;
  rows($("visitCountries"), data.visitCountries);
  rows($("downloadCountries"), data.downloadCountries);
  rows($("referrers"), data.referrers);
  $("login").hidden = true;
  $("board").hidden = false;
}

async function load(password) {
  const response = await fetch("/panel/data", { method: "POST", headers: { Authorization: "Bearer " + password } });
  if (!response.ok) throw new Error(String(response.status));
  show(await response.json());
}

function remembered() {
  try { return sessionStorage.getItem(key); } catch { return null; }
}

$("login").addEventListener("submit", async (event) => {
  event.preventDefault();
  $("error").textContent = "";
  const password = $("password").value;
  try {
    await load(password);
    try { sessionStorage.setItem(key, password); } catch {}
    $("password").value = "";
  } catch (error) {
    $("error").textContent = error.message === "401" ? "Şifre yanlış" : "Veriler alınamadı";
  }
});

$("logout").addEventListener("click", () => {
  try { sessionStorage.removeItem(key); } catch {}
  location.reload();
});

const saved = remembered();
if (saved) load(saved).catch(() => {});
</script>
</body>
</html>
`;
