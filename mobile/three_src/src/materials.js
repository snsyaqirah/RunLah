// Custom shader materials. All of them share the lighting/fog/time uniforms
// in env.U, so one setTimeOfDay() call relights the whole city.
import { AdditiveBlending, Color, DoubleSide, ShaderMaterial } from 'three';
import { GLSL_COMMON, U } from './env.js';

export const STYLE = { office: 0, petronas: 1, glass: 2, lit: 3, stone: 4, plain: 5 };

/**
 * Building facade: lambert light + procedural windows that light up at
 * night. Works for plain meshes (geometry in metres) and for instanced unit
 * boxes (window grid follows each instance's scale).
 */
export function facadeMaterial({ style = STYLE.office, base = '#2a3446', win = '#ffd9a0', accent = '#9fc2ff', density = 0.45, seed = 0, floor = 3.6, bay = 3.2, height = 100 } = {}) {
  return new ShaderMaterial({
    uniforms: {
      ...U,
      uBase: { value: new Color(base) },
      uWin: { value: new Color(win) },
      uAccent: { value: new Color(accent) },
      uDensity: { value: density },
      uStyle: { value: style },
      uSeed: { value: seed },
      uFloor: { value: floor },
      uBay: { value: bay },
      uHeight: { value: height },
    },
    vertexShader: /* glsl */ `
      uniform float uSeed;
      varying vec3 vObj;
      varying vec3 vObjN;
      varying vec3 vN;
      varying vec3 vW;
      varying float vSeed;
      varying float vH;
      void main() {
        mat4 m = modelMatrix;
        vec3 obj = position;
        float seed = uSeed;
        float h = 0.0;
        #ifdef USE_INSTANCING
          vec3 sc = vec3(length(instanceMatrix[0].xyz), length(instanceMatrix[1].xyz), length(instanceMatrix[2].xyz));
          obj = position * sc;
          m = modelMatrix * instanceMatrix;
          seed = fract(instanceMatrix[3].x * 0.0137 + instanceMatrix[3].z * 0.0291) * 100.0;
          h = sc.y;
        #endif
        vObj = obj;
        vObjN = normal;
        vSeed = seed;
        vH = h;
        vec4 w = m * vec4(position, 1.0);
        vW = w.xyz;
        vN = normalize(mat3(m) * normal);
        gl_Position = projectionMatrix * viewMatrix * w;
      }`,
    fragmentShader: GLSL_COMMON + /* glsl */ `
      uniform vec3 uBase;
      uniform vec3 uWin;
      uniform vec3 uAccent;
      uniform float uDensity;
      uniform float uStyle;
      uniform float uFloor;
      uniform float uBay;
      uniform float uHeight;
      varying vec3 vObj;
      varying vec3 vObjN;
      varying vec3 vN;
      varying vec3 vW;
      varying float vSeed;
      varying float vH;
      void main() {
        vec3 n = normalize(vN);
        vec3 v = normalize(cameraPosition - vW);
        float diff = max(dot(n, uSunDir), 0.0);
        vec3 amb = mix(uGroundAmb, uSkyAmb, n.y * 0.5 + 0.5);
        vec3 col = uBase * (amb * 1.6 + uSunCol * diff * 1.5);
        float wall = 1.0 - smoothstep(0.55, 0.85, abs(vObjN.y));
        float u = abs(vObjN.x) > abs(vObjN.z) ? vObj.z : vObj.x;
        float y = vObj.y;
        float fres = pow(1.0 - max(dot(n, v), 0.0), 3.0);
        int style = int(uStyle + 0.5);

        if (style == 0) {
          // Office block: grid of windows, some lit.
          vec2 cell = vec2(u / uBay, y / uFloor);
          vec2 f = fract(cell);
          vec2 id = floor(cell);
          float win = step(0.16, f.x) * step(f.x, 0.84) * step(0.28, f.y) * step(f.y, 0.86);
          float lit = step(1.0 - uDensity, hash12(id + vSeed * 7.0));
          float warm = hash12(id * 1.37 + vSeed);
          vec3 wc = mix(uWin, vec3(0.75, 0.88, 1.0), step(0.7, warm)) * (0.6 + 0.6 * warm);
          float top = 1.0 - step(0.0, y - (vH > 0.0 ? vH : 1e5) + 1.5);
          col = mix(col, col * 0.55 + uSkyAmb * 0.25 * fres, win * wall * 0.6);
          col += wc * win * lit * wall * top * uNight * 1.25;
          col += uWin * win * wall * (1.0 - uNight) * fres * 0.08;
        } else if (style == 1) {
          // Petronas: steel ribs and floor bands, floodlit silver at night.
          float ang = atan(vObj.z, vObj.x);
          float ribs = smoothstep(0.75, 1.0, abs(sin(ang * 16.0)));
          float bands = smoothstep(0.55, 0.9, fract(y / 4.0));
          float steel = 0.55 + 0.25 * ribs + 0.2 * bands;
          col = uBase * (amb * 1.8 + uSunCol * diff * 2.2) * steel + vec3(0.9) * fres * uDay * 0.25;
          float flood = (0.55 + 0.45 * bands) * (0.75 + 0.25 * ribs) * (0.55 + 0.45 * smoothstep(0.0, uHeight, y));
          col += uAccent * flood * uNight * 1.05;
          col += uWin * step(0.65, hash12(floor(vec2(ang * 30.0, y / 4.0)) + 3.0)) * bands * uNight * 0.35;
        } else if (style == 2) {
          // Glass tower with diamond facets (Merdeka 118).
          float a = fract((u + y * 0.55) / 14.0);
          float b = fract((u - y * 0.55) / 14.0);
          float lines = smoothstep(0.03, 0.0, min(min(a, 1.0 - a), min(b, 1.0 - b)));
          vec3 glass = mix(uBase, uSkyAmb * 1.3 + uHorizon * 0.4, fres * 0.8);
          col = glass * (amb * 1.4 + uSunCol * diff * 1.6) + uSunCol * pow(max(dot(reflect(-v, n), uSunDir), 0.0), 40.0) * 0.6;
          col += uAccent * lines * (0.25 + 0.75 * uNight) * 0.9;
          vec2 cell = vec2(u / 3.0, y / 4.0);
          float lit = step(0.86, hash12(floor(cell) + 11.0)) * step(0.3, fract(cell.y)) ;
          col += uWin * lit * wall * uNight * 0.7;
        } else if (style == 3) {
          // Floodlit concrete (KL Tower shaft): colour wash from below.
          float g = smoothstep(0.0, uHeight, y);
          col += uAccent * (0.35 + 0.65 * g) * uNight * 0.85;
          col += uAccent * fres * 0.3 * uNight;
        } else if (style == 4) {
          // Heritage stone: warm uplights and glowing arches.
          vec2 cell = vec2(u / 4.0, y / 6.0);
          vec2 f = fract(cell);
          float arch = step(0.25, f.x) * step(f.x, 0.75) * step(0.15, f.y) * step(f.y, 0.55 + 0.25 * sqrt(max(0.0, 1.0 - pow((f.x - 0.5) * 4.0, 2.0))));
          col += uAccent * exp(-y / 14.0) * uNight * 0.9;
          col += uWin * arch * wall * uNight * 0.9 * step(y, 30.0);
        } else {
          // Plain: just lit, with an accent glow at night.
          col += uAccent * uNight * 0.35;
        }
        col = applyFog(col, length(vW - cameraPosition));
        gl_FragColor = vec4(col, 1.0);
        #include <colorspace_fragment>
      }`,
  });
}

