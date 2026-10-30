// One window: scrolling through the stage changes what's in it.
(() => {
  const stage = document.querySelector(".stage");
  const windowEl = stage.querySelector(".window");
  const tabs = stage.querySelector(".tabs");
  const bar = stage.querySelector(".progress span");
  const chapters = [...stage.querySelectorAll(".chapter")];
  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");
  stage.style.setProperty("--chapters", chapters.length);

  const images = chapters.map((chapter) => windowEl.appendChild(chapter.querySelector("img")));
  const buttons = chapters.map((chapter, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = chapter.querySelector(".eyebrow").textContent;
    button.addEventListener("click", () => jumpTo(index));
    return tabs.appendChild(button);
  });

  // How far the stage has scrolled while pinned, 0 to 1.
  const travel = () => stage.offsetHeight - innerHeight;
  const progress = () => Math.min(Math.max(-stage.getBoundingClientRect().top / travel(), 0), 1);

  function jumpTo(index) {
    const top = stage.getBoundingClientRect().top + scrollY + travel() * ((index + 0.5) / chapters.length);
    window.glideTo(top);
  }

  let active = -1;
  function show(index) {
    if (index === active) return;
    const forward = index > active;
    active = index;
    windowEl.dataset.direction = forward ? "up" : "down";
    chapters.forEach((chapter, i) => chapter.classList.toggle("is-active", i === index));
    images.forEach((image, i) => image.classList.toggle("is-active", i === index));
    buttons.forEach((button, i) => {
      button.setAttribute("aria-current", i === index);
      if (i === index) {
        tabs.scrollTo({ left: button.offsetLeft - tabs.offsetLeft - 16, behavior: "auto" });
      }
    });
  }

  addEventListener("langchange", () => {
    buttons.forEach((button, index) => { button.textContent = chapters[index].querySelector(".eyebrow").textContent; });
    update();
  });

  let queued = false;
  function update() {
    queued = false;
    const value = progress();
    show(Math.min(Math.floor(value * chapters.length), chapters.length - 1));
    bar.style.transform = `scaleX(${value})`;
    // The window tips up into place as the stage arrives.
    if (!reduceMotion.matches) {
      const arrival = Math.min(Math.max(stage.getBoundingClientRect().top / innerHeight, 0), 1);
      stage.style.setProperty("--arrive", arrival.toFixed(3));
    }
    const box = stage.getBoundingClientRect();
    window.setNotchLabel?.(box.top <= 0 && box.bottom >= innerHeight ? chapters[active].querySelector(".eyebrow").textContent : "");
    stage.style.setProperty("--trail", `${value * 1080}deg`);
  }
  function queue() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(update);
  }
  addEventListener("scroll", queue, { passive: true });
  addEventListener("resize", queue);
  update();

  // Notch or pill, in the same window.
  const shapes = [...stage.querySelectorAll("[data-shape]")];
  images.forEach((image) => {
    image.dataset.notch = image.getAttribute("src");
    new Image().src = image.dataset.pill;
  });
  shapes.forEach((button) => button.addEventListener("click", () => {
    shapes.forEach((other) => other.setAttribute("aria-pressed", other === button));
    images.forEach((image) => { image.src = image.dataset[button.dataset.shape]; });
  }));
})();
