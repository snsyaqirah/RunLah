// Sparse low-poly city blocks, parks, lakes and trees for depth.
import {
  BoxGeometry,
  Color,
  CylinderGeometry,

  IcosahedronGeometry,
  InstancedMesh,
  Matrix4,
  Mesh,
  MeshLambertMaterial,
  Quaternion,
  Shape,
  ShapeGeometry,
  Vector3,
} from 'three';
import { footprint } from './landmarks.js';
import { STYLE, facadeMaterial, waterMaterial } from './materials.js';
import { rng } from './util.js';

/** Grid hash of route samples (plus corral/chute extensions) for fast clearance checks. */
class RouteHash {
  constructor(route, cell = 100) {
    this.cell = cell;
    this.map = new Map();
    const tmp = {};
    const add = (x, z) => {
      const k = `${Math.floor(x / cell)},${Math.floor(z / cell)}`;
      let a = this.map.get(k);
      if (!a) this.map.set(k, (a = []));
      a.push(x, z);
    };
    for (let i = 0; i < route.n; i++) add(route.x[i], route.z[i]);
    for (let d = -1400; d < 0; d += 20) {
      route.at(d, tmp);
      add(tmp.x, tmp.z);
    }
    for (let d = route.distance; d < route.distance + 120; d += 20) {
      route.at(d, tmp);
      add(tmp.x, tmp.z);
    }
  }

  clearance(x, z) {
    const c = this.cell;
    const cx = Math.floor(x / c);
    const cz = Math.floor(z / c);
    let best = Infinity;
    for (let i = -1; i <= 1; i++) {
      for (let j = -1; j <= 1; j++) {
        const a = this.map.get(`${cx + i},${cz + j}`);
        if (!a) continue;
        for (let k = 0; k < a.length; k += 2) {
          const d = (a[k] - x) ** 2 + (a[k + 1] - z) ** 2;
          if (d < best) best = d;
        }
      }
    }
    return Math.sqrt(best);
  }
}

const UP = new Vector3(0, 1, 0);

function blob(r, seed, n = 30) {
  const rand = rng(seed);
  const pts = [];
  const ph = [rand() * 6, rand() * 6, rand() * 6];
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2;
    const k = 0.84 + 0.1 * Math.sin(a * 2 + ph[0]) + 0.07 * Math.sin(a * 3 + ph[1]) + 0.05 * Math.sin(a * 5 + ph[2]);
    pts.push([Math.cos(a) * r * k, Math.sin(a) * r * k]);
  }
  return pts;
}