/**
 * Camera-facing glowing dots for instanced runners. The quad is sized in
 * screen pixels from a world size, clamped so dots stay visible from 8 km
 * away and don't balloon when you fly close. Instance scale = size factor.
 */
export function dotMaterial({ worldSize = 7, minPx = 2.2, maxPx = 9, ring = false } = {}) {
  return new ShaderMaterial({
    uniforms: {
      ...U,
      uWorld: { value: worldSize },
      uMinPx: { value: minPx },
      uMaxPx: { value: maxPx },
    },
    vertexShader: /* glsl */ `
      uniform vec2 uViewport;
      uniform float uDpr;
      uniform float uWorld;
      uniform float uMinPx;
      uniform float uMaxPx;
      varying vec2 vUv;
      varying vec3 vColor;
      void main() {
        float s = length(instanceMatrix[0].xyz);
        vec4 mv = modelViewMatrix * vec4(instanceMatrix[3].xyz, 1.0);
        float px = uWorld * projectionMatrix[1][1] * uViewport.y * 0.5 / max(1.0, -mv.z);
        px = clamp(px, uMinPx * uDpr, uMaxPx * uDpr) * s;
        vec4 clip = projectionMatrix * mv;
        clip.xy += position.xy * px * 2.0 / uViewport * clip.w;
        gl_Position = s < 0.001 ? vec4(2.0, 2.0, 2.0, 1.0) : clip;
        vUv = position.xy * 2.0;
        #ifdef USE_INSTANCING_COLOR
          vColor = instanceColor;
        #else
          vColor = vec3(1.0);
        #endif
      }`,
    fragmentShader: GLSL_COMMON + (ring
      ? /* glsl */ `
      varying vec2 vUv;
      varying vec3 vColor;
      void main() {
        float r = length(vUv);
        float a = 0.0;
        for (int i = 0; i < 2; i++) {
          float ph = fract(uTime * 0.6 + float(i) * 0.5);
          float rr = 0.25 + ph * 0.75;
          a += smoothstep(0.09, 0.0, abs(r - rr)) * (1.0 - ph);
        }
        a += smoothstep(0.3, 0.22, abs(r - 0.32)) * 0.0;
        a *= step(r, 1.0);
        gl_FragColor = vec4(vColor * a, 1.0);
        #include <colorspace_fragment>
      }`
      : /* glsl */ `
      varying vec2 vUv;
      varying vec3 vColor;
      void main() {
        float r = length(vUv);
        if (r > 1.0) discard;
        float core = smoothstep(0.42, 0.24, r);
        float glow = exp(-r * r * 6.0);
        vec3 c = vColor * (glow * 0.85 + core * 0.9) + vec3(1.0) * core * 0.35 * dot(vColor, vec3(0.33));
        gl_FragColor = vec4(c, 1.0);
        #include <colorspace_fragment>
      }`),
    blending: AdditiveBlending,
    depthWrite: false,
    transparent: true,
  });
}

