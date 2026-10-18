// Every runner in the payload: kinematics identical to RaceSim.distanceAt,
// drawn as glowing instanced dots (replay) or little figures (drone view).
import { Color, Euler, InstancedMesh, Matrix4, PlaneGeometry, Quaternion, Vector3 } from 'three';
import { blobMaterial, dotMaterial, figureMaterial } from './materials.js';
import { hash01, segment } from './util.js';

export const COLORS = {
  M: '#4d8dff',
  F: '#2fd27e',
  cat: '#ffab1f',
  friend: '#ff5ca8',
  you: '#ffc83d',
  picked: '#ffffff',
};

const STATE_CORRAL = 0;
const STATE_RUN = 1;
const STATE_DONE = 2;
const STATE_DNF = 3;

export class Runners {
  constructor(scene, data, route, figGeo) {
    this.route = route;
    this.distance = data.distance;
    const defMarks = Float64Array.from(data.marks);
    const youId = data.youId;
    const focusId = data.focusId ?? youId;
    this.list = (data.runners || []).map((r, i) => {
      const marks = r.marks ? Float64Array.from(r.marks) : defMarks;
      const cum = Float64Array.from(r.cum);
      const n = cum.length;
      const lastV = (marks[n - 1] - marks[n - 2]) / Math.max(1, cum[n - 1] - cum[n - 2]);
      let dnfNet = null;
      if (r.dnf != null) {
        const k = segment(marks, Math.min(r.dnf, marks[n - 1]));
        const f = (r.dnf - marks[k]) / (marks[k + 1] - marks[k] || 1);
        dnfNet = cum[k] + (cum[k + 1] - cum[k]) * f;
      }
      const cls = r.id === youId ? 'you' : r.cls;
      return {
        i,
        id: r.id,
        s: r.startDelay,
        marks,
        cum,
        net: cum[n - 1],
        lastV,
        dnf: r.dnf ?? null,
        dnfNet,
        g: r.g,
        cls,
        focus: r.id === focusId,
        lane: hash01(r.id) * 2 - 1,
        phase: hash01(r.id * 7 + 3) * 6.283,
        color: new Color(cls === 'field' ? COLORS[r.g] || COLORS.M : COLORS[cls] || COLORS.M),
        size: cls === 'you' ? 2.1 : cls === 'friend' ? 1.6 : cls === 'cat' ? 1.05 : 1,
        // per-frame
        d: 0,
        state: STATE_CORRAL,
        alpha: 0,
        x: 0,
        y: 0,
        z: 0,
        tx: 1,
        tz: 0,
      };
    });
    this.byId = new Map(this.list.map((r) => [r.id, r]));
    const N = this.list.length;

    this.dots = new InstancedMesh(new PlaneGeometry(1, 1), dotMaterial({ worldSize: 7, minPx: 2.3, maxPx: 9 }), Math.max(1, N));
    this.dots.frustumCulled = false;
    this.dots.renderOrder = 5;
    this.list.forEach((r, i) => this.dots.setColorAt(i, r.color));
    scene.add(this.dots);

    // Pulsing rings on you / friends / the picked runner.
    this.rings = new InstancedMesh(new PlaneGeometry(1, 1), dotMaterial({ worldSize: 70, minPx: 24, maxPx: 46, ring: true }), 8);
    this.rings.frustumCulled = false;
    this.rings.renderOrder = 6;
    this.rings.count = 0;
    scene.add(this.rings);

    // Drone-view figures + contact shadows (only runners near the finish).
    this.figures = new InstancedMesh(figGeo, figureMaterial(), Math.max(1, N));
    this.figures.frustumCulled = false;
    this.figures.count = 0;
    this.figures.setColorAt(0, new Color());
    scene.add(this.figures);
    const blobGeo = new PlaneGeometry(1.3, 1.3);
    blobGeo.rotateX(-Math.PI / 2);
    this.blobs = new InstancedMesh(blobGeo, blobMaterial(), Math.max(1, N));
    this.blobs.frustumCulled = false;
    this.blobs.count = 0;
    scene.add(this.blobs);
    this.figureIds = new Int32Array(Math.max(1, N));

    this.special = this.list.filter((r) => r.cls === 'you' || r.cls === 'friend' || r.focus);
    this.pickedId = null;
    this._m = new Matrix4();
    this._q = new Quaternion();
    this._s = new Vector3();
    this._p = new Vector3();
    this._e = new Vector3();
    this._c = new Color();
    this._tmp = {};
  }

