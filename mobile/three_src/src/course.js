// The course: road surface, glowing route ribbon, checkpoint beams.
import { BufferGeometry, CylinderGeometry, Float32BufferAttribute, Group, Mesh, PlaneGeometry, Uint32BufferAttribute } from 'three';
import { beamMaterial, groundRingMaterial, ribbonMaterial, roadMaterial } from './materials.js';

/** Ribbon geometry along race distances [from, to] sampled every `step` metres. */
function ribbonGeometry(route, from, to, step) {
  const pos = [];
  const side = [];
  const dist = [];
  const nrm = [];
  const tmp = {};
  const ds = [];
  for (let d = from; d < to; d += step) ds.push(d);
  ds.push(to);
  for (const d of ds) {
    route.at(d, tmp);
    for (const s of [-1, 1]) {
      pos.push(tmp.x, 0, tmp.z);
      side.push(s);
      dist.push(d);
      nrm.push(-tmp.tz, tmp.tx);
    }
  }
  const idx = [];
  for (let i = 0; i < ds.length - 1; i++) {
    const l0 = i * 2;
    const r0 = l0 + 1;
    const l1 = l0 + 2;
    const r1 = l0 + 3;
    idx.push(l0, r0, l1, r0, r1, l1);
  }
  const g = new BufferGeometry();
  g.setAttribute('position', new Float32BufferAttribute(pos, 3));
  g.setAttribute('aSide', new Float32BufferAttribute(side, 1));
  g.setAttribute('aDist', new Float32BufferAttribute(dist, 1));
  g.setAttribute('aNormal', new Float32BufferAttribute(nrm, 2));
  g.setIndex(new Uint32BufferAttribute(idx, 1));
  return g;
}

export class Course {
  constructor(scene, data, route, strings) {
    this.route = route;
    // Road: course + start corral behind the line + finish chute.
    this.roadMat = roadMaterial({ halfWidth: 7 });
    this.road = new Mesh(ribbonGeometry(route, -1300, route.distance + 90, 8), this.roadMat);
    this.road.frustumCulled = false;
    this.road.renderOrder = -3;
    scene.add(this.road);

    // Glowing route line (wide glow in the overview, a painted blue line up close).
    this.glowMat = ribbonMaterial({ halfWidth: 42, core: 0.16 });
    this.glow = new Mesh(ribbonGeometry(route, 0, route.distance, 10), this.glowMat);
    this.glow.frustumCulled = false;
    this.glow.renderOrder = 2;
    scene.add(this.glow);

    // Checkpoint beams + ground rings. Start and finish share Dataran Merdeka.
    this.beams = new Group();
    this.cps = [];
    const placed = [];
    for (const c of data.checkpoints || []) {
      const x = c.x;
      const z = -c.y;
      const isEnd = c.type === 'start' || c.type === 'finish';
      const prev = placed.find((p) => Math.hypot(p.x - x, p.z - z) < 40);
      if (prev) {
        prev.label = `${strings.start} · ${strings.finish}`;
        prev.end = true;
        continue;
      }
      const color = isEnd ? '#ffb547' : '#55c8ff';
      const h = isEnd ? 260 : 150;
      const beamGeo = new CylinderGeometry(isEnd ? 5 : 3.2, isEnd ? 5 : 3.2, 1, 14, 1, true);
      beamGeo.translate(0, 0.5, 0);
      const beam = new Mesh(beamGeo, beamMaterial(color));
      beam.scale.y = h;
      beam.position.set(x, 0, z);
      beam.renderOrder = 3;
      this.beams.add(beam);
      const ring = new Mesh(new PlaneGeometry(1, 1), groundRingMaterial(color));
      ring.rotation.x = -Math.PI / 2;
      ring.scale.setScalar(isEnd ? 90 : 60);
      ring.position.set(x, 1.6, z);
      ring.renderOrder = 3;
      this.beams.add(ring);
      const label = isEnd ? (c.type === 'start' ? strings.start : strings.finish) : c.label;
      const p = { x, z, h, label, name: c.name, d: c.d, end: isEnd, beam, ring };
      placed.push(p);
    }
    this.cps = placed;
    scene.add(this.beams);
    this.checkpoints = data.checkpoints || [];
  }

  /** Width/look per mode. */
  setMode(mode) {
    const u = this.glowMat.uniforms;
    if (mode === 'drone') {
      // Painted blue race line on the road.
      u.uHalf.value = 0.35;
      u.uCore.value = 0.95;
      u.uGlow.value = 0.0;
      u.uY.value = 0.2;
      u.uFlow.value = 0.0;
      this.beams.visible = false;
    } else {
      u.uHalf.value = 42;
      u.uCore.value = 0.16;
      u.uGlow.value = 1;
      u.uY.value = 1.2;
      u.uFlow.value = 1;
      this.beams.visible = true;
    }
  }

  setProgress(d) {
    this.glowMat.uniforms.uProgress.value = d;
  }
}
