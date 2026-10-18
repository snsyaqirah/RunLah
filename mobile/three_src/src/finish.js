// The finish area at Dataran Merdeka, detailed for the drone view.
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import {
  BoxGeometry,
  CanvasTexture,
  CapsuleGeometry,
  Color,
  CylinderGeometry,
  Group,
  InstancedMesh,
  Matrix4,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  PlaneGeometry,
  Quaternion,
  SRGBColorSpace,
  SphereGeometry,
  Vector3,
} from 'three';
import { dotMaterial, figureMaterial } from './materials.js';
import { fmtDuration, rng } from './util.js';

const FONT = 'system-ui, -apple-system, "Segoe UI", Roboto, sans-serif';

function canvasTexture(w, h, draw) {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const ctx = c.getContext('2d');
  draw(ctx, w, h);
  const t = new CanvasTexture(c);
  t.colorSpace = SRGBColorSpace;
  t.anisotropy = 4;
  return { texture: t, canvas: c, ctx };
}

function bannerTexture(title, sub) {
  return canvasTexture(1024, 200, (ctx, w, h) => {
    const g = ctx.createLinearGradient(0, 0, 0, h);
    g.addColorStop(0, '#1d2d52');
    g.addColorStop(1, '#0d1630');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = '#e8930c';
    ctx.fillRect(0, h - 22, w, 22);
    ctx.fillRect(0, 0, w, 8);
    ctx.fillStyle = '#ffffff';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.font = `900 118px ${FONT}`;
    if ('letterSpacing' in ctx) ctx.letterSpacing = '14px';
    ctx.fillText(title, w / 2 + 7, h / 2 - 8);
    if ('letterSpacing' in ctx) ctx.letterSpacing = '0px';
    ctx.font = `800 30px ${FONT}`;
    ctx.fillStyle = '#e8930c';
    ctx.textAlign = 'left';
    ctx.fillText('RunLah', 26, h / 2 - 8);
    ctx.textAlign = 'right';
    ctx.fillText('RunLah', w - 26, h / 2 - 8);
    if (sub) {
      ctx.textAlign = 'center';
      ctx.font = `700 15px ${FONT}`;
      ctx.fillStyle = '#14213d';
      ctx.fillText(sub.toUpperCase(), w / 2, h - 11);
    }
  });
}

