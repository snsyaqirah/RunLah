# RunLah 3D scenes (three.js)

Source for `../assets/three/race3d.html`, the single self-contained page the
Flutter app shows in **Race3DScreen** (`lib/features/three/`). Everything
(three.js r186, OrbitControls, the scene code, CSS) is inlined, so the page
loads from `file:///android_asset`, iOS WKWebView file URLs and a Flutter-web
iframe with no network access.

```bash
npm install          # three 0.186.1 + esbuild 0.28.2 (exact versions)
npm run build        # -> ../assets/three/race3d.html (~655 KB minified)
npm run watch        # rebuild on change
```

## Modes

| mode      | camera                                                      | runners                                   |
|-----------|-------------------------------------------------------------|-------------------------------------------|
| `replay`  | whole course from the WSW, OrbitControls, optional chase cam | instanced glowing dots (≤ 3,000)          |
| `drone`   | hovering low over the FINISH arch at Dataran Merdeka         | capsule figures near the finish           |
| `flyover` | spline ~230 m up along the course, loops every ~52 s         | none (course preview, km/checkpoint pop-ups) |

Sky, light and window glow follow the time of day (gun 04:45, sunrise 07:10).

## Bridge

Flutter → page: `window.runlah.receive(json)` (or `postMessage` into the iframe)

- `{type:'init', data}` (built by `Race3DPayload.build` in Dart)
- `{type:'play'}`, `{type:'pause'}`, `{type:'seek', t}`, `{type:'speed', x}`
- `{type:'follow', id|null}`, `{type:'mode', mode, t?, speed?}`

Page → Flutter: `window.RunLah.postMessage(json)` (webview_flutter channel) or
`window.parent.postMessage(json, '*')` (web iframe, tagged with `?ch=`):

- `{type:'ready', webgl}`, repeated every second until `init` arrives
- `{type:'time', t, playing, mode, d?}`, ~4 Hz (`t` = flyover seconds in flyover)
- `{type:'pick', id|null}` when a runner (or empty space) is tapped
- `{type:'error', reason|message}`

Runner positions use exactly the same piecewise-linear model as
`RaceSim.distanceAt` (start delay + net time at each distance mark).

## Previewing without Flutter

```bash
# dump the real payload from the Dart side
cd .. && RUNLAH_DUMP_PAYLOAD=/tmp/payload.json flutter test test/three_test.dart --plain-name "dump payload"
cd three_src
node tools/preview.mjs --payload /tmp/payload.json --mode drone --t 5800 --bars --step 3 --out .preview/drone.html
google-chrome --headless=new --use-angle=swiftshader --enable-unsafe-swiftshader \
  --window-size=450,900 --virtual-time-budget=6000 --screenshot=/tmp/drone.png file://$PWD/.preview/drone.html
```

`--bars` draws Flutter's top/bottom overlay, `--step N` advances N frames
synchronously, `--follow you` turns on the chase cam, and `--cam x,y,z --target x,y,z`
places the camera. `window.__runlah` exposes the state, camera and world for
debugging.

## Files

- `src/main.js`: renderer, modes, render loop, picking, bridge wiring
- `src/env.js`: sky dome, lights, fog, ground grid, time of day
- `src/materials.js`: facade (procedural windows), dots, figures, ribbon, beams, water
- `src/landmarks.js`: Petronas Twin Towers, KL Tower, Merdeka 118, Sultan Abdul Samad Building, Masjid Negara
- `src/city.js`: street frontage + city blocks, parks, lakes, trees
- `src/course.js`: road, glowing route line, checkpoint beams
- `src/finish.js`: finish gantry, race clock, barriers, crowd, lamps, Dataran field + flag
- `src/runners.js`: kinematics, instanced dots / figures, rings, picking
- `src/rigs.js`: camera rigs (overview fit, chase, drone, flyover spline)
- `src/labels.js`: HTML labels pinned to 3D points
