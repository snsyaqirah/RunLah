// Low-poly KL landmarks at their real positions and heights.
import {
  BoxGeometry,
  BufferGeometry,
  CircleGeometry,
  CylinderGeometry,
  ExtrudeGeometry,
  Float32BufferAttribute,
  Group,
  LatheGeometry,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  Shape,
  SphereGeometry,
  Vector2,
} from 'three';
import { STYLE, facadeMaterial, waterMaterial } from './materials.js';

/** Extruded star prism (Petronas floor plan), base at y0. */
function starPrism(rOut, rIn, points, y0, y1) {
  const s = new Shape();
  for (let i = 0; i < points * 2; i++) {
    const a = (i / (points * 2)) * Math.PI * 2;
    const r = i % 2 === 0 ? rOut : rIn;
    if (i === 0) s.moveTo(Math.cos(a) * r, Math.sin(a) * r);
    else s.lineTo(Math.cos(a) * r, Math.sin(a) * r);
  }
  s.closePath();
  const g = new ExtrudeGeometry(s, { depth: y1 - y0, bevelEnabled: false, curveSegments: 1 });
  g.rotateX(-Math.PI / 2);
  g.translate(0, y0, 0);
  return g;
}

function cyl(rTop, rBot, y0, y1, seg = 12) {
  const g = new CylinderGeometry(rTop, rBot, y1 - y0, seg, 1);
  g.translate(0, (y0 + y1) / 2, 0);
  return g;
}

/** Stack of rings with alternating rotation = faceted, tapering tower. */
function facetedTower(rBase, rTop, height, rings, sides) {
  const pos = [];
  const ring = (i) => {
    const t = i / rings;
    const y = t * height;
    const r = rBase + (rTop - rBase) * Math.pow(t, 1.15);
    const off = (i % 2) * (Math.PI / sides);
    const pts = [];
    for (let j = 0; j < sides; j++) {
      const a = off + (j / sides) * Math.PI * 2;
      pts.push([Math.cos(a) * r, y, Math.sin(a) * r]);
    }
    return pts;
  };
  for (let i = 0; i < rings; i++) {
    const a = ring(i);
    const b = ring(i + 1);
    for (let j = 0; j < sides; j++) {
      const j1 = (j + 1) % sides;
      // Antiprism band: two triangles per side.
      if (i % 2 === 0) {
        pos.push(...a[j], ...b[j], ...a[j1]);
        pos.push(...a[j1], ...b[j], ...b[j1]);
      } else {
        pos.push(...a[j], ...b[j], ...b[j1]);
        pos.push(...a[j], ...b[j1], ...a[j1]);
      }
    }
  }
  const top = ring(rings);
  for (let j = 0; j < sides; j++) {
    const j1 = (j + 1) % sides;
    pos.push(0, height, 0, ...top[j1], ...top[j]);
  }
  const g = new BufferGeometry();
  g.setAttribute('position', new Float32BufferAttribute(pos, 3));
  g.computeVertexNormals();
  return g;
}

function petronas(scale) {
  const g = new Group();
  const steel = facadeMaterial({ style: STYLE.petronas, base: '#8d97a8', accent: '#cfe0ff', win: '#fff2d6', height: 452 * scale });
  const tiers = [
    [0, 175, 23.5],
    [175, 256, 22],
    [256, 306, 19.5],
    [306, 336, 16.5],
    [336, 358, 13.5],
    [358, 374, 10.5],
    [374, 384, 7.5],
  ];
  const spireMat = facadeMaterial({ style: STYLE.lit, base: '#9aa3b2', accent: '#e8f0ff', height: 70 });
  for (const side of [-1, 1]) {
    const tower = new Group();
    for (const [a, b, r] of tiers) {
      tower.add(new Mesh(starPrism(r, r * 0.8, 8, a * scale, b * scale), steel));
    }
    tower.add(new Mesh(cyl(1.6, 6.5, 384 * scale, 414 * scale, 8), spireMat));
    tower.add(new Mesh(cyl(0.25, 1.6, 414 * scale, 452 * scale, 6), spireMat));
    tower.position.x = side * 47;
    g.add(tower);
  }
  // Skybridge on levels 41-42 and its inverted-V legs.
  const bridgeMat = facadeMaterial({ style: STYLE.lit, base: '#9aa3b2', accent: '#ffffff', height: 10 });
  const bridge = new Mesh(new BoxGeometry(56, 6, 5), bridgeMat);
  bridge.position.y = 172 * scale;
  g.add(bridge);
  for (const side of [-1, 1]) {
    const leg = new Mesh(cyl(0.9, 0.9, 0, 52 * scale, 6), bridgeMat);
    leg.position.set(side * 2, 128 * scale, 0);
    leg.rotation.z = side * -0.5;
    g.add(leg);
  }
  // Suria KLCC podium.
  const podium = new Mesh(new BoxGeometry(250, 28, 110), facadeMaterial({ style: STYLE.office, base: '#3a4252', win: '#ffe3b0', density: 0.7, seed: 4 }));
  podium.position.set(0, 14, -95);
  g.add(podium);
  return g;
}