/** Lambert + rim + a little self-light for the drone-view runner figures. */
export function figureMaterial() {
  return new ShaderMaterial({
    uniforms: { ...U },
    vertexShader: /* glsl */ `
      varying vec3 vN;
      varying vec3 vW;
      varying vec3 vColor;
      varying float vY;
      void main() {
        mat4 m = modelMatrix * instanceMatrix;
        vec4 w = m * vec4(position, 1.0);
        vW = w.xyz;
        vN = normalize(mat3(m) * normal);
        vY = position.y;
        #ifdef USE_INSTANCING_COLOR
          vColor = instanceColor;
        #else
          vColor = vec3(1.0);
        #endif
        gl_Position = projectionMatrix * viewMatrix * w;
      }`,
    fragmentShader: GLSL_COMMON + /* glsl */ `
      varying vec3 vN;
      varying vec3 vW;
      varying vec3 vColor;
      varying float vY;
      void main() {
        vec3 n = normalize(vN);
        vec3 v = normalize(cameraPosition - vW);
        float diff = max(dot(n, uSunDir), 0.0);
        vec3 amb = mix(uGroundAmb, uSkyAmb, n.y * 0.5 + 0.5);
        vec3 c = vColor;
        // Head and legs a touch darker than the shirt.
        float head = step(1.42, vY);
        float legs = 1.0 - step(0.62, vY);
        c = mix(c, vec3(0.86, 0.68, 0.55), head * 0.85);
        c = mix(c, c * 0.35, legs * 0.6);
        vec3 col = c * (amb * 2.0 + uSunCol * diff * 2.2 + 0.45);
        float rim = pow(1.0 - max(dot(n, v), 0.0), 2.5);
        col += vColor * rim * 0.6;
        col = applyFog(col, length(vW - cameraPosition));
        gl_FragColor = vec4(col, 1.0);
        #include <colorspace_fragment>
      }`,
  });
}

/** Soft dark blob under each figure (cheap contact shadow). */
export function blobMaterial() {
  return new ShaderMaterial({
    vertexShader: /* glsl */ `
      varying vec2 vUv;
      void main() {
        vUv = uv * 2.0 - 1.0;
        gl_Position = projectionMatrix * viewMatrix * modelMatrix * instanceMatrix * vec4(position, 1.0);
      }`,
    fragmentShader: /* glsl */ `
      varying vec2 vUv;
      void main() {
        float r = length(vUv);
        gl_FragColor = vec4(0.0, 0.0, 0.0, 0.45 * smoothstep(1.0, 0.2, r));
      }`,
    transparent: true,
    depthWrite: false,
    polygonOffset: true,
    polygonOffsetFactor: -2,
    polygonOffsetUnits: -2,
  });
}

