// The course polyline in scene coordinates (X = east, Z = south, metres
// from the start line) with race-distance lookups.
import { segment } from './util.js';

export class Route {
  constructor(r, distance) {
    const n = r.x.length;
    this.n = n;
    this.distance = distance;
    this.x = Float64Array.from(r.x);
    this.z = Float64Array.from(r.y, (y) => -y);
    this.d = Float64Array.from(r.d);
    // Smoothed unit tangents per point (average of the adjacent segments).
    this.tx = new Float64Array(n);
    this.tz = new Float64Array(n);
    for (let i = 0; i < n; i++) {
      const a = Math.max(0, i - 1);
      const b = Math.min(n - 1, i + 1);
      let dx = this.x[b] - this.x[a];
      let dz = this.z[b] - this.z[a];
      const l = Math.hypot(dx, dz) || 1;
      this.tx[i] = dx / l;
      this.tz[i] = dz / l;
    }
    // Straight extensions: the start corral behind the line and the finish chute.
    this.startDir = this._dirBetween(0, 3);
    this.endDir = this._dirBetween(n - 4, n - 1);
  }

  _dirBetween(i, j) {
    const dx = this.x[j] - this.x[i];
    const dz = this.z[j] - this.z[i];
    const l = Math.hypot(dx, dz) || 1;
    return { x: dx / l, z: dz / l };
  }

  /**
   * Position + tangent at race distance d. Negative distances run back
   * into the start corral, distances past the finish continue straight on.
   * Writes into out = {x, z, tx, tz}.
   */
  at(d, out) {
    const n = this.n;
    if (d <= 0) {
      const s = this.startDir;
      out.x = this.x[0] + s.x * d;
      out.z = this.z[0] + s.z * d;
      out.tx = s.x;
      out.tz = s.z;
      return out;
    }
    if (d >= this.distance) {
      const e = this.endDir;
      const over = d - this.distance;
      out.x = this.x[n - 1] + e.x * over;
      out.z = this.z[n - 1] + e.z * over;
      out.tx = e.x;
      out.tz = e.z;
      return out;
    }
    const k = segment(this.d, d);
    const f = (d - this.d[k]) / (this.d[k + 1] - this.d[k] || 1);
    out.x = this.x[k] + (this.x[k + 1] - this.x[k]) * f;
    out.z = this.z[k] + (this.z[k + 1] - this.z[k]) * f;
    let tx = this.tx[k] + (this.tx[k + 1] - this.tx[k]) * f;
    let tz = this.tz[k] + (this.tz[k + 1] - this.tz[k]) * f;
    const l = Math.hypot(tx, tz) || 1;
    out.tx = tx / l;
    out.tz = tz / l;
    return out;
  }

  /** Bounding box of the course in scene coordinates. */
  bounds() {
    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    for (let i = 0; i < this.n; i++) {
      minX = Math.min(minX, this.x[i]);
      maxX = Math.max(maxX, this.x[i]);
      minZ = Math.min(minZ, this.z[i]);
      maxZ = Math.max(maxZ, this.z[i]);
    }
    return { minX, maxX, minZ, maxZ, cx: (minX + maxX) / 2, cz: (minZ + maxZ) / 2 };
  }

  /** Distance from (x, z) to the nearest route sample (coarse, for layout). */
  clearance(x, z, step = 1) {
    let best = Infinity;
    for (let i = 0; i < this.n; i += step) {
      const dx = this.x[i] - x;
      const dz = this.z[i] - z;
      const d = dx * dx + dz * dz;
      if (d < best) best = d;
    }
    return Math.sqrt(best);
  }

  /** Index of the nearest route sample to (x, z). */
  nearestIndex(x, z) {
    let best = Infinity;
    let bi = 0;
    for (let i = 0; i < this.n; i++) {
      const dx = this.x[i] - x;
      const dz = this.z[i] - z;
      const d = dx * dx + dz * dz;
      if (d < best) {
        best = d;
        bi = i;
      }
    }
    return bi;
  }
}