function klTower(scale) {
  const g = new Group();
  const hill = new Mesh(new SphereGeometry(1, 28, 10, 0, Math.PI * 2, 0, Math.PI / 2), new MeshLambertMaterial({ color: '#1d3b26', flatShading: true }));
  hill.scale.set(230, 48, 210);
  g.add(hill);
  const base = 46;
  const s = (v) => base + v * scale;
  const shaftMat = facadeMaterial({ style: STYLE.lit, base: '#9aa0aa', accent: '#8a6cff', height: 270 * scale });
  g.add(new Mesh(cyl(23, 28, s(0), s(14), 12), facadeMaterial({ style: STYLE.office, base: '#5a6070', win: '#ffe0a8', density: 0.6, seed: 2 })));
  g.add(new Mesh(cyl(6.2, 10.5, s(0), s(268), 12), shaftMat));
  const prof = [
    [5, 0], [13, 4], [21, 13], [24.5, 22], [23, 29], [19, 34], [20.5, 39], [16, 46], [9, 52], [6.5, 56],
  ].map(([r, y]) => new Vector2(r, y * scale));
  const pod = new Mesh(new LatheGeometry(prof, 20), facadeMaterial({ style: STYLE.office, base: '#7d8594', win: '#c9e4ff', density: 0.8, seed: 7, floor: 4, bay: 2.6 }));
  pod.position.y = s(262);
  g.add(pod);
  g.add(new Mesh(cyl(4.2, 6.2, s(318), s(338), 10), shaftMat));
  g.add(new Mesh(cyl(0.35, 2.6, s(338), s(421), 6), facadeMaterial({ style: STYLE.lit, base: '#c8ccd4', accent: '#d8ccff', height: 80 })));
  const beacon = new Mesh(new SphereGeometry(2.2, 10, 6), new MeshBasicMaterial({ color: '#ff3b30' }));
  beacon.position.y = s(421);
  g.add(beacon);
  g.userData.top = s(421);
  return g;
}

function merdeka118(scale) {
  const g = new Group();
  const body = new Mesh(
    facetedTower(40, 21, 505 * scale, 14, 8),
    facadeMaterial({ style: STYLE.glass, base: '#26384f', accent: '#6fd3ff', win: '#d6ecff' }),
  );
  g.add(body);
  const spire = new Mesh(
    facetedTower(15, 0.4, 174 * scale, 6, 4),
    facadeMaterial({ style: STYLE.lit, base: '#9fb0c4', accent: '#b8ecff', height: 174 * scale }),
  );
  spire.position.y = 505 * scale;
  g.add(spire);
  const podium = new Mesh(new BoxGeometry(150, 34, 95), facadeMaterial({ style: STYLE.office, base: '#344055', win: '#ffe0b0', density: 0.55, seed: 9 }));
  podium.position.set(0, 17, 60);
  g.add(podium);
  return g;
}

function sultanAbdulSamad(scale) {
  const g = new Group();
  const brick = facadeMaterial({ style: STYLE.stone, base: '#8a4f35', accent: '#ffad66', win: '#ffd28a' });
  const copper = facadeMaterial({ style: STYLE.plain, base: '#4f8a76', accent: '#ffcf80' });
  const body = new Mesh(new BoxGeometry(110, 20 * scale * 1.0, 18), brick);
  body.position.y = 10 * scale;
  g.add(body);
  const tower = new Mesh(new BoxGeometry(11, 32 * scale, 11), brick);
  tower.position.set(0, 16 * scale, 2);
  g.add(tower);
  const dome = new Mesh(new SphereGeometry(6.4, 16, 8, 0, Math.PI * 2, 0, Math.PI / 2), copper);
  dome.scale.y = 1.35;
  dome.position.set(0, 32 * scale, 2);
  g.add(dome);
  const finial = new Mesh(cyl(0.1, 0.6, 0, 3, 6), copper);
  finial.position.set(0, 32 * scale + 8.3, 2);
  g.add(finial);
  for (const side of [-1, 1]) {
    const t = new Mesh(new BoxGeometry(7, 25 * scale, 7), brick);
    t.position.set(side * 44, 12.5 * scale, 1);
    g.add(t);
    const d = new Mesh(new SphereGeometry(4, 12, 6, 0, Math.PI * 2, 0, Math.PI / 2), copper);
    d.scale.y = 1.3;
    d.position.set(side * 44, 25 * scale, 1);
    g.add(d);
  }
  // Clock faces glow warm.
  const face = new MeshBasicMaterial({ color: '#fff1c2' });
  for (let k = 0; k < 4; k++) {
    const c = new Mesh(new CircleGeometry(2.3, 16), face);
    const a = (k * Math.PI) / 2;
    c.position.set(Math.sin(a) * 5.6, 27 * scale, 2 + Math.cos(a) * 5.6);
    c.rotation.y = a;
    g.add(c);
  }
  return g;
}

