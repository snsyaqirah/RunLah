// Writes a preview page: the built race3d.html plus an injected init message,
// for checking the scene in a browser / headless Chrome without Flutter.
//
//   node tools/preview.mjs --payload payload.json --mode drone --t 5790 --out .preview/drone.html [--bars] [--follow you]
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => {
    if (a.startsWith('--')) acc.push([a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true]);
    return acc;
  }, []),
);
if (!args.payload) {
  console.error('usage: node tools/preview.mjs --payload payload.json [--mode replay|drone|flyover] [--t seconds] [--follow you|<id>] [--play] [--bars] --out file.html');
  process.exit(1);
}
const data = JSON.parse(readFileSync(resolve(args.payload), 'utf8'));
if (args.mode) data.mode = args.mode;
if (args.t != null) data.t0 = Number(args.t);
if (args.follow) data.followId = args.follow === 'you' ? data.youId : Number(args.follow);
data.playing = !!args.play;
data.insets = args.bars ? { top: 118, bottom: 262 } : { top: 0, bottom: 0 };
data.strings = { start: 'START', finish: 'FINISH', km: 'KM', you: 'You', event: 'KL City Night-to-Dawn Run 2026', ...(data.strings || {}) };

const html = readFileSync(resolve(here, '../../assets/three/race3d.html'), 'utf8');
const bars = args.bars
  ? `<div style="position:fixed;left:0;right:0;top:0;height:118px;background:linear-gradient(#0b1220ee,#0b122000);pointer-events:none"></div>
     <div style="position:fixed;left:0;right:0;bottom:0;height:262px;background:linear-gradient(#0b122000,#0b1220f0 30%);pointer-events:none"></div>`
  : '';
// --cam x,y,z --target x,y,z places the camera after init (replay/drone only).
const cam = args.cam && args.target
  ? `const R=window.__runlah;R.camera.position.set(${args.cam});R.controls.target.set(${args.target});R.controls.update();`
  : '';
const step = args.step ? `window.__runlah.step(${Number(args.step)});` : '';
const inject = `${bars}<script>window.runlah.receive(${JSON.stringify(JSON.stringify({ type: 'init', data }))});${cam}${step}</script>`;
const out = resolve(args.out || resolve(here, '../.preview/preview.html'));
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, html.replace('</body>', `${inject}</body>`));
console.log(out);
