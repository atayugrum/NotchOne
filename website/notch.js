// Moves within the page slowly instead of jumping. Scrolling by hand takes over at any time.
window.glideTo = (top) => {
  const start = scrollY;
  const end = Math.max(0, Math.min(top, document.documentElement.scrollHeight - innerHeight));
  const distance = end - start;
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
    scrollTo(0, end);
    return;
  }
  window.stopGlide?.();
  const duration = Math.min(800 + Math.abs(distance) * 0.25, 1800);
  const began = performance.now();
  let frame;
  const stop = () => {
    cancelAnimationFrame(frame);
    removeEventListener("wheel", stop);
    removeEventListener("touchstart", stop);
    removeEventListener("keydown", stop);
    window.stopGlide = null;
  };
  window.stopGlide = stop;
  addEventListener("wheel", stop, { passive: true });
  addEventListener("touchstart", stop, { passive: true });
  addEventListener("keydown", stop);
  const step = (now) => {
    const t = Math.min((now - began) / duration, 1);
    const eased = t < 0.5 ? 4 * t ** 3 : 1 - (-2 * t + 2) ** 3 / 2;
    scrollTo(0, start + distance * eased);
    if (t < 1) frame = requestAnimationFrame(step);
    else stop();
  };
  frame = requestAnimationFrame(step);
};

// Links to a place on this page glide there; Home does the same when you're already on it.
document.addEventListener("click", (event) => {
  const link = event.target.closest?.("a[href]");
  const page = (path) => path.replace(/index\.html$/, "");
  if (!link || link.hasAttribute("download") || link.origin !== location.origin || page(link.pathname) !== page(location.pathname)) return;
  const target = link.hash ? document.querySelector(link.hash) : document.body;
  if (!target) return;
  event.preventDefault();
  window.glideTo(link.hash ? target.getBoundingClientRect().top + scrollY : 0);
  history.pushState(null, "", link.hash || location.pathname);
});

// The top bar: opens on hover or a click, like the notch in the app.
(() => {
  const notch = document.querySelector(".notch");
  const bar = notch.querySelector(".notch-bar");
  const label = notch.querySelector(".notch-label");
  const canHover = matchMedia("(hover: hover) and (pointer: fine)").matches;

  function setOpen(open) {
    notch.classList.toggle("is-open", open);
    bar.setAttribute("aria-expanded", open);
  }

  // Closed, it shows the feature on screen. The old text stays while it fades out.
  window.setNotchLabel = (text) => {
    if (text) label.textContent = text;
    notch.classList.toggle("has-label", Boolean(text));
  };

  if (canHover) {
    notch.addEventListener("pointerenter", () => setOpen(true));
    notch.addEventListener("pointerleave", () => setOpen(false));
  }
  bar.addEventListener("click", () => {
    if (!canHover) setOpen(!notch.classList.contains("is-open"));
    else if (document.activeElement === bar && !notch.matches(":hover")) setOpen(!notch.classList.contains("is-open"));
  });
  notch.addEventListener("focusout", (event) => {
    if (!notch.contains(event.relatedTarget)) setOpen(false);
  });
  notch.querySelectorAll("a").forEach((link) => link.addEventListener("click", () => setOpen(false)));
  addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    setOpen(false);
    bar.blur();
  });
  addEventListener("pointerdown", (event) => {
    if (!notch.contains(event.target)) setOpen(false);
  });
})();