/**
 * The course as a glowing ribbon. Geometry stores the centre line plus a
 * side (-1/+1) and the 2D normal, so width can change per mode.
 * Behind the focus runner (uProgress) the line turns amber.
 */
export function ribbonMaterial({ halfWidth = 40, core = 0.18, ahead = '#3fa9ff', done = '#ffb547', y = 1.2 } = {}) {
  return new ShaderMaterial({
    uniforms: {
      ...U,
      uHalf: { value: halfWidth },
      uCore: { value: core },
      uAhead: { value: new Color(ahead) },
      uDone: { value: new Color(done) },
      uProgress: { value: -1 },
      uY: { value: y },
      uGlow: { value: 1 },
      uFlow: { value: 1 },
    },
    vertexShader: /* glsl */ `
      attribute float aSide;
      attribute float aDist;
      attribute vec2 aNormal;
      uniform float uHalf;
      uniform float uY;
      varying float vSide;
      varying float vDist;
      varying vec3 vW;
      void main() {
        vec3 p = position + vec3(aNormal.x, 0.0, aNormal.y) * aSide * uHalf;
        p.y = uY;
        vec4 w = modelMatrix * vec4(p, 1.0);
        vW = w.xyz;
        vSide = aSide;
        vDist = aDist;
        gl_Position = projectionMatrix * viewMatrix * w;
      }`,
    fragmentShader: GLSL_COMMON + /* glsl */ `
      uniform float uCore;
      uniform vec3 uAhead;
      uniform vec3 uDone;
      uniform float uProgress;
      uniform float uGlow;
      uniform float uFlow;
      varying float vSide;
      varying float vDist;
      varying vec3 vW;
      void main() {
        float a = abs(vSide);
        float core = smoothstep(uCore, uCore * 0.45, a);
        float glow = exp(-a * a * 5.0) * uGlow;
        vec3 base = vDist < uProgress ? uDone : uAhead;
        float pulse = pow(fract(vDist / 600.0 - uTime * 0.35), 12.0) * uFlow;
        vec3 col = base * (core * 1.25 + glow * 0.45) + vec3(1.0) * core * pulse * 0.6;
        float dist = length(vW - cameraPosition);
        float f = 1.0 - exp(-uFogDensity * uFogDensity * dist * dist);
        col *= 1.0 - clamp(f, 0.0, 1.0) * 0.85;
        col *= 0.75 + 0.25 * uNight;
        gl_FragColor = vec4(col, 1.0);
        #include <colorspace_fragment>
      }`,
    blending: AdditiveBlending,
    depthWrite: false,
    transparent: true,
    side: DoubleSide,
  });
}

/** Asphalt road surface along the course with edge lines. */
export function roadMaterial({ halfWidth = 7 } = {}) {
  return new ShaderMaterial({
    uniforms: { ...U, uHalf: { value: halfWidth }, uY: { value: 0.15 } },
    vertexShader: /* glsl */ `
      attribute float aSide;
      attribute float aDist;
      attribute vec2 aNormal;
      uniform float uHalf;
      uniform float uY;
      varying float vSide;
      varying float vDist;
      varying vec3 vW;
      void main() {
        vec3 p = position + vec3(aNormal.x, 0.0, aNormal.y) * aSide * uHalf;
        p.y = uY;
        vec4 w = modelMatrix * vec4(p, 1.0);
        vW = w.xyz;
        vSide = aSide;
        vDist = aDist;
        gl_Position = projectionMatrix * viewMatrix * w;
      }`,
    fragmentShader: GLSL_COMMON + /* glsl */ `
      uniform float uHalf;
      varying float vSide;
      varying float vDist;
      varying vec3 vW;
      void main() {
        float a = abs(vSide) * uHalf;
        vec3 asphalt = mix(vec3(0.035, 0.04, 0.055), vec3(0.16, 0.165, 0.175), uDay);
        asphalt *= 0.9 + 0.1 * hash12(floor(vW.xz * 2.0));
        float edge = smoothstep(0.18, 0.05, abs(a - (uHalf - 0.7)));
        float dash = step(0.5, fract(vDist / 9.0)) * smoothstep(0.12, 0.04, abs(vSide * uHalf));
        vec3 paint = mix(vec3(0.55, 0.55, 0.5), vec3(0.85), uDay);
        vec3 col = asphalt + paint * (edge * 0.6 + dash * 0.25);
        col += vec3(0.05, 0.035, 0.015) * uNight;
        col = applyFog(col, length(vW - cameraPosition));
        gl_FragColor = vec4(col, 1.0);
        #include <colorspace_fragment>
      }`,
    polygonOffset: true,
    polygonOffsetFactor: -1,
    polygonOffsetUnits: -1,
  });
}

