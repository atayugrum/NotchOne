// Touches around the page. All optional: the page reads the same without them.
(() => {
  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const finePointer = matchMedia("(hover: hover) and (pointer: fine)").matches;

  // Headlines arrive word by word; they're split again when the language changes.
  function splitWords(heading) {
    let index = 0;
    [...heading.childNodes].forEach((node) => {
      if (node.nodeType !== Node.TEXT_NODE || !node.textContent.trim()) return;
      const parts = node.textContent.trim().split(/\s+/).flatMap((text) => {
        const word = document.createElement("span");
        word.className = "word";
        word.textContent = text;
        word.style.setProperty("--i", index++);
        return [word, " "];
      });
      node.replaceWith(...parts);
    });
  }
  const split = () => document.querySelectorAll("[data-words]").forEach(splitWords);
  split();

  // The marquee, moving faster as you scroll.
  const marquee = document.querySelector("[data-marquee]");
  function fillMarquee() {
    const items = window.t("marquee").split(",").map((text) => `<span>${text}</span>`).join("");
    marquee.innerHTML = items + items;
  }
  fillMarquee();
  let offset = 0, lastScroll = scrollY, boost = 0;
  function runMarquee() {
    boost *= 0.92;
    offset -= 0.6 + boost;
    const half = marquee.scrollWidth / 2;
    if (half && -offset > half) offset += half;
    marquee.style.transform = `translateX(${offset}px)`;
    requestAnimationFrame(runMarquee);
  }
  if (!reduceMotion) {
    addEventListener("scroll", () => {
      boost = Math.min(boost + Math.abs(scrollY - lastScroll) * 0.04, 14);
      lastScroll = scrollY;
    }, { passive: true });
    requestAnimationFrame(runMarquee);
  }

  // A line along the top shows how far down the page you are.
  const line = document.querySelector(".scroll-line");
  const setLine = () => {
    const room = document.documentElement.scrollHeight - innerHeight;
    line.style.transform = `scaleX(${room > 0 ? scrollY / room : 0})`;
  };
  setLine();
  addEventListener("scroll", setLine, { passive: true });

  // Text typed into the Search tile.
  const typed = document.querySelector("[data-typed]");
  let typing;
  function typeLoop() {
    clearTimeout(typing);
    const text = window.t(typed.dataset.typed);
    if (reduceMotion) { typed.textContent = text; return; }
    let count = 0;
    const tick = () => {
      typed.textContent = text.slice(0, count);
      count = count > text.length + 8 ? 0 : count + 1;
      typing = setTimeout(tick, count > text.length ? 160 : 110);
    };
    tick();
  }
  typeLoop();

  // Sections fade up when they arrive; tiles start their animations only then.
  const seen = new IntersectionObserver((entries) => {
    entries.filter((entry) => entry.isIntersecting).forEach((entry) => {
      entry.target.classList.add("is-in");
      seen.unobserve(entry.target);
    });
  }, { rootMargin: "0px 0px -8% 0px" });
  document.querySelectorAll(".big, .tile, .closing > p, .closing > .hero-actions, .closing footer").forEach((target, index) => {
    target.classList.add("reveal");
    target.style.setProperty("--delay", `${(index % 3) * 70}ms`);
    seen.observe(target);
  });

  addEventListener("langchange", () => {
    split();
    fillMarquee();
    typeLoop();
  });

  if (finePointer && !reduceMotion) {
    // A glow follows the pointer around the page.
    const glow = document.querySelector(".pointer-glow");
    let glowX = innerWidth / 2, glowY = innerHeight / 3, aimX = glowX, aimY = glowY;
    addEventListener("pointermove", (event) => { aimX = event.clientX; aimY = event.clientY; }, { passive: true });
    const followPointer = () => {
      glowX += (aimX - glowX) * 0.08;
      glowY += (aimY - glowY) * 0.08;
      glow.style.transform = `translate(${glowX}px, ${glowY}px)`;
      requestAnimationFrame(followPointer);
    };
    requestAnimationFrame(followPointer);

    // Tiles and the window tilt under the pointer, and a light follows it.
    document.querySelectorAll(".tile, .window").forEach((tile) => {
      const strength = tile.classList.contains("window") ? 3 : 7;
      tile.addEventListener("pointermove", (event) => {
        const box = tile.getBoundingClientRect();
        const x = (event.clientX - box.left) / box.width;
        const y = (event.clientY - box.top) / box.height;
        tile.style.setProperty("--x", `${x * 100}%`);
        tile.style.setProperty("--y", `${y * 100}%`);
        tile.style.setProperty("--tilt-x", `${(0.5 - y) * strength}deg`);
        tile.style.setProperty("--tilt-y", `${(x - 0.5) * strength}deg`);
      });
      tile.addEventListener("pointerleave", () => {
        tile.style.setProperty("--tilt-x", "0deg");
        tile.style.setProperty("--tilt-y", "0deg");
      });
    });
  }
})();
