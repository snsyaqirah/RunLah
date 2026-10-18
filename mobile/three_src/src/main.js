// RunLah 3D race scenes: replay, drone view at the finish, course flyover.
// One renderer, three camera rigs. Driven by Flutter through bridge.js.
import { Color, InstancedMesh, Matrix4, PerspectiveCamera, PlaneGeometry, Scene, WebGLRenderer } from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { listen, post } from './bridge.js';
import { Trees, buildCity } from './city.js';
import { Course } from './course.js';
import { Environment, U } from './env.js';
import { FinishArea, figureGeometry } from './finish.js';
import { Labels } from './labels.js';
import { buildLandmarks } from './landmarks.js';
import { dotMaterial } from './materials.js';
import { Route } from './route.js';
import { Rigs } from './rigs.js';
import { Runners } from './runners.js';
import { clamp, rng, smoothstep } from './util.js';

const STR = {
  start: 'START',
  finish: 'FINISH',
  km: 'KM',
  you: 'You',
  event: '',
  noWebgl: '3D needs WebGL 2, which this device does not support.',
  lost: 'The 3D view was paused by the system. Reopen it to continue.',
};

const S = {
  data: null,
  mode: 'replay',
  t: 0,
  flyT: 0,
  flyDur: 52,
  playing: false,
  speed: 60,
  range: [0, 16200],
  followId: null,
  lastEmit: 0,
};

const stage = document.getElementById('stage');
const msgEl = document.getElementById('msg');
const cardEl = document.getElementById('card');

function showMessage(text) {
  msgEl.textContent = text;
  msgEl.classList.remove('hidden');
}

function hasWebGL2() {
  try {
    const c = document.createElement('canvas');
    return !!(window.WebGL2RenderingContext && c.getContext('webgl2'));
  } catch (e) {
    return false;
  }
}

let renderer = null;
let scene = null;
let camera = null;
let controls = null;
let env = null;
let W = null; // world, built on the first init

function setupRenderer() {
  if (!hasWebGL2()) return false;
  try {
    renderer = new WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
  } catch (e) {
    return false;
  }
  renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.setClearColor('#0b1220');
  stage.appendChild(renderer.domElement);
  renderer.domElement.addEventListener('webglcontextlost', (e) => {
    e.preventDefault();
    showMessage(STR.lost);
  });
  scene = new Scene();
  camera = new PerspectiveCamera(50, window.innerWidth / window.innerHeight, 4, 70000);
  camera.position.set(-5000, 4000, 3000);
  controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.09;
  controls.rotateSpeed = 0.6;
  controls.zoomSpeed = 0.9;
  env = new Environment(scene);
  env.setTimeOfDay(17100, 25800);
  return true;
}