/** Vertical light beam for checkpoints (fades upward, brighter in the middle). */
export function beamMaterial(color) {
  return new ShaderMaterial({
    uniforms: { ...U, uColor: { value: new Color(color) } },
    vertexShader: /* glsl */ `
      varying vec2 vUv;
      varying vec3 vN;
      varying vec3 vW;
      void main() {
        vUv = uv;
        vec4 w = modelMatrix * vec4(position, 1.0);
        vW = w.xyz;
        vN = normalize(mat3(modelMatrix) * normal);
        gl_Position = projectionMatrix * viewMatrix * w;
      }`,
    fragmentShader: GLSL_COMMON + /* glsl */ `
      uniform vec3 uColor;
      varying vec2 vUv;
      varying vec3 vN;
      varying vec3 vW;
      void main() {
        vec3 v = normalize(cameraPosition - vW);
        float facing = abs(dot(normalize(vN), v));
        float a = pow(1.0 - vUv.y, 1.6) * (0.15 + 0.85 * pow(facing, 2.0));
        a *= 0.55 + 0.45 * uNight;
        gl_FragColor = vec4(uColor * a * 0.9, 1.0);
        #include <colorspace_fragment>
      }`,
    blending: AdditiveBlending,
    depthWrite: false,
    transparent: true,
    side: DoubleSide,
  });
}

/** Flat additive ring on the ground (checkpoints, focus runner). */
export function groundRingMaterial(color, { pulse = false } = {}) {
  return new ShaderMaterial({
    uniforms: { ...U, uColor: { value: new Color(color) }, uPulse: { value: pulse ? 1 : 0 } },
    vertexShader: /* glsl */ `
      varying vec2 vUv;
      void main() {
        vUv = uv * 2.0 - 1.0;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }`,
    fragmentShader: GLSL_COMMON + /* glsl */ `
      uniform vec3 uColor;
      uniform float uPulse;
      varying vec2 vUv;
      void main() {
        float r = length(vUv);
        float ring = smoothstep(0.1, 0.0, abs(r - 0.8)) + smoothstep(0.5, 0.0, r) * 0.25;
        if (uPulse > 0.5) {
          float ph = fract(uTime * 0.7);
          ring += smoothstep(0.08, 0.0, abs(r - ph)) * (1.0 - ph) * 1.5;
        }
        ring *= step(r, 1.0);
        gl_FragColor = vec4(uColor * ring, 1.0);
        #include <colorspace_fragment>
      }`,
    blending: AdditiveBlending,
    depthWrite: false,
    transparent: true,
  });
}

/** Water that mirrors the sky colours. */
export function waterMaterial() {
  return new ShaderMaterial({
    uniforms: { ...U },
    vertexShader: /* glsl */ `
      varying vec3 vW;
      void main() {
        vec4 w = modelMatrix * vec4(position, 1.0);
        vW = w.xyz;
        gl_Position = projectionMatrix * viewMatrix * w;
      }`,
    fragmentShader: GLSL_COMMON + /* glsl */ `
      varying vec3 vW;
      void main() {
        vec3 v = normalize(cameraPosition - vW);
        float fres = pow(1.0 - max(v.y, 0.0), 3.0);
        vec3 col = mix(uTop, uHorizon, fres) * 0.55 + vec3(0.0, 0.03, 0.05);
        float ripple = hash12(floor(vW.xz * 0.5 + vec2(uTime * 0.3, 0.0)));
        col += vec3(0.5, 0.45, 0.35) * step(0.985, ripple) * uNight * 0.5;
        col = applyFog(col, length(vW - cameraPosition));
        gl_FragColor = vec4(col, 1.0);
        #include <colorspace_fragment>
      }`,
    polygonOffset: true,
    polygonOffsetFactor: -2,
    polygonOffsetUnits: -2,
  });
}
