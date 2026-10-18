// Sky, lights, fog and ground. Time of day drives everything: the gun goes
// at 04:45 in the dark and the sun comes up around 07:10 in KL.
import {
  BackSide,
  Color,
  DirectionalLight,
  FogExp2,
  HemisphereLight,
  Mesh,
  PlaneGeometry,
  ShaderMaterial,
  SphereGeometry,
  Vector2,
  Vector3,
} from 'three';
import { clamp, smoothstep } from './util.js';

/** Uniforms shared (by reference) by every custom material. */
export const U = {
  uTime: { value: 0 },
  uSunDir: { value: new Vector3(0, 1, 0) },
  uSunCol: { value: new Color() },
  uSkyAmb: { value: new Color() },
  uGroundAmb: { value: new Color() },
  uNight: { value: 1 },
  uDay: { value: 0 },
  uFogColor: { value: new Color() },
  uFogDensity: { value: 0.00008 },
  uHorizon: { value: new Color() },
  uTop: { value: new Color() },
  uViewport: { value: new Vector2(1, 1) },
  uDpr: { value: 1 },
};

/** GLSL helpers prepended to custom fragment shaders. */
export const GLSL_COMMON = /* glsl */ `
uniform float uTime;
uniform vec3 uSunDir;
uniform vec3 uSunCol;
uniform vec3 uSkyAmb;
uniform vec3 uGroundAmb;
uniform float uNight;
uniform float uDay;
uniform vec3 uFogColor;
uniform float uFogDensity;
uniform vec3 uHorizon;
uniform vec3 uTop;
float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}
vec3 applyFog(vec3 col, float dist) {
  float f = 1.0 - exp(-uFogDensity * uFogDensity * dist * dist);
  return mix(col, uFogColor, clamp(f, 0.0, 1.0));
}
`;

// Sky keyframes by sun elevation (degrees): zenith, horizon, below-horizon.
const MOON_DIR = new Vector3(-0.45, 0.75, 0.35).normalize();

const SKY = [
  [-40, '#02040b', '#070d1d', '#02040a'],
  [-18, '#040917', '#0e1733', '#03060d'],
  [-12, '#081430', '#1f2852', '#050912'],
  [-7, '#122650', '#4a3f6e', '#080d1a'],
  [-3, '#203f78', '#b0607a', '#0e1322'],
  [0, '#2f5a98', '#f08a5a', '#161b2a'],
  [5, '#3f74b6', '#ffc28a', '#22293a'],
  [14, '#4a86c8', '#cfe0ee', '#323a4a'],
  [40, '#3d7cc8', '#b5d3ee', '#3c4656'],
].map(([e, a, b, c]) => [e, new Color(a), new Color(b), new Color(c)]);

function skyAt(elev, top, hor, bot) {
  let i = 0;
  while (i < SKY.length - 2 && elev > SKY[i + 1][0]) i++;
  const a = SKY[i];
  const b = SKY[i + 1];
  const t = clamp((elev - a[0]) / (b[0] - a[0]), 0, 1);
  top.copy(a[1]).lerp(b[1], t);
  hor.copy(a[2]).lerp(b[2], t);
  bot.copy(a[3]).lerp(b[3], t);
}