function build(data) {
  const route = new Route(data.route, data.distance);
  const b = route.bounds();
  env.setCentre(b.cx, b.cz);
  const landmarks = buildLandmarks(scene, data, route);
  const trees = new Trees(scene, 2600);
  const city = buildCity(scene, data, route, landmarks, trees);
  const course = new Course(scene, data, route, STR);
  const figGeo = figureGeometry();
  const finish = new FinishArea(scene, route, STR, figGeo);
  const rand = rng(7);
  for (const [x, z] of finish.treeSpots) {
    if (city.hash.clearance(x, z) > 12) trees.add(x, z, 7 + rand() * 3, rand);
  }
  trees.done();
  const runners = new Runners(scene, data, route, figGeo);
  const labels = new Labels(document.getElementById('labels'));

  // Landmark names: the skyline always, smaller places only when the camera is near.
  const lmLabels = [];
  for (const l of landmarks) {
    const item = labels.add(l.name, 'lbl-lm');
    item.pos.set(l.x, l.top + 35, l.z);
    const big = l.kind === 'twin' || l.kind === 'tower';
    lmLabels.push({ item, far: big ? 1e9 : 3200 });
  }
  for (const p of data.landmarks || []) {
    if (p.kind !== 'park') continue;
    const item = labels.add(p.name, 'lbl-lm');
    item.pos.set(p.x, 40, -p.y);
    lmLabels.push({ item, far: 2600 });
  }

  const cpLabels = course.cps.map((c) => {
    const it = labels.add(c.label, c.end ? 'lbl-cp end' : 'lbl-cp');
    it.pos.set(c.x, c.h + 8, c.z);
    return it;
  });

  const kmLabels = [];
  const tmp = {};
  for (let k = 1; k * 1000 < data.distance; k++) {
    const it = labels.add(`${STR.km} ${k}`, 'lbl-km');
    route.at(k * 1000, tmp);
    it.pos.set(tmp.x, 28, tmp.z);
    kmLabels.push({ d: k * 1000, item: it });
  }

  const runnerLabels = runners.special.map((r) => {
    const text = (data.labels && data.labels[String(r.id)]) || (r.cls === 'you' ? STR.you : `#${r.id}`);
    const cls = r.cls === 'you' ? 'lbl-you' : r.cls === 'friend' ? 'lbl-friend' : 'lbl-focus';
    return { r, item: labels.add(text, cls) };
  });

  // Blinking red aviation lights on the skyline.
  const tops = [];
  for (const l of landmarks) {
    if (l.kind === 'twin') for (const s of [-1, 1]) tops.push([l.x + s * 47, l.top + 2, l.z]);
    else if (l.kind === 'tower') tops.push([l.x, l.top + 2, l.z]);
  }
  const beacons = new InstancedMesh(new PlaneGeometry(1, 1), dotMaterial({ worldSize: 14, minPx: 4, maxPx: 16 }), Math.max(1, tops.length));
  const m4 = new Matrix4();
  tops.forEach(([x, y, z], i) => {
    beacons.setMatrixAt(i, m4.makeTranslation(x, y, z));
    beacons.setColorAt(i, new Color('#ff2a1a'));
  });
  beacons.count = tops.length;
  beacons.frustumCulled = false;
  scene.add(beacons);

  const rigs = new Rigs(camera, controls, route, finish, landmarks);
  W = { route, landmarks, city, course, finish, runners, labels, lmLabels, cpLabels, kmLabels, runnerLabels, rigs, beacons };
}

function rangeFor(mode) {
  const d = S.data;
  if (mode === 'drone') return d.window || [d.finishT - 60, d.finishT + 60];
  if (mode === 'flyover') return [0, S.flyDur];
  return [0, d.cutoff || 16200];
}

function setMode(mode) {
  if (!['replay', 'drone', 'flyover'].includes(mode)) return;
  S.mode = mode;
  S.range = rangeFor(mode);
  if (mode === 'drone' && (S.t < S.range[0] || S.t > S.range[1])) S.t = S.range[0];
  if (mode !== 'flyover') S.t = clamp(S.t, S.range[0], S.range[1]);
  W.course.setMode(mode);
  W.rigs.followId = mode === 'replay' ? S.followId : null;
  W.rigs.enter(mode);
  cardEl.classList.add('hidden');
  emitTime(true);
}

function seek(t) {
  if (S.mode === 'flyover') S.flyT = clamp(t, 0, S.flyDur);
  else S.t = clamp(t, S.range[0], S.range[1]);
  emitTime(true);
}

function emitTime(force) {
  const now = performance.now();
  if (!force && now - S.lastEmit < 250) return;
  S.lastEmit = now;
  const flyover = S.mode === 'flyover';
  post({
    type: 'time',
    t: Math.round((flyover ? S.flyT : S.t) * 10) / 10,
    playing: S.playing,
    mode: S.mode,
    d: flyover ? Math.round(S.flyD || 0) : undefined,
  });
}

function applyInsets(ins) {
  if (!W || !ins) return;
  W.rigs.insets = { top: ins.top || 0, bottom: ins.bottom || 0 };
  cardEl.style.top = `${(ins.top || 0) + 14}px`;
  onResize();
}

function onInit(d) {
  Object.assign(STR, d.strings || {});
  if (!renderer) {
    showMessage(STR.noWebgl);
    return;
  }
  const first = !W;
  S.data = d;
  S.flyDur = d.flyDuration || 52;
  if (first) build(d);
  S.followId = d.followId ?? null;
  S.speed = d.speed || (d.mode === 'drone' ? 2 : d.mode === 'flyover' ? 1 : 60);
  S.mode = d.mode || 'replay';
  S.range = rangeFor(S.mode);
  if (S.mode === 'flyover') S.flyT = clamp(d.t0 || 0, 0, S.flyDur);
  else S.t = clamp(d.t0 ?? S.range[0], S.range[0], S.range[1]);
  if (d.insets) W.rigs.insets = { top: d.insets.top || 0, bottom: d.insets.bottom || 0 };
  cardEl.style.top = `${((d.insets && d.insets.top) || 0) + 14}px`;
  onResize();
  setMode(S.mode);
  if (S.followId != null) W.rigs.setFollow(S.followId);
  S.playing = d.playing !== false;
  inited = true;
  emitTime(true);
}