function flagTexture() {
  // Jalur Gemilang: 14 red/white stripes, blue canton, yellow crescent + star.
  return canvasTexture(280, 140, (ctx, w, h) => {
    for (let i = 0; i < 14; i++) {
      ctx.fillStyle = i % 2 === 0 ? '#cc0001' : '#ffffff';
      ctx.fillRect(0, (i * h) / 14, w, h / 14 + 1);
    }
    ctx.fillStyle = '#010066';
    ctx.fillRect(0, 0, w / 2, (h * 8) / 14);
    ctx.fillStyle = '#ffcc00';
    ctx.beginPath();
    ctx.arc(52, 40, 26, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#010066';
    ctx.beginPath();
    ctx.arc(60, 40, 22, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#ffcc00';
    ctx.beginPath();
    for (let i = 0; i < 28; i++) {
      const a = (i / 28) * Math.PI * 2 - Math.PI / 2;
      const r = i % 2 === 0 ? 20 : 9;
      ctx.lineTo(98 + Math.cos(a) * r, 40 + Math.sin(a) * r);
    }
    ctx.fill();
  });
}

/** Runner figure: capsule body + head, feet at y = 0, ~1.75 m tall. */
export function figureGeometry() {
  const body = new CapsuleGeometry(0.24, 0.82, 4, 8);
  body.translate(0, 0.24 + 0.41, 0);
  const head = new SphereGeometry(0.15, 10, 8);
  head.translate(0, 1.58, 0);
  return mergeGeometries([body, head]);
}

export class FinishArea {
  constructor(scene, route, strings, figGeo) {
    const tmp = {};
    route.at(route.distance, tmp);
    const F = new Vector3(tmp.x, 0, tmp.z);
    const A = new Vector3(route.endDir.x, 0, route.endDir.z).normalize();
    const R = new Vector3(-A.z, 0, A.x);
    this.F = F;
    this.A = A;
    this.R = R;
    const half = 7;
    this.group = new Group();
    scene.add(this.group);

    // Gantry, facing incoming runners.
    const gantry = new Group();
    gantry.position.copy(F);
    gantry.rotation.y = Math.atan2(-A.x, -A.z);
    this.group.add(gantry);
    const frame = new MeshLambertMaterial({ color: '#1c2a4a' });
    for (const s of [-1, 1]) {
      const pillar = new Mesh(new BoxGeometry(1.1, 7.6, 1.1), frame);
      pillar.position.set(s * (half + 0.9), 3.8, 0);
      gantry.add(pillar);
      const foot = new Mesh(new BoxGeometry(1.6, 0.5, 1.6), frame);
      foot.position.set(s * (half + 0.9), 0.25, 0);
      gantry.add(foot);
    }
    const banner = bannerTexture(strings.finish, strings.event);
    const bannerMat = new MeshBasicMaterial({ map: banner.texture });
    const beam = new Mesh(new BoxGeometry(2 * half + 2.9, 2.3, 0.9), [frame, frame, frame, frame, bannerMat, bannerMat]);
    beam.position.y = 7.6 + 1.15 - 0.4;
    gantry.add(beam);
    this.clock = canvasTexture(256, 72, () => {});
    this.clockMat = new MeshBasicMaterial({ map: this.clock.texture });
    const clockBox = new Mesh(new BoxGeometry(3.2, 0.9, 0.5), [frame, frame, frame, frame, this.clockMat, this.clockMat]);
    clockBox.position.y = beam.position.y + 1.15 + 0.45;
    gantry.add(clockBox);
    this._clockText = '';

    // Timing mat + finish line.
    const matTex = canvasTexture(256, 64, (ctx, w, h) => {
      ctx.fillStyle = '#15171c';
      ctx.fillRect(0, 0, w, h);
      ctx.fillStyle = '#f2c230';
      for (let x = 0; x < w; x += 22) ctx.fillRect(x, 6, 8, h - 12);
    });
    const mat = new Mesh(new PlaneGeometry(2 * half, 2.6), new MeshLambertMaterial({ map: matTex.texture }));
    mat.rotation.x = -Math.PI / 2;
    mat.position.set(0, 0.22, 1.6);
    gantry.add(mat);
    const line = new Mesh(new PlaneGeometry(2 * half, 0.5), new MeshBasicMaterial({ color: '#f4f4f0' }));
    line.rotation.x = -Math.PI / 2;
    line.position.set(0, 0.24, 0);
    gantry.add(line);

    const rand = rng(34144);
    const m = new Matrix4();
    const q = new Quaternion();
    const s = new Vector3();
    const p = new Vector3();
    const up = new Vector3(0, 1, 0);
    const yawAt = (tx, tz) => Math.atan2(-tz, tx);

    // Crowd barriers along both sides.
    const barrierSpots = [];
    for (let d = route.distance - 170; d < route.distance + 40; d += 2.35) {
      route.at(d, tmp);
      for (const sd of [-1, 1]) barrierSpots.push([tmp.x - tmp.tz * sd * (half + 0.45), tmp.z + tmp.tx * sd * (half + 0.45), yawAt(tmp.tx, tmp.tz), sd]);
    }
    const barGeo = new BoxGeometry(2.2, 1.05, 0.07);
    barGeo.translate(0, 0.6, 0);
    const bars = new InstancedMesh(barGeo, new MeshLambertMaterial({ color: '#ffffff' }), barrierSpots.length);
    const cA = new Color('#dfe5ee');
    const cB = new Color('#2e5c8a');
    barrierSpots.forEach(([x, z, yaw], i) => {
      q.setFromAxisAngle(up, yaw);
      m.compose(p.set(x, 0, z), q, s.set(1, 1, 1));
      bars.setMatrixAt(i, m);
      bars.setColorAt(i, Math.floor(i / 2) % 3 === 0 ? cB : cA);
    });
    this.group.add(bars);

    // Spectators behind the barriers, in clumps.
    const fans = [];
    for (let d = route.distance - 160; d < route.distance - 6; d += 0.9) {
      route.at(d, tmp);
      for (const sd of [-1, 1]) {
        const clump = Math.sin(d * 0.07 + sd * 2) + Math.sin(d * 0.19 + sd);
        if (rand() > 0.42 + clump * 0.22) continue;
        const off = half + 1.2 + rand() * 2.6;
        const x = tmp.x - tmp.tz * sd * off + (rand() - 0.5) * 0.4;
        const z = tmp.z + tmp.tx * sd * off + (rand() - 0.5) * 0.4;
        fans.push([x, z, yawAt(tmp.tx, tmp.tz) + (sd > 0 ? Math.PI / 2 : -Math.PI / 2), rand()]);
      }
    }
    this.fans = new InstancedMesh(figGeo, figureMaterial(), fans.length);
    // Muted shirts so the runners' legend colours stand out.
    const shirt = ['#8a4a5a', '#7d6a48', '#4f5f7a', '#6a5a86', '#7a5a48', '#4d6a64', '#9a9aa4', '#874a6a', '#5a6a7a'].map((h) => new Color(h));
    this.fanData = fans;
    fans.forEach(([x, z, yaw, r], i) => {
      q.setFromAxisAngle(up, yaw);
      m.compose(p.set(x, 0, z), q, s.setScalar(0.9 + r * 0.2));
      this.fans.setMatrixAt(i, m);
      this.fans.setColorAt(i, shirt[(r * 997) % shirt.length | 0]);
    });
    this.group.add(this.fans);

    // Street lamps (glow at night) and trees along the run-in.
    const lampSpots = [];
    for (let d = route.distance - 380; d < route.distance + 60; d += 34) {
      route.at(d, tmp);
      for (const sd of [-1, 1]) lampSpots.push([tmp.x - tmp.tz * sd * (half + 6), tmp.z + tmp.tx * sd * (half + 6)]);
    }
    const poleGeo = new CylinderGeometry(0.09, 0.14, 8, 6);
    poleGeo.translate(0, 4, 0);
    const poles = new InstancedMesh(poleGeo, new MeshLambertMaterial({ color: '#2b3342' }), lampSpots.length);
    this.lamps = new InstancedMesh(new PlaneGeometry(1, 1), dotMaterial({ worldSize: 3.2, minPx: 2, maxPx: 70 }), lampSpots.length);
    this.lamps.frustumCulled = false;
    const warm = new Color('#ffcf8a');
    lampSpots.forEach(([x, z], i) => {
      m.makeTranslation(x, 0, z);
      poles.setMatrixAt(i, m);
      m.makeTranslation(x, 8.1, z);
      this.lamps.setMatrixAt(i, m);
      this.lamps.setColorAt(i, warm);
    });
    this.lampColor = warm;
    this.group.add(poles, this.lamps);

    this.treeSpots = [];
    for (let d = route.distance - 420; d < route.distance + 80; d += 10 + rand() * 6) {
      route.at(d, tmp);
      for (const sd of [-1, 1]) {
        if (rand() < 0.25) continue;
        const off = half + 9 + rand() * 6;
        this.treeSpots.push([tmp.x - tmp.tz * sd * off, tmp.z + tmp.tx * sd * off]);
      }
    }

    // Dataran Merdeka field with mowing stripes, and the flagpole.
    const grassTex = canvasTexture(256, 256, (ctx, w, h) => {
      for (let i = 0; i < 8; i++) {
        ctx.fillStyle = i % 2 ? '#2f6b34' : '#3a7a3c';
        ctx.fillRect(0, (i * h) / 8, w, h / 8);
      }
    });
    const field = new Mesh(new PlaneGeometry(110, 210), new MeshLambertMaterial({ map: grassTex.texture }));
    field.rotation.x = -Math.PI / 2;
    field.rotation.z = Math.atan2(-A.x, -A.z);
    const fc = F.clone().addScaledVector(A, -70).addScaledVector(R, half + 34 + 55);
    field.position.set(fc.x, 0.1, fc.z);
    this.group.add(field);
    const fp = F.clone().addScaledVector(A, 25).addScaledVector(R, half + 40);
    const pole = new Mesh(new CylinderGeometry(0.35, 0.8, 95, 10), new MeshLambertMaterial({ color: '#c9ced8' }));
    pole.position.set(fp.x, 47.5, fp.z);
    this.group.add(pole);
    const flag = new Mesh(new PlaneGeometry(14, 7, 8, 1), new MeshLambertMaterial({ map: flagTexture().texture, side: 2 }));
    flag.position.set(fp.x + 7 * R.x, 90, fp.z + 7 * R.z);
    flag.rotation.y = Math.atan2(-R.z, R.x);
    const fpos = flag.geometry.attributes.position;
    for (let i = 0; i < fpos.count; i++) fpos.setZ(i, Math.sin((fpos.getX(i) + 7) * 0.5) * 0.7 * ((fpos.getX(i) + 7) / 14));
    flag.geometry.computeVertexNormals();
    this.group.add(flag);
  }

  /** Race clock on the gantry (gun time). */
  setClock(t) {
    const text = fmtDuration(Math.max(0, t));
    if (text === this._clockText) return;
    this._clockText = text;
    const { ctx, canvas } = this.clock;
    ctx.fillStyle = '#05070c';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = '#ff9f1a';
    ctx.font = `800 52px ui-monospace, "SF Mono", Menlo, Consolas, monospace`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.shadowColor = '#ff7a00';
    ctx.shadowBlur = 12;
    ctx.fillText(text, canvas.width / 2, canvas.height / 2 + 2);
    ctx.shadowBlur = 0;
    this.clock.texture.needsUpdate = true;
  }

  /** Lamps brighten with the night; fans bob. */
  update(t, night, active) {
    this.lamps.visible = night > 0.05;
    if (this.lamps.instanceColor && Math.abs((this._night ?? -1) - night) > 0.02) {
      this._night = night;
      const c = new Color().copy(this.lampColor).multiplyScalar(0.25 + 0.75 * night);
      for (let i = 0; i < this.lamps.count; i++) this.lamps.setColorAt(i, c);
      this.lamps.instanceColor.needsUpdate = true;
    }
    if (!active) return;
    const m = this._m || (this._m = new Matrix4());
    const q = this._q || (this._q = new Quaternion());
    const s = this._s || (this._s = new Vector3());
    const p = this._p || (this._p = new Vector3());
    const up = this._up || (this._up = new Vector3(0, 1, 0));
    this.fanData.forEach(([x, z, yaw, r], i) => {
      const hop = Math.max(0, Math.sin(t * (2 + r * 3) + r * 50)) * 0.12 * (r > 0.6 ? 1 : 0.2);
      q.setFromAxisAngle(up, yaw);
      m.compose(p.set(x, hop, z), q, s.setScalar(0.9 + r * 0.2));
      this.fans.setMatrixAt(i, m);
    });
    this.fans.instanceMatrix.needsUpdate = true;
  }
}
