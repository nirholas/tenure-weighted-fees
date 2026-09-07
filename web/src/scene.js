/**
 * The pool, in three dimensions.
 *
 * A Uniswap v4 pool is a curve with fourteen doors around it, and this draws exactly that: the torus is the pool, the
 * fourteen pillars are the callbacks the protocol offers, and the ones this hook claims stand tall and lit while the
 * rest stay dark and low. Order flow orbits the curve as particles and slows where a lit pillar governs it, which is
 * the picture of a hook pricing a swap on its way through.
 *
 * Drag to orbit. It rotates on its own when left alone, pauses when scrolled out of view, and renders one still frame
 * when the visitor has asked for reduced motion. Without WebGL the page loses the picture and nothing else: every fact
 * it shows is also written in the text beneath it.
 */
import {
  AdditiveBlending, BufferAttribute, BufferGeometry, CanvasTexture, Color, CylinderGeometry, Fog, Group, Mesh,
  MeshBasicMaterial, PerspectiveCamera, Points, PointsMaterial, Scene, SphereGeometry, Sprite, SpriteMaterial,
  TorusGeometry, WebGLRenderer,
} from "three";

/** The fourteen callbacks, grouped so a phase reads as a contiguous arc of the ring. */
const DOORS = [
  ["beforeInitialize", "init"], ["afterInitialize", "init"],
  ["beforeAddLiquidity", "liquidity"], ["afterAddLiquidity", "liquidity"],
  ["afterAddLiquidityReturnsDelta", "liquidity"],
  ["beforeRemoveLiquidity", "liquidity"], ["afterRemoveLiquidity", "liquidity"],
  ["afterRemoveLiquidityReturnsDelta", "liquidity"],
  ["beforeSwap", "swap"], ["afterSwap", "swap"],
  ["beforeSwapReturnsDelta", "swap"], ["afterSwapReturnsDelta", "swap"],
  ["beforeDonate", "donate"], ["afterDonate", "donate"],
];

const PHASE = {init: 0x8ab4ff, liquidity: 0x4ecdc4, swap: 0xff6a2b, donate: 0xb58cff};

const canvas = document.querySelector("canvas[data-permissions]");
if (canvas) mount(canvas, JSON.parse(canvas.dataset.permissions));

function label(text, active) {
  const c = document.createElement("canvas");
  const scale = 3;
  c.width = 340 * scale;
  c.height = 52 * scale;
  const ctx = c.getContext("2d");
  ctx.scale(scale, scale);
  ctx.font = "500 17px ui-monospace, SFMono-Regular, Menlo, monospace";
  ctx.fillStyle = active ? "#e8eaef" : "#4b5563";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(text, 170, 26);
  const sprite = new Sprite(new SpriteMaterial({map: new CanvasTexture(c), transparent: true, depthTest: false}));
  sprite.scale.set(2.5, 0.38, 1);
  return sprite;
}