function onCommand(m) {
  if (m.type === 'init') return onInit(m.data || {});
  if (!W) return;
  switch (m.type) {
    case 'play':
      if (S.mode === 'replay' && S.t >= S.range[1] - 0.5) S.t = S.range[0];
      S.playing = true;
      break;
    case 'pause':
      S.playing = false;
      break;
    case 'seek':
      seek(Number(m.t) || 0);
      return;
    case 'speed':
      S.speed = clamp(Number(m.x) || 1, 0.1, 2000);
      break;
    case 'follow':
      S.followId = m.id ?? null;
      if (S.mode === 'replay') W.rigs.setFollow(S.followId);
      break;
    case 'mode':
      setMode(m.mode);
      if (m.t != null) seek(Number(m.t));
      if (m.speed != null) S.speed = Number(m.speed);
      break;
    case 'insets':
      applyInsets(m);
      break;
    default:
      break;
  }
  emitTime(true);
}

function onResize() {
  if (!renderer) return;
  const w = window.innerWidth;
  const h = window.innerHeight;
  renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
  renderer.setSize(w, h);
  U.uViewport.value.set(w * renderer.getPixelRatio(), h * renderer.getPixelRatio());
  U.uDpr.value = renderer.getPixelRatio();
  if (W) W.rigs.resize(w, h);
  else {
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }
}

// Tap (not drag) on a runner -> pick event.
function setupPicking() {
  const el = renderer.domElement;
  let down = null;
  let pointers = 0;
  el.addEventListener('pointerdown', (e) => {
    pointers++;
    down = pointers === 1 ? { x: e.clientX, y: e.clientY, t: performance.now() } : null;
  });
  const end = (e) => {
    pointers = Math.max(0, pointers - 1);
    if (!down || !W || S.mode === 'flyover') return;
    const moved = Math.hypot(e.clientX - down.x, e.clientY - down.y);
    const quick = performance.now() - down.t < 400;
    down = null;
    if (moved > 9 || !quick) return;
    const r = W.runners.pick(camera, e.clientX, e.clientY, window.innerWidth, window.innerHeight, S.mode);
    W.runners.pickedId = r ? r.id : null;
    post({ type: 'pick', id: r ? r.id : null });
  };
  el.addEventListener('pointerup', end);
  el.addEventListener('pointercancel', () => {
    pointers = Math.max(0, pointers - 1);
    down = null;
  });
}

let last = performance.now();
let inited = false;

function frame(now) {
  requestAnimationFrame(frame);
  const dt = Math.min(0.1, Math.max(0, (now - last) / 1000));
  last = now;
  tick(dt, true);
}

function tick(dt, draw) {
  U.uTime.value += dt;
  if (!renderer) return;
  if (!W || !S.data) {
    env.update(camera);
    renderer.render(scene, camera);
    return;
  }
  const d = S.data;

  if (S.playing) {
    if (S.mode === 'flyover') {
      S.flyT += dt;
      if (S.flyT > S.flyDur + 2) S.flyT = 0;
    } else {
      S.t += dt * S.speed;
      if (S.mode === 'drone' && S.t > S.range[1]) S.t = S.range[0];
      if (S.mode === 'replay' && S.t >= S.range[1]) {
        S.t = S.range[1];
        S.playing = false;
        emitTime(true);
      }
    }
  }

  const t = S.t;
  const sod = S.mode === 'flyover' ? d.sunriseSod - 1450 : d.gunSod + t;
  env.setTimeOfDay(sod, d.sunriseSod);

  const { runners, rigs, course, finish } = W;
  runners.update(t, S.mode);
  const focus = runners.get(d.focusId ?? d.youId);
  course.setProgress(S.mode === 'replay' && focus && focus.state > 0 ? Math.min(focus.d, d.distance) : -1);
  finish.update(U.uTime.value, U.uNight.value, S.mode === 'drone');
  W.beacons.visible = S.mode !== 'drone' && Math.sin(U.uTime.value * 4.2) > -0.2;
  if (S.mode === 'drone') finish.setClock(t);

  const followed = S.followId != null ? runners.get(S.followId) : null;
  const flyD = rigs.update(dt, followed, S.flyT, S.flyDur);
  // Route glow: a broad band from far away, a crisp line up close.
  if (S.mode !== 'drone') {
    const camDist = S.mode === 'flyover' ? camera.position.y * 4 : camera.position.distanceTo(controls.target);
    course.glowMat.uniforms.uHalf.value = clamp(camDist * 0.0042, 4.5, 30);
  }
  S.flyD = flyD;
  updateLabels(flyD);

  env.update(camera);
  if (!draw) return;
  let drift = null;
  if (S.mode === 'drone') {
    drift = rigs.droneDrift(U.uTime.value).clone();
    camera.position.add(drift);
  }
  renderer.render(scene, camera);
  if (drift) camera.position.sub(drift);
  W.labels.update(camera, window.innerWidth, window.innerHeight);
  emitTime(false);
}