export class Environment {
  constructor(scene) {
    this.scene = scene;
    this.elev = -30;

    // Sky dome (follows the camera).
    const skyMat = new ShaderMaterial({
      uniforms: {
        ...U,
        uBottom: { value: new Color() },
        uSunGlow: { value: 0 },
        uStars: { value: 1 },
        uSkySun: { value: new Vector3(0, 1, 0) },
        uSkySunCol: { value: new Color() },
      },
      vertexShader: /* glsl */ `
        varying vec3 vDir;
        void main() {
          vDir = normalize(position);
          vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
          gl_Position = p.xyww;
        }`,
      fragmentShader: GLSL_COMMON + /* glsl */ `
        uniform vec3 uBottom;
        uniform float uSunGlow;
        uniform float uStars;
        uniform vec3 uSkySun;
        uniform vec3 uSkySunCol;
        varying vec3 vDir;
        float hash13(vec3 p3) {
          p3 = fract(p3 * 0.1031);
          p3 += dot(p3, p3.zyx + 31.32);
          return fract((p3.x + p3.y) * p3.z);
        }
        void main() {
          vec3 d = normalize(vDir);
          float h = d.y;
          vec3 col = mix(uHorizon, uTop, pow(smoothstep(-0.02, 0.6, h), 0.65));
          col = mix(col, uBottom, smoothstep(0.0, -0.12, h));
          float sd = max(dot(d, uSkySun), 0.0);
          vec2 hd = normalize(d.xz + 1e-5);
          vec2 hs = normalize(uSkySun.xz + 1e-5);
          float az = max(dot(hd, hs), 0.0);
          // Warm band on the horizon toward the sun, then the sun's glow and disc.
          col += uSkySunCol * pow(az, 4.0) * exp(-abs(h - 0.02) * 9.0) * 0.55 * uSunGlow;
          col += uSkySunCol * (pow(sd, 10.0) * 0.35 + pow(sd, 120.0) * 0.8) * uSunGlow;
          col += vec3(1.0, 0.92, 0.75) * smoothstep(0.99955, 0.9998, sd) * step(-0.01, uSkySun.y) * 3.0;
          // Stars.
          vec3 p = d * 420.0;
          vec3 cell = floor(p);
          float r = hash13(cell);
          float star = step(0.9965, r) * smoothstep(0.42, 0.0, length(fract(p) - 0.5));
          star *= 0.55 + 0.45 * sin(uTime * (1.5 + r * 3.0) + r * 40.0);
          col += vec3(0.85, 0.9, 1.0) * star * uStars * smoothstep(0.02, 0.25, h);
          gl_FragColor = vec4(col, 1.0);
          #include <colorspace_fragment>
        }`,
      side: BackSide,
      depthWrite: false,
      depthTest: false,
      fog: false,
    });
    this.skyMat = skyMat;
    this.sky = new Mesh(new SphereGeometry(1000, 32, 16), skyMat);
    this.sky.renderOrder = -10;
    this.sky.frustumCulled = false;
    scene.add(this.sky);

    this.hemi = new HemisphereLight('#334', '#111', 0.6);
    scene.add(this.hemi);
    this.sun = new DirectionalLight('#fff', 1);
    scene.add(this.sun);
    scene.add(this.sun.target);

    scene.fog = new FogExp2('#000', U.uFogDensity.value);

    // Ground with a faint glowing street grid.
    const groundMat = new ShaderMaterial({
      uniforms: { ...U, uCentre: { value: new Vector2() } },
      vertexShader: /* glsl */ `
        varying vec3 vW;
        void main() {
          vec4 w = modelMatrix * vec4(position, 1.0);
          vW = w.xyz;
          gl_Position = projectionMatrix * viewMatrix * w;
        }`,
      fragmentShader: GLSL_COMMON + /* glsl */ `
        uniform vec2 uCentre;
        varying vec3 vW;
        float gridLine(vec2 p, float size, float width) {
          vec2 q = p / size;
          vec2 g = abs(fract(q - 0.5) - 0.5) / (fwidth(q) * width);
          return 1.0 - min(min(g.x, g.y), 1.0);
        }
        void main() {
          float dist = length(vW - cameraPosition);
          vec3 night = vec3(0.0045, 0.0065, 0.014);
          vec3 day = vec3(0.07, 0.08, 0.072);
          vec3 col = mix(night, day, uDay);
          float fadeNear = 1.0 - smoothstep(1500.0, 9000.0, dist);
          float minor = gridLine(vW.xz, 100.0, 1.2) * fadeNear;
          float major = gridLine(vW.xz, 1000.0, 1.6) * (1.0 - smoothstep(4000.0, 16000.0, dist));
          vec3 gridCol = mix(vec3(0.02, 0.06, 0.16), vec3(0.09, 0.1, 0.11), uDay);
          col += gridCol * (minor * 0.3 + major * 0.55) * (0.5 + 0.5 * uNight);
          // Faint sodium-light haze under the city.
          float r = length(vW.xz - uCentre);
          col += vec3(0.016, 0.009, 0.006) * exp(-r * r / 1.2e7) * uNight;
          col = applyFog(col, dist);
          gl_FragColor = vec4(col, 1.0);
          #include <colorspace_fragment>
        }`,
      fog: false,
    });
    this.groundMat = groundMat;
    this.ground = new Mesh(new PlaneGeometry(60000, 60000), groundMat);
    this.ground.rotation.x = -Math.PI / 2;
    this.ground.renderOrder = -5;
    scene.add(this.ground);

    this._top = new Color();
    this._hor = new Color();
    this._bot = new Color();
    this._tmp = new Color();
  }

