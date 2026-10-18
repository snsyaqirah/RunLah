// Camera rigs: replay overview / chase cam, drone at the finish, flyover.
import { CatmullRomCurve3, Vector3 } from 'three';
import { clamp, easeInOut } from './util.js';

export class Rigs {
  constructor(camera, controls, route, finish, landmarks) {
    this.camera = camera;
    this.controls = controls;
    this.route = route;
    this.finish = finish;
    this.landmarks = landmarks;
    this.insets = { top: 0, bottom: 0 };
    this.tween = null;
    this.followId = null;
    this._tmp = {};
    this._v = new Vector3();
    this._look = new Vector3();
    this._lookInit = false;

    // Flyover path: smoothed course ~130 m up.
    const pts = [];
    const tmp = {};
    for (let d = -250; d <= route.distance + 250; d += 280) {
      route.at(d, tmp);
      pts.push(new Vector3(tmp.x, 230, tmp.z));
    }
    this.fly = new CatmullRomCurve3(pts, false, 'centripetal');
    this.flyLen = this.fly.getLength();
  }

  /** Keeps the scene's centre in the free area between Flutter's top and bottom bars. */
  resize(w, h) {
    const cam = this.camera;
    cam.aspect = w / h;
    const shift = clamp((this.insets.bottom - this.insets.top) / 2, -h / 4, h / 4);
    if (Math.abs(shift) > 0.5) cam.setViewOffset(w, h, 0, shift, w, h);
    else cam.clearViewOffset();
    cam.updateProjectionMatrix();
    this.w = w;
    this.h = h;
  }

  _setNearFar(near, far) {
    this.camera.near = near;
    this.camera.far = far;
    this.camera.updateProjectionMatrix();
  }

  enter(mode) {
    const c = this.controls;
    this.mode = mode;
    this.tween = null;
    this._lookInit = false;
    if (mode === 'replay') {
      this._setNearFar(4, 70000);
      this.camera.fov = 50;
      c.enabled = true;
      c.enablePan = true;
      c.minDistance = 60;
      c.maxDistance = 16000;
      c.maxPolarAngle = 1.48;
      c.minPolarAngle = 0.05;
      this.fitOverview();
      if (this.followId != null) this.startFollow();
    } else if (mode === 'drone') {
      this._setNearFar(0.3, 60000);
      this.camera.fov = 52;
      c.enabled = true;
      c.enablePan = true;
      c.minDistance = 6;
      c.maxDistance = 260;
      c.maxPolarAngle = 1.5;
      c.minPolarAngle = 0.15;
      const { F, A, R } = this.finish;
      const target = F.clone().addScaledVector(A, -24).setY(0.5);
      const pos = F.clone().addScaledVector(A, 36).addScaledVector(R, -3.5).setY(23);
      this.camera.position.copy(pos);
      c.target.copy(target);
    } else {
      this._setNearFar(4, 70000);
      this.camera.fov = 55;
      c.enabled = false;
    }
    this.camera.updateProjectionMatrix();
    c.update();
  }

  /** Whole course in view from the WSW, avoiding the Flutter bars. */
  fitOverview() {
    const cam = this.camera;
    const route = this.route;
    const b = route.bounds();
    const target = new Vector3(b.cx + 150, 0, b.cz);
    const az = (160 * Math.PI) / 180;
    const el = (27 * Math.PI) / 180;
    const dir = new Vector3(Math.cos(el) * Math.cos(az), Math.sin(el), Math.cos(el) * Math.sin(az));
    const pts = [];
    for (let i = 0; i < route.n; i += 12) pts.push(new Vector3(route.x[i], 0, route.z[i]));
    const v = this._v;
    // The free area between Flutter's bars, in NDC.
    const h = this.h || window.innerHeight;
    const yTop = 1 - (2 * this.insets.top) / h - 0.06;
    const yBot = -1 + (2 * this.insets.bottom) / h + 0.04;
    const fits = (D) => {
      cam.position.copy(target).addScaledVector(dir, D);
      cam.lookAt(target);
      cam.updateMatrixWorld();
      for (const p of pts) {
        v.copy(p).project(cam);
        if (Math.abs(v.x) > 0.95 || v.y > yTop || v.y < yBot) return false;
      }
      return true;
    };
    const search = () => {
      let lo = 800;
      let hi = 40000;
      for (let k = 0; k < 22; k++) {
        const mid = (lo + hi) / 2;
        if (fits(mid)) hi = mid;
        else lo = mid;
      }
      return hi;
    };
    // Fit, then slide the target sideways so the course sits centred, and refit.
    let D = search();
    for (let pass = 0; pass < 2; pass++) {
      cam.position.copy(target).addScaledVector(dir, D);
      cam.lookAt(target);
      cam.updateMatrixWorld();
      let minX = Infinity;
      let maxX = -Infinity;
      for (const p of pts) {
        v.copy(p).project(cam);
        minX = Math.min(minX, v.x);
        maxX = Math.max(maxX, v.x);
      }
      const off = (minX + maxX) / 2;
      const right = new Vector3().setFromMatrixColumn(cam.matrixWorld, 0);
      target.addScaledVector(right, off * D * Math.tan((cam.fov * Math.PI) / 360) * cam.aspect);
      D = search();
    }
    cam.position.copy(target).addScaledVector(dir, D);
    this.controls.target.copy(target);
    this.controls.update();
    this.home = { pos: cam.position.clone(), target: target.clone() };
  }

