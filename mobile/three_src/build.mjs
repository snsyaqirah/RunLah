// Bundles src/ (three.js scene) into ONE self-contained HTML file:
//   ../assets/three/race3d.html
// No network and no runtime module imports, so it loads from
// file:///android_asset, iOS WKWebView file URLs and a Flutter-web iframe.
import { build, context } from 'esbuild';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(here, '../assets/three/race3d.html');
const watch = process.argv.includes('--watch');

const options = {
  entryPoints: [resolve(here, 'src/main.js')],
  bundle: true,
  minify: true,
  format: 'iife',
  // WebGL2 baseline: Android System WebView / Chrome 90+, iOS 15+.
  target: ['chrome90', 'safari15', 'firefox90'],
  legalComments: 'none',
  treeShaking: true,
  outfile: resolve(here, '.preview/bundle.js'),
  write: false,
  logLevel: 'warning',
};

function emit(result) {
  const js = result.outputFiles[0].text
    // Never let the bundle close the inline <script> early.
    .replace(/<\/script/gi, '<\\/script');
  const css = readFileSync(resolve(here, 'src/style.css'), 'utf8').replace(/\s*\n\s*/g, '');
  const html = readFileSync(resolve(here, 'src/index.html'), 'utf8')
    .replace('/*__CSS__*/', () => css)
    .replace('/*__JS__*/', () => js);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, html);
  const kb = (Buffer.byteLength(html) / 1024).toFixed(0);
  console.log(`race3d.html  ${kb} KB  ->  ${out}`);
}

if (watch) {
  const ctx = await context({
    ...options,
    plugins: [{ name: 'emit', setup(b) { b.onEnd((r) => r.errors.length || emit(r)); } }],
  });
  await ctx.watch();
  console.log('watching src/ ...');
} else {
  emit(await build(options));
}