  setCentre(x, z) {
    this.groundMat.uniforms.uCentre.value.set(x, z);
  }

  /**
   * Updates sky, lights and fog for a time of day.
   * @param sod seconds of the local day
   * @param sunriseSod sunrise, seconds of the day
   */
  setTimeOfDay(sod, sunriseSod) {
    // KL is near the equator: the sun climbs ~15 degrees an hour, rising in the ESE.
    const elev = clamp((sod - sunriseSod) / 240, -40, 70);
    this.elev = elev;
    const er = (elev * Math.PI) / 180;
    const az = (102 * Math.PI) / 180;
    const sky = this.skyMat.uniforms;
    const sunDir = sky.uSkySun.value.set(Math.cos(er) * Math.sin(az), Math.sin(er), Math.cos(er) * Math.cos(az)).normalize();

    skyAt(elev, this._top, this._hor, this._bot);
    U.uTop.value.copy(this._top);
    U.uHorizon.value.copy(this._hor);
    sky.uBottom.value.copy(this._bot);

    const night = 1 - smoothstep(-9, 3, elev);
    const day = smoothstep(-8, 18, elev);
    U.uNight.value = night;
    U.uDay.value = day;
    sky.uStars.value = 1 - smoothstep(-14, -5, elev);
    sky.uSunGlow.value = smoothstep(-16, -2, elev) * (1 - smoothstep(25, 50, elev) * 0.6);

    // Sun colour: deep orange at the horizon, white higher up.
    const warm = smoothstep(18, -2, elev);
    const sunCol = sky.uSkySunCol.value.setRGB(1.0, 0.86 - 0.32 * warm, 0.7 - 0.45 * warm);

    // Key light: the sun once it is up, a cool moon before that.
    const sunI = smoothstep(-3, 12, elev);
    const moonI = (1 - sunI) * 0.5;
    this.sun.color.copy(sunCol).multiplyScalar(sunI * 2.4).add(this._tmp.setRGB(0.55, 0.65, 1.0).multiplyScalar(moonI));
    this.sun.intensity = 1;
    const keyDir = sunI > 0.05 ? sunDir : MOON_DIR;
    this.sun.position.copy(keyDir).multiplyScalar(1000);
    U.uSunDir.value.copy(keyDir);
    U.uSunCol.value.copy(this.sun.color).multiplyScalar(0.55);

    const skyAmb = this._tmp.copy(this._top).lerp(this._hor, 0.35);
    U.uSkyAmb.value.copy(skyAmb).multiplyScalar(0.9 + 0.4 * day).addScalar(0.03);
    U.uGroundAmb.value.copy(this._bot).multiplyScalar(0.8).addScalar(0.015);
    this.hemi.color.copy(U.uSkyAmb.value).multiplyScalar(2.2);
    this.hemi.groundColor.copy(U.uGroundAmb.value).multiplyScalar(2.0);
    this.hemi.intensity = 1;

    // Haze: thin, and bluer than the horizon glow so daylight doesn't turn orange.
    const fog = U.uFogColor.value.copy(this._hor).lerp(this._top, 0.5 + 0.25 * day).multiplyScalar(0.85 - 0.1 * day);
    U.uFogDensity.value = 0.00007 - 0.000042 * day;
    this.scene.fog.color.copy(fog);
    this.scene.fog.density = U.uFogDensity.value;
  }

  /** Call every frame (before rendering) so the dome stays around the camera. */
  update(camera) {
    this.sky.position.copy(camera.position);
  }
}
