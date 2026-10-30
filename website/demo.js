// The MacBook in the hero. The notch has the app's real sizes, and opens onto real screenshots.
(() => {
  const mac = document.querySelector("#demo");
  const notch = mac?.querySelector(".dn");
  if (!notch) return;
  const buttons = [...document.querySelectorAll("[data-demo]")];
  const shots = [...notch.querySelectorAll(".dn-shots img")];
  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const reel = ["music", "volume", "open:home", "music", "note", "open:nowplaying", "focus", "open:system", "charge", "open:weather"];
  const closedRest = "music";
  let step = 0, timer, hovering = false, touched = false, resting = closedRest;

  const fit = () => mac.style.setProperty("--s", mac.querySelector(".mac-screen").clientWidth / 1470);
  fit();
  new ResizeObserver(fit).observe(mac);

  function setState(state) {
    const [kind, page] = state.split(":");
    notch.dataset.state = kind;
    notch.classList.toggle("is-open", kind === "open");
    if (page) {
      const shot = shots.find((image) => image.dataset.open === page);
      notch.style.setProperty("--h", `${shot.dataset.height}px`);
      shots.forEach((image) => image.classList.toggle("is-on", image === shot));
    } else {
      notch.style.removeProperty("--h");
    }
    buttons.forEach((button) => button.classList.toggle("is-on", button.dataset.demo === state));
  }

  function play() {
    clearTimeout(timer);
    if (hovering || touched || reduceMotion) return;
    setState(reel[step]);
    const hold = reel[step].startsWith("open") ? 3400 : 2200;
    step = (step + 1) % reel.length;
    timer = setTimeout(play, hold);
  }

  buttons.forEach((button) => button.addEventListener("click", () => {
    touched = true;
    clearTimeout(timer);
    const state = button.dataset.demo;
    if (state === "volume") notch.style.setProperty("--level", `${30 + Math.round(Math.random() * 65)}%`);
    setState(state);
    if (state.startsWith("open")) resting = state;
    else if (state === "focus") resting = state;
    else timer = setTimeout(() => setState(resting = closedRest), 2200);
  }));

  notch.addEventListener("pointerenter", () => {
    hovering = true;
    clearTimeout(timer);
    if (notch.dataset.state !== "open") setState("open:home");
  });
  notch.addEventListener("pointerleave", () => {
    hovering = false;
    if (touched) setState(resting.startsWith("open") ? closedRest : resting);
    else play();
  });

  // The Mac's menu bar shows the real date and time, in the page's language.
  const date = mac.querySelector(".mac-date");
  const time = mac.querySelector(".mac-time");
  function tick() {
    const now = new Date();
    const lang = document.documentElement.lang;
    const part = (options) => now.toLocaleDateString(lang, options);
    const day = part({ day: "numeric", month: "short" });
    const weekday = part({ weekday: "short" });
    date.textContent = lang === "tr" ? `${day} ${weekday}` : `${weekday} ${day}`;
    time.textContent = now.toLocaleTimeString(lang, { hour: "2-digit", minute: "2-digit", hour12: false });
  }
  tick();
  setTimeout(() => {
    tick();
    setInterval(tick, 60000);
  }, 60000 - Date.now() % 60000);
  addEventListener("langchange", tick);

  // The site's own notch steps aside while the Mac's notch is under it.
  const siteNotch = document.querySelector(".notch");
  const tuck = () => {
    const box = mac.getBoundingClientRect();
    siteNotch.classList.toggle("is-tucked", box.top < 90 && box.bottom > 90);
  };
  tuck();
  addEventListener("scroll", tuck, { passive: true });
  addEventListener("resize", tuck);

  if (reduceMotion) setState("open:home");
  else new IntersectionObserver(([entry]) => {
    if (entry.isIntersecting) play();
    else clearTimeout(timer);
  }).observe(notch);
})();