function updateLabels(flyD) {
  const mode = S.mode;
  const replay = mode === 'replay';
  const fly = mode === 'flyover';
  for (const { item, far } of W.lmLabels) {
    const dist = camera.position.distanceTo(item.pos);
    item.visible = (replay || fly) && dist < far;
    item.opacity = far > 1e8 ? 1 : 1 - smoothstep(far * 0.7, far, dist);
  }
  W.cpLabels.forEach((it) => (it.visible = replay || fly));
  for (const { r, item } of W.runnerLabels) {
    if (mode === 'drone') {
      item.visible = r.alpha > 0.05 && r.d > S.data.distance - 480 && r.d < S.data.distance + 70;
      item.pos.set(r.x, 2.15, r.z);
    } else {
      item.visible = replay && r.alpha > 0.05;
      item.pos.set(r.x, r.y + 4, r.z);
    }
    item.opacity = Math.min(1, r.alpha * 1.5);
  }
  // Flyover: km markers pop up ahead, checkpoint names in a card.
  for (const { d, item } of W.kmLabels) {
    const ahead = fly && flyD != null ? d - flyD : -1;
    item.visible = fly && ahead > -150 && ahead < 2600;
    item.opacity = smoothstep(-150, 120, ahead) * (1 - smoothstep(1900, 2600, ahead));
  }
  if (fly && flyD != null) {
    let show = null;
    for (const c of W.course.checkpoints) {
      if (flyD > c.d - 350 && flyD < c.d + 650) show = c;
    }
    if (show) {
      const label = show.type === 'start' ? STR.start : show.type === 'finish' ? STR.finish : show.label;
      const html = `<b></b><div></div>`;
      if (cardEl.dataset.key !== `${show.d}`) {
        cardEl.innerHTML = html;
        cardEl.firstChild.textContent = label;
        cardEl.lastChild.textContent = show.name;
        cardEl.dataset.key = `${show.d}`;
      }
      cardEl.classList.remove('hidden');
    } else {
      cardEl.classList.add('hidden');
    }
  } else if (!cardEl.classList.contains('hidden')) {
    cardEl.classList.add('hidden');
  }
}

// Read-only handles for debugging in a browser console / preview pages.
window.__runlah = {
  state: S,
  get camera() {
    return camera;
  },
  get controls() {
    return controls;
  },
  get world() {
    return W;
  },
  /** Runs n frames of dt seconds synchronously (deterministic previews). */
  step(n, dt = 0.1) {
    for (let i = 0; i < n; i++) tick(dt, i === n - 1);
  },
};

// ------------------------------------------------------------------ boot

listen(onCommand);
const ok = setupRenderer();
if (!ok) {
  showMessage(STR.noWebgl);
  post({ type: 'error', reason: 'webgl' });
} else {
  onResize();
  window.addEventListener('resize', onResize);
  setupPicking();
  requestAnimationFrame(frame);
}
post({ type: 'ready', webgl: ok });
// Hosts can miss the very first message while the page is attaching; repeat until init.
let readyTries = 0;
const readyTimer = setInterval(() => {
  if (inited || ++readyTries > 15) {
    clearInterval(readyTimer);
    return;
  }
  post({ type: 'ready', webgl: ok });
}, 1000);
