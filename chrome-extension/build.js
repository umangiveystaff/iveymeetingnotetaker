// build.js — esbuild bundler for Ivey Meeting Notes extension
import { build } from 'esbuild';
import { cpSync, mkdirSync, readdirSync, copyFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const dist = join(__dirname, 'dist');
const src  = join(__dirname, 'src');

const isWatch = process.argv.includes('--watch');

// Ensure dist dirs exist
mkdirSync(dist, { recursive: true });
mkdirSync(join(dist, 'icons'), { recursive: true });
mkdirSync(join(dist, 'wasm'),  { recursive: true });

// ── Copy static files ────────────────────────────────────────────────────────
const statics = ['manifest.json', 'popup.html', 'offscreen.html'];
for (const f of statics) {
  const from = join(__dirname, f);
  if (existsSync(from)) {
    copyFileSync(from, join(dist, f));
    console.log(`Copied: ${f}`);
  }
}

// Copy popup.css
if (existsSync(join(src, 'popup.css'))) {
  copyFileSync(join(src, 'popup.css'), join(dist, 'popup.css'));
  console.log('Copied: popup.css');
}

// Copy icons
if (existsSync(join(__dirname, 'icons'))) {
  cpSync(join(__dirname, 'icons'), join(dist, 'icons'), { recursive: true });
  console.log('Copied: icons/');
}

// Copy ONNX WASM files from onnxruntime-web (needed by @xenova/transformers)
// These are compute binaries, not data — they run the Whisper model locally
const onnxDirs = [
  join(__dirname, 'node_modules', 'onnxruntime-web', 'dist'),
  join(__dirname, 'node_modules', '@xenova', 'transformers', 'dist'),
];
for (const dir of onnxDirs) {
  if (existsSync(dir)) {
    const wasmFiles = readdirSync(dir).filter(f => f.endsWith('.wasm') || f.endsWith('.mjs'));
    for (const f of wasmFiles) {
      copyFileSync(join(dir, f), join(dist, 'wasm', f));
    }
    if (wasmFiles.length) console.log(`Copied ${wasmFiles.length} WASM files from ${dir}`);
  }
}

// ── Bundle JS files ──────────────────────────────────────────────────────────
const baseConfig = {
  bundle: true,
  format: 'esm',
  target: 'chrome116',
  minify: !isWatch,
  sourcemap: isWatch ? 'inline' : false,
};

const entries = [
  { in: join(src, 'background.js'),  out: join(dist, 'background') },
  { in: join(src, 'content.js'),     out: join(dist, 'content') },
  { in: join(src, 'offscreen.js'),   out: join(dist, 'offscreen') },
  { in: join(src, 'popup.js'),       out: join(dist, 'popup') },
];

console.log('\nBundling JS...');
await Promise.all(entries.map(({ in: entryPoint, out: outfile }) =>
  build({
    ...baseConfig,
    entryPoints: [entryPoint],
    outfile: outfile + '.js',
    // Mark Chrome extension APIs as external (they're globals in the extension context)
    define: {
      'process.env.NODE_ENV': '"production"',
    },
  }).then(() => console.log(`  ✓ ${entryPoint.split('/').pop()}`))
));

console.log('\n✅ Build complete → dist/');
console.log('   Load dist/ folder as an unpacked extension in chrome://extensions\n');