  /** Race distance at race time t, exactly like RaceSim.distanceAt, plus corral/finish extras. */
  kin(r, t) {
    const e = t - r.s;
    if (e <= 0) {
      r.state = STATE_CORRAL;
      // Shuffle toward the start line at walking pace before crossing it.
      r.d = Math.max(-1250, e * 1.25);
      r.since = 0;
      return;
    }
    const cum = r.cum;
    const marks = r.marks;
    if (r.dnf != null && r.dnfNet != null && e >= r.dnfNet) {
      r.state = STATE_DNF;
      r.d = r.dnf;
      r.since = e - r.dnfNet;
      return;
    }
    if (e >= r.net) {
      r.state = STATE_DONE;
      const s = e - r.net;
      r.since = s;
      // Glide to a stop past the line, then walk out of the chute.
      r.d = this.distance + r.lastV * 5 * (1 - Math.exp(-s / 5)) + 1.0 * Math.max(0, s - 6);
      return;
    }
    const k = segment(cum, e);
    const f = (e - cum[k]) / (cum[k + 1] - cum[k] || 1);
    r.d = marks[k] + (marks[k + 1] - marks[k]) * f;
    r.state = STATE_RUN;
    r.since = 0;
  }

  /**
   * Moves everyone to race time t.
   * mode 'replay' draws dots; 'drone' draws figures near the finish.
   */
  update(t, mode, clock) {
    const route = this.route;
    const tmp = this._tmp;
    const drone = mode === 'drone';
    const show = mode !== 'flyover';
    const half = drone ? 5.6 : 6.5;
    const mArr = this.dots.instanceMatrix.array;
    const cArr = this.dots.instanceColor.array;
    const m = this._m;
    const q = this._q;
    const s = this._s;
    const p = this._p;
    const e = this._e;
    let fig = 0;
    const figMin = this.distance - 480;
    const figMax = this.distance + 70;

    for (const r of this.list) {
      this.kin(r, t);
      let alpha = 1;
      if (r.state === STATE_CORRAL) alpha = t < -600 ? 0 : 0.55;
      else if (r.state === STATE_DONE) alpha = drone ? (r.since < 40 ? 1 : 0) : Math.max(0, 1 - r.since / 45);
      else if (r.state === STATE_DNF) alpha = Math.max(0, 0.5 - r.since / 300);
      if (!show) alpha = 0;
      r.alpha = alpha;

      route.at(r.d, tmp);
      const lane = (r.lane * 0.85 + 0.15 * Math.sin(t * 0.013 + r.phase)) * (half - 0.9);
      r.x = tmp.x - tmp.tz * lane;
      r.z = tmp.z + tmp.tx * lane;
      r.tx = tmp.tx;
      r.tz = tmp.tz;
      r.y = drone ? 0 : 3.2;

      const o = r.i * 16;
      const sc = !drone && alpha > 0.01 ? r.size * (r.id === this.pickedId ? 1.5 : 1) : 0;
      mArr[o] = sc;
      mArr[o + 5] = sc;
      mArr[o + 10] = sc;
      mArr[o + 12] = r.x;
      mArr[o + 13] = r.y;
      mArr[o + 14] = r.z;
      const ci = r.i * 3;
      const col = r.id === this.pickedId ? this._c.set(COLORS.picked) : r.color;
      cArr[ci] = col.r * alpha;
      cArr[ci + 1] = col.g * alpha;
      cArr[ci + 2] = col.b * alpha;

      if (drone && alpha > 0.01 && r.d > figMin && r.d < figMax) {
        const running = r.state === STATE_RUN || (r.state === STATE_DONE && r.since < 5);
        const bob = running ? Math.abs(Math.sin(t * 9.1 + r.phase)) * 0.09 : 0;
        const lean = running ? 0.13 : 0.02;
        const yaw = Math.atan2(r.tx, r.tz);
        q.setFromEuler(this._euler(lean, yaw));
        const big = r.cls === 'you' || r.focus ? 1.08 : 1;
        m.compose(p.set(r.x, bob, r.z), q, s.set(big, big, big));
        this.figures.setMatrixAt(fig, m);
        this.figures.setColorAt(fig, r.id === this.pickedId ? this._c.set(COLORS.picked) : this.droneColor(r));
        m.compose(p.set(r.x, 0.25, r.z), this._q0 || (this._q0 = new Quaternion()), s.set(1, 1, 1));
        this.blobs.setMatrixAt(fig, m);
        this.figureIds[fig] = r.i;
        fig++;
      }
    }
    this.dots.visible = !drone && show;
    this.dots.instanceMatrix.needsUpdate = true;
    this.dots.instanceColor.needsUpdate = true;
    this.figures.count = fig;
    this.blobs.count = fig;
    this.figures.visible = drone;
    this.blobs.visible = drone;
    if (fig > 0) {
      this.figures.instanceMatrix.needsUpdate = true;
      this.figures.instanceColor.needsUpdate = true;
      this.blobs.instanceMatrix.needsUpdate = true;
    }

    // Rings.
    let k = 0;
    if (!drone && show) {
      const ringFor = (r, color) => {
        if (!r || r.alpha < 0.05 || k >= 8) return;
        const sc2 = r.cls === 'you' ? 1 : r.id === this.pickedId ? 0.8 : 0.7;
        m.makeTranslation(r.x, r.y, r.z).scale(e.set(sc2, sc2, sc2));
        this.rings.setMatrixAt(k, m);
        this.rings.setColorAt(k, this._c.set(color).multiplyScalar(r.alpha));
        k++;
      };
      for (const r of this.special) ringFor(r, r.cls === 'you' ? COLORS.you : r.cls === 'friend' ? COLORS.friend : COLORS.cat);
      if (this.pickedId != null) ringFor(this.byId.get(this.pickedId), COLORS.picked);
    }
    this.rings.count = k;
    if (k > 0) {
      this.rings.instanceMatrix.needsUpdate = true;
      this.rings.instanceColor.needsUpdate = true;
    }
  }