function inPoly(pts, x, y) {
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [xi, yi] = pts[i];
    const [xj, yj] = pts[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

function flatShape(pts, y, material) {
  const s = new Shape();
  pts.forEach(([x, z], i) => (i ? s.lineTo(x, -z) : s.moveTo(x, -z)));
  s.closePath();
  const g = new ShapeGeometry(s);
  g.rotateX(-Math.PI / 2);
  const m = new Mesh(g, material);
  m.position.y = y;
  return m;
}

/** Instanced trees: canopies + trunks share matrices. */
export class Trees {
  constructor(scene, max) {
    const canopy = new IcosahedronGeometry(1, 0);
    canopy.translate(0, 1.35, 0);
    const trunk = new CylinderGeometry(0.12, 0.18, 1, 5);
    trunk.translate(0, 0.5, 0);
    this.canopy = new InstancedMesh(canopy, new MeshLambertMaterial({ color: '#ffffff', flatShading: true }), max);
    this.trunk = new InstancedMesh(trunk, new MeshLambertMaterial({ color: '#3b2a1e' }), max);
    this.canopy.count = 0;
    this.trunk.count = 0;
    this.max = max;
    this.m = new Matrix4();
    this.q = new Quaternion();
    this.s = new Vector3();
    this.p = new Vector3();
    this.c = new Color();
    this.palette = ['#2f6b3a', '#3a7d44', '#24573a', '#4a8a3c', '#2c6447'].map((h) => new Color(h));
    scene.add(this.canopy, this.trunk);
  }

  add(x, z, size, rand) {
    const i = this.canopy.count;
    if (i >= this.max) return;
    const w = size * (0.8 + rand() * 0.4);
    this.q.setFromAxisAngle(UP, rand() * 6.28);
    this.m.compose(this.p.set(x, 0, z), this.q, this.s.set(w * 0.75, size, w * 0.75));
    this.canopy.setMatrixAt(i, this.m);
    this.trunk.setMatrixAt(i, this.m);
    this.canopy.setColorAt(i, this.c.copy(this.palette[(rand() * this.palette.length) | 0]));
    this.canopy.count = this.trunk.count = i + 1;
  }

  done() {
    this.canopy.instanceMatrix.needsUpdate = true;
    this.trunk.instanceMatrix.needsUpdate = true;
    if (this.canopy.instanceColor) this.canopy.instanceColor.needsUpdate = true;
    this.canopy.computeBoundingSphere();
    this.trunk.computeBoundingSphere();
  }
}

export function buildCity(scene, data, route, landmarks, trees) {
  const rand = rng(118);
  const hash = new RouteHash(route);
  const b = route.bounds();
  const lms = (data.landmarks || []).map((l) => {
    const placed = landmarks.find((p) => p.name === l.name);
    return { ...l, x: placed ? placed.x : l.x, z: placed ? placed.z : -l.y, r: footprint(l) };
  });

  // Parks: grass, a lake, lots of trees.
  const grass = new MeshLambertMaterial({ color: '#1e4a2c' });
  const parks = [];
  for (const l of lms.filter((p) => p.kind === 'park')) {
    const big = l.r > 300;
    const pts = blob(l.r, Math.round(l.x * 7 + l.z));
    const world = pts.map(([x, z]) => [x + l.x, z + l.z]);
    scene.add(flatShape(world, 0.08, grass));
    const lake = blob(big ? 150 : 70, Math.round(l.x), 22).map(([x, z]) => [x * 1.3 + l.x + (big ? -60 : -40), z * 0.8 + l.z + (big ? 40 : -60)]);
    scene.add(flatShape(lake, 0.2, waterMaterial()));
    parks.push({ world, lake });
    const n = big ? 650 : 220;
    for (let k = 0; k < n * 3 && n > 0; k++) {
      const x = l.x + (rand() * 2 - 1) * l.r;
      const z = l.z + (rand() * 2 - 1) * l.r;
      if (!inPoly(world, x, z) || inPoly(lake, x, z)) continue;
      if (hash.clearance(x, z) < 22) continue;
      trees.add(x, z, 9 + rand() * 8, rand);
    }
  }
  // Bukit Nanas forest around KL Tower.
  for (const l of lms.filter((p) => p.kind === 'tower' && !/118/.test(p.name))) {
    for (let k = 0; k < 260; k++) {
      const a = rand() * 6.283;
      const r = 40 + Math.sqrt(rand()) * 175;
      const x = l.x + Math.cos(a) * r;
      const z = l.z + Math.sin(a) * r * 0.9;
      if (hash.clearance(x, z) < 20) continue;
      const t = Math.min(1, r / 220);
      const y = 48 * Math.sqrt(Math.max(0, 1 - t * t));
      const i = trees.canopy.count;
      trees.add(x, z, 10 + rand() * 6, rand);
      if (trees.canopy.count === i) break;
      // Lift the tree onto the hill.
      trees.canopy.getMatrixAt(i, trees.m);
      trees.m.elements[13] = y - 2;
      trees.canopy.setMatrixAt(i, trees.m);
      trees.trunk.setMatrixAt(i, trees.m);
    }
  }

  // City blocks.
  const cbd = [
    [2000, -1116, 1000, 1],
    [1934, 133, 800, 0.85],
    [778, 685, 600, 0.7],
    [1300, -600, 700, 0.5],
  ];
  const blocks = [];
  const pad = 1300;
  const step = 72;
  for (let x = b.minX - pad; x <= b.maxX + pad; x += step) {
    for (let z = b.minZ - pad; z <= b.maxZ + pad; z += step) {
      const px = x + (rand() - 0.5) * step * 0.6;
      const pz = z + (rand() - 0.5) * step * 0.6;
      let dense = 0;
      for (const [cx, cz, r, w] of cbd) dense = Math.max(dense, w * Math.exp(-((px - cx) ** 2 + (pz - cz) ** 2) / (r * r)));
      const fromCentre = Math.hypot(px - b.cx, pz - b.cz) / 4500;
      // Every stretch of the course gets a neighbourhood around it.
      const nearRoad = hash.clearance(px, pz);
      const along = nearRoad < 100 ? 0.3 : 0;
      const keep = 0.2 + dense * 0.5 + along - Math.max(0, fromCentre - 0.55) * 0.45;
      if (rand() > keep) continue;
      const w = 16 + rand() * 30 + dense * 18;
      const d = 16 + rand() * 30 + dense * 18;
      const half = Math.hypot(w, d) / 2;
      const clear = nearRoad < 100 ? nearRoad : hash.clearance(px, pz);
      if (clear < half + 16) continue;
      let blocked = false;
      for (const l of lms) {
        if (Math.hypot(px - l.x, pz - l.z) < l.r + half) {
          blocked = true;
          break;
        }
      }
      if (blocked) continue;
      const tall = rand() < 0.06 + dense * 0.3;
      let h = tall ? 60 + rand() * (90 + dense * 170) : 8 + rand() * rand() * 40 + dense * 20;
      // Keep the street canyon open so the course stays visible from above.
      h = Math.min(h, 12 + Math.max(0, clear - half) * 0.9);
      blocks.push([px, pz, w, d, h, 0.38 + (rand() - 0.5) * 0.25]);
    }
  }

  const geo = new BoxGeometry(1, 1, 1);
  geo.translate(0, 0.5, 0);
  const mat = facadeMaterial({ style: STYLE.office, base: '#2a3448', win: '#ffcf86', density: 0.5 });
  const mesh = new InstancedMesh(geo, mat, blocks.length);
  const m = new Matrix4();
  const q = new Quaternion();
  const axis = new Vector3(0, 1, 0);
  const s = new Vector3();
  const p = new Vector3();
  blocks.forEach(([x, z, w, d, h, yaw], i) => {
    q.setFromAxisAngle(axis, yaw);
    m.compose(p.set(x, 0, z), q, s.set(w, h, d));
    mesh.setMatrixAt(i, m);
  });
  mesh.instanceMatrix.needsUpdate = true;
  mesh.computeBoundingSphere();
  scene.add(mesh);
  return { mesh, count: blocks.length, hash };
}