function masjidNegara(scale) {
  const g = new Group();
  const stone = facadeMaterial({ style: STYLE.stone, base: '#cfc8b8', accent: '#9fe8dc', win: '#fff0c8' });
  const hall = new Mesh(cyl(36, 38, 0, 11, 18), stone);
  g.add(hall);
  // Folded-plate umbrella roof: 18-point star.
  const pos = [];
  const n = 36;
  for (let i = 0; i < n; i++) {
    const a0 = (i / n) * Math.PI * 2;
    const a1 = ((i + 1) / n) * Math.PI * 2;
    const r0 = i % 2 === 0 ? 44 : 37;
    const r1 = (i + 1) % 2 === 0 ? 44 : 37;
    const y0 = i % 2 === 0 ? 11 : 16;
    const y1 = (i + 1) % 2 === 0 ? 11 : 16;
    pos.push(0, 26, 0, Math.cos(a1) * r1, y1, Math.sin(a1) * r1, Math.cos(a0) * r0, y0, Math.sin(a0) * r0);
  }
  const roofGeo = new BufferGeometry();
  roofGeo.setAttribute('position', new Float32BufferAttribute(pos, 3));
  roofGeo.computeVertexNormals();
  g.add(new Mesh(roofGeo, facadeMaterial({ style: STYLE.plain, base: '#2d8c86', accent: '#36d2c0' })));
  const minaret = new Mesh(cyl(2.4, 3.3, 0, 60 * scale, 12), stone);
  minaret.position.set(62, 0, 24);
  g.add(minaret);
  const cap = new Mesh(cyl(0.2, 5.5, 60 * scale, 73 * scale, 12), facadeMaterial({ style: STYLE.plain, base: '#2d8c86', accent: '#36d2c0' }));
  cap.position.set(62, 0, 24);
  g.add(cap);
  const pool = new Mesh(new CircleGeometry(1, 24), waterMaterial());
  pool.rotation.x = -Math.PI / 2;
  pool.scale.set(28, 14, 1);
  pool.position.set(-10, 0.4, 62);
  g.add(pool);
  return g;
}

function generic(l) {
  const h = Math.max(20, l.h || 60);
  const m = new Mesh(new BoxGeometry(40, h, 40), facadeMaterial({ style: STYLE.office }));
  m.position.y = h / 2;
  const g = new Group();
  g.add(m);
  return g;
}

/** Footprint radius used for spacing (city blocks keep out of it). */
export function footprint(l) {
  if (l.kind === 'twin') return 190;
  if (l.kind === 'tower' && /118/.test(l.name)) return 150;
  if (l.kind === 'tower') return 245;
  if (l.kind === 'mosque') return 110;
  if (l.kind === 'park') return /botan|perdana|lake/i.test(l.name) ? 520 : 240;
  return 80;
}

/**
 * Builds the landmark meshes. Each one is nudged off the course if its
 * footprint would sit on the road, and turned to face the nearest road.
 * Returns [{ name, kind, group, x, z, top }].
 */
export function buildLandmarks(scene, data, route) {
  const out = [];
  const tmp = {};
  for (const l of data.landmarks || []) {
    if (l.kind === 'park') continue;
    let x = l.x;
    let z = -l.y;
    let group;
    let clear = 30;
    let top = l.h || 40;
    if (l.kind === 'twin') {
      group = petronas((l.h || 452) / 452);
      clear = 80;
    } else if (l.kind === 'tower' && /118/.test(l.name)) {
      group = merdeka118((l.h || 679) / 679);
      clear = 75;
    } else if (l.kind === 'tower') {
      group = klTower((l.h || 421) / 421);
      top = group.userData.top;
      clear = 60;
    } else if (l.kind === 'mosque') {
      group = masjidNegara((l.h || 73) / 73);
      clear = 70;
    } else if (/sultan|abdul samad/i.test(l.name)) {
      group = sultanAbdulSamad((l.h || 41) / 41);
      clear = 26;
    } else {
      group = generic(l);
    }
    // Face the nearest stretch of road and keep off it.
    const i = route.nearestIndex(x, z);
    route.at(route.d[i], tmp);
    const yaw = Math.atan2(-tmp.tz, tmp.tx);
    let away = { x: x - tmp.x, z: z - tmp.z };
    const len = Math.hypot(away.x, away.z) || 1;
    away = { x: away.x / len, z: away.z / len };
    for (let k = 0; k < 60; k++) {
      const c = Math.min(route.clearance(x, z), clearAlong(route, x, z, yaw, l));
      if (c >= clear) break;
      x += away.x * 4;
      z += away.z * 4;
    }
    group.position.set(x, 0, z);
    if (l.kind === 'building' || l.kind === 'mosque') group.rotation.y = yaw;
    scene.add(group);
    out.push({ name: l.name, kind: l.kind, group, x, z, top });
  }
  return out;
}

// For long buildings, also check the ends of the long axis.
function clearAlong(route, x, z, yaw, l) {
  if (l.kind !== 'building') return Infinity;
  const dx = Math.cos(yaw);
  const dz = -Math.sin(yaw);
  let best = Infinity;
  for (const s of [-55, -27, 27, 55]) best = Math.min(best, route.clearance(x + dx * s, z + dz * s) + 18);
  return best;
}

