// One slow amber gradient behind the whole site. It keeps flowing as you scroll and drifts a
// little with the pointer.
(() => {
  const host = document.querySelector("#bg");
  const P = window.PaperShaders;
  if (!host || !P) return;
  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const speed = 0.55;
  const colors = ["#100803", "#6a2c07", "#d9720f", "#ffb23e", "#2a1206"].map((color) => P.getShaderColorFromString(color));

  let shader;
  try {
    shader = new P.ShaderMount(host, P.meshGradientFragmentShader, {
      u_colors: colors, u_colorsCount: colors.length, u_distortion: 1, u_swirl: 0.55, u_grainMixer: 0.1, u_grainOverlay: 0.08,
      u_fit: P.ShaderFitOptions.cover, u_rotation: 0, u_scale: 1, u_offsetX: 0, u_offsetY: 0, u_originX: 0.5, u_originY: 0.5, u_worldWidth: 0, u_worldHeight: 0,
    }, undefined, reduceMotion ? 0 : speed, 300, 1, 1600 * 1000);
  } catch {
    return; // No WebGL: the CSS gradient behind it stays.
  }
  if (reduceMotion) return;

  let aimX = 0, aimY = 0, x = 0, y = 0, rotation = 0, last = "";
  addEventListener("pointermove", (event) => {
    aimX = (event.clientX / innerWidth - 0.5) * 0.18;
    aimY = (event.clientY / innerHeight - 0.5) * 0.18;
  }, { passive: true });

  function frame() {
    requestAnimationFrame(frame);
    const room = document.documentElement.scrollHeight - innerHeight;
    const aimRotation = room > 0 ? (scrollY / room) * 140 : 0;
    x += (aimX - x) * 0.05;
    y += (aimY - y) * 0.05;
    rotation += (aimRotation - rotation) * 0.06;
    const key = `${x.toFixed(3)},${y.toFixed(3)},${rotation.toFixed(1)}`;
    if (key === last) return;
    last = key;
    shader.setUniforms({ u_offsetX: x, u_offsetY: -y, u_rotation: rotation });
  }
  requestAnimationFrame(frame);
})();