function mount(canvas, permissions) {
  let renderer;
  try {
    renderer = new WebGLRenderer({canvas, antialias: true, alpha: true, powerPreference: "high-performance"});
  } catch {
    return;
  }

  const fallback = canvas.parentElement?.querySelector(".scene__fallback");
  if (fallback) fallback.classList.add("scene__fallback--quiet");

  const scene = new Scene();
  scene.fog = new Fog(0x07080b, 12, 30);

  const camera = new PerspectiveCamera(42, 1, 0.1, 120);
  const root = new Group();
  scene.add(root);

  const RADIUS = 3.2;

  // The pool: the curve every swap moves along.
  const ring = new Mesh(
    new TorusGeometry(RADIUS, 0.045, 14, 260),
    new MeshBasicMaterial({color: 0x1d6f74, transparent: true, opacity: 0.9}),
  );
  ring.rotation.x = Math.PI / 2;
  root.add(ring);

  const halo = new Mesh(
    new TorusGeometry(RADIUS, 0.24, 12, 200),
    new MeshBasicMaterial({color: 0x1d6f74, transparent: true, opacity: 0.06, blending: AdditiveBlending}),
  );
  halo.rotation.x = Math.PI / 2;
  root.add(halo);

  // A faint floor ring, purely to give the eye a horizon and make the ring read as a solid in space.
  const floor = new Mesh(
    new TorusGeometry(RADIUS * 1.9, 0.006, 6, 160),
    new MeshBasicMaterial({color: 0x1b1f28, transparent: true, opacity: 0.7}),
  );
  floor.rotation.x = Math.PI / 2;
  floor.position.y = -1.5;
  root.add(floor);

  const doors = DOORS.map(([key, phase], index) => {
    const active = permissions[key] === true;
    const angle = (index / DOORS.length) * Math.PI * 2;
    const height = active ? 1.5 : 0.34;
    const colour = new Color(active ? PHASE[phase] : 0x252c38);

    const pillar = new Mesh(
      new CylinderGeometry(active ? 0.075 : 0.05, active ? 0.075 : 0.05, height, 14),
      new MeshBasicMaterial({color: colour, transparent: true, opacity: active ? 0.95 : 0.5}),
    );
    pillar.position.set(Math.cos(angle) * RADIUS, height / 2, Math.sin(angle) * RADIUS);
    root.add(pillar);

    let glow = null;
    if (active) {
      glow = new Mesh(
        new SphereGeometry(0.2, 18, 14),
        new MeshBasicMaterial({color: colour, transparent: true, opacity: 0.25, blending: AdditiveBlending}),
      );
      glow.position.set(pillar.position.x, height, pillar.position.z);
      root.add(glow);
    }

    const text = label(key, active);
    text.position.set(Math.cos(angle) * (RADIUS + 1.55), height + 0.34, Math.sin(angle) * (RADIUS + 1.55));
    root.add(text);

    return {angle, active, pillar, glow, height};
  });

  // Order flow, orbiting the curve. It slows in the arc a claimed callback governs, which is what a hook taxing a
  // swap on its way through actually looks like.
  const COUNT = 1400;
  const positions = new Float32Array(COUNT * 3);
  const phase = new Float32Array(COUNT);
  const lift = new Float32Array(COUNT);
  for (let i = 0; i < COUNT; i++) {
    phase[i] = Math.random() * Math.PI * 2;
    lift[i] = (Math.random() - 0.5) * 0.3;
  }
  const geometry = new BufferGeometry();
  geometry.setAttribute("position", new BufferAttribute(positions, 3));
  const flow = new Points(
    geometry,
    new PointsMaterial({color: 0x7fe9d8, size: 0.05, transparent: true, opacity: 0.8, blending: AdditiveBlending}),
  );
  root.add(flow);

  // Camera, orbited by dragging and drifting on its own otherwise.
  let yaw = 0.6;
  let pitch = 0.52;
  let targetYaw = yaw;
  let targetPitch = pitch;
  let distance = 11.5;
  let dragging = false;
  let lastPointer = null;
  let idleSince = performance.now();

  canvas.style.touchAction = "pan-y";
  canvas.addEventListener("pointerdown", (event) => {
    dragging = true;
    lastPointer = {x: event.clientX, y: event.clientY};
    canvas.setPointerCapture(event.pointerId);
    canvas.style.cursor = "grabbing";
  });
  canvas.addEventListener("pointermove", (event) => {
    if (!dragging || !lastPointer) return;
    targetYaw -= (event.clientX - lastPointer.x) * 0.006;
    targetPitch = Math.max(0.12, Math.min(1.3, targetPitch + (event.clientY - lastPointer.y) * 0.004));
    lastPointer = {x: event.clientX, y: event.clientY};
    idleSince = performance.now();
  });
  const release = (event) => {
    dragging = false;
    lastPointer = null;
    canvas.style.cursor = "grab";
    idleSince = performance.now();
    if (event?.pointerId !== undefined && canvas.hasPointerCapture(event.pointerId)) {
      canvas.releasePointerCapture(event.pointerId);
    }
  };
  canvas.addEventListener("pointerup", release);
  canvas.addEventListener("pointercancel", release);
  canvas.style.cursor = "grab";

  function resize() {
    const {clientWidth, clientHeight} = canvas;
    if (clientWidth === 0 || clientHeight === 0) return;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(clientWidth, clientHeight, false);
    camera.aspect = clientWidth / clientHeight;
    // Pull back on narrow screens so the ring and its labels still fit.
    distance = clientWidth < 720 ? 15.5 : 11.5;
    camera.updateProjectionMatrix();
  }

  const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
  let elapsed = 0;
  let last = performance.now();
  let visible = true;

  function step(delta, now) {
    elapsed += delta;

    // Drift back into motion once the visitor has stopped dragging.
    if (!dragging && now - idleSince > 2500) targetYaw += delta * 0.12;
    yaw += (targetYaw - yaw) * 0.08;
    pitch += (targetPitch - pitch) * 0.08;

    camera.position.set(
      Math.sin(yaw) * Math.cos(pitch) * distance,
      Math.sin(pitch) * distance,
      Math.cos(yaw) * Math.cos(pitch) * distance,
    );
    camera.lookAt(0, 0.4, 0);

    for (const door of doors) {
      if (!door.active) continue;
      const pulse = 0.5 + 0.5 * Math.sin(elapsed * 1.6 + door.angle * 2.4);
      door.pillar.scale.y = 1 + pulse * 0.06;
      if (door.glow) {
        door.glow.material.opacity = 0.16 + pulse * 0.24;
        door.glow.scale.setScalar(1 + pulse * 0.22);
      }
    }

    for (let i = 0; i < COUNT; i++) {
      let drag = 0;
      for (const door of doors) {
        if (!door.active) continue;
        const gap = Math.abs(((phase[i] - door.angle + Math.PI * 3) % (Math.PI * 2)) - Math.PI);
        if (gap > Math.PI - 0.5) drag += 1;
      }
      phase[i] += delta * 0.34 / (1 + drag * 2.2);
      const r = RADIUS + Math.sin(phase[i] * 4 + i) * 0.06;
      positions[i * 3] = Math.cos(phase[i]) * r;
      positions[i * 3 + 1] = lift[i] + Math.sin(elapsed * 0.7 + i) * 0.03;
      positions[i * 3 + 2] = Math.sin(phase[i]) * r;
    }
    flow.geometry.attributes.position.needsUpdate = true;
  }

  resize();
  if (reduced) {
    step(0, performance.now());
    renderer.render(scene, camera);
  } else {
    const frame = (now) => {
      requestAnimationFrame(frame);
      const delta = Math.min((now - last) / 1000, 0.05);
      last = now;
      if (!visible) return;
      step(delta, now);
      renderer.render(scene, camera);
    };
    requestAnimationFrame(frame);
  }

  window.addEventListener("resize", resize, {passive: true});
  new IntersectionObserver((entries) => {
    visible = entries.some((entry) => entry.isIntersecting);
  }).observe(canvas);
}

// Copy buttons, for the addresses and commands this page exists to hand people.
document.addEventListener("click", async (event) => {
  const button = event.target.closest(".copy");
  if (!button || !navigator.clipboard) return;
  const value = button.dataset.copy ?? button.previousElementSibling?.textContent ?? "";
  await navigator.clipboard.writeText(value);
  const previous = button.textContent;
  button.textContent = "copied";
  setTimeout(() => { button.textContent = previous; }, 1400);
});