  setFollow(id) {
    this.followId = id;
    if (this.mode === 'replay') {
      if (id != null) this.startFollow();
      else if (this.home) this._tweenTo(this.home.pos, this.home.target, 1.2);
    }
  }

  startFollow() {
    this._needFollowStart = true;
  }

  _tweenTo(pos, target, dur) {
    this.tween = {
      t: 0,
      dur,
      p0: this.camera.position.clone(),
      t0: this.controls.target.clone(),
      p1: pos.clone(),
      t1: target.clone(),
      chase: false,
    };
  }

  /** Per-frame camera work. Returns the course distance under a flyover camera. */
  update(dt, runner, flyT, flyDur) {
    const cam = this.camera;
    const c = this.controls;
    if (this.mode === 'flyover') {
      const u = easeInOut(clamp(flyT / flyDur, 0, 1));
      const p = this.fly.getPointAt(u);
      const ahead = clamp(u + 700 / this.flyLen, 0, 1);
      const look = this.fly.getPointAt(ahead);
      look.y = 0;
      if (u + 700 / this.flyLen > 1) {
        // Past the end: look on along the finish straight.
        const over = (u + 700 / this.flyLen - 1) * this.flyLen;
        look.x += this.route.endDir.x * over;
        look.z += this.route.endDir.z * over;
      }
      if (!this._lookInit || dt > 0.5) {
        this._look.copy(look);
        this._lookInit = true;
      } else {
        this._look.lerp(look, 1 - Math.exp(-dt * 2.5));
      }
      cam.position.copy(p);
      cam.lookAt(this._look);
      return u * this.route.distance;
    }

    if (this.mode === 'replay' && this.followId != null && runner && runner.alpha > 0.01) {
      const tgt = this._v.set(runner.x, 0, runner.z);
      if (this._needFollowStart) {
        this._needFollowStart = false;
        const back = new Vector3(-runner.tx, 0, -runner.tz).normalize();
        const side = new Vector3(-runner.tz, 0, runner.tx);
        const pos = tgt.clone().addScaledVector(back, 270).addScaledVector(side, -110).setY(125);
        this._tweenTo(pos, tgt, 1.4);
        this.tween.chase = true;
      }
      if (this.tween && this.tween.chase) {
        // Ease toward the chase position while the runner keeps moving.
        const tw = this.tween;
        tw.t += dt;
        const k = easeInOut(clamp(tw.t / tw.dur, 0, 1));
        const offset = tw.p1.clone().sub(tw.t1);
        cam.position.lerpVectors(tw.p0, tgt.clone().add(offset), k);
        c.target.lerpVectors(tw.t0, tgt, k);
        if (k >= 1) this.tween = null;
      } else {
        const delta = tgt.clone().sub(c.target);
        c.target.add(delta);
        cam.position.add(delta);
      }
    } else if (this.tween) {
      const tw = this.tween;
      tw.t += dt;
      const k = easeInOut(clamp(tw.t / tw.dur, 0, 1));
      cam.position.lerpVectors(tw.p0, tw.p1, k);
      c.target.lerpVectors(tw.t0, tw.t1, k);
      if (k >= 1) this.tween = null;
    }
    c.update();
    return null;
  }

  /** Small hover drift for the drone, applied around rendering only. */
  droneDrift(time) {
    return this._v.set(Math.sin(time * 0.31) * 0.35, Math.sin(time * 0.53) * 0.22, Math.cos(time * 0.27) * 0.3);
  }
}