  _euler(x, y) {
    const eu = this._eu || (this._eu = new Euler(0, 0, 0, 'YXZ'));
    return eu.set(x, y, 0, 'YXZ');
  }

  /** Drone-view legend: your category amber, other men blue, women green. */
  droneColor(r) {
    if (r.cls === 'you') return this._c.set(COLORS.you);
    if (r.cls === 'friend') return this._c.set(COLORS.friend);
    if (r.cls === 'cat') return this._c.set(COLORS.cat);
    return this._c.set(r.g === 'F' ? COLORS.F : COLORS.M);
  }

  /** Nearest visible runner to a screen point (CSS px), or null. */
  pick(camera, x, y, w, h, mode) {
    const v = this._p;
    let best = null;
    let bestD = mode === 'drone' ? 40 : 26;
    const consider = (r, yOff) => {
      if (r.alpha < 0.05) return;
      v.set(r.x, r.y + yOff, r.z).project(camera);
      if (v.z > 1 || v.z < -1) return;
      const sx = ((v.x + 1) / 2) * w;
      const sy = ((1 - v.y) / 2) * h;
      let d = Math.hypot(sx - x, sy - y);
      if (r.cls !== 'field') d *= 0.75;
      if (d < bestD) {
        bestD = d;
        best = r;
      }
    };
    if (mode === 'drone') {
      for (let i = 0; i < this.figures.count; i++) consider(this.list[this.figureIds[i]], 0.9);
    } else {
      for (const r of this.list) consider(r, 0);
    }
    return best;
  }

  get(id) {
    return this.byId.get(id);
  }
}
