#!/usr/bin/env node
// Rend l'icône de l'app (1024 px : claire, sombre, teintée) et le W de l'écran de démarrage,
// à partir du tracé du W (le même que WeydaMark.swift et que l'app Android) — sans dépendance :
// rastérisation par distance au tracé (anticrénelage), encodage PNG maison (zlib de Node).
//
//   node scripts/render-icon.mjs
//
// Sorties : Weyda/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon{,-dark,-tinted}.png (RVB, sans alpha)
//           Weyda/Resources/Assets.xcassets/SplashMark.imageset/SplashMark@{2,3}x.png (RVBA)

import { writeFileSync, mkdirSync } from 'node:fs';
import { deflateSync } from 'node:zlib';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ASSETS = join(ROOT, 'Weyda', 'Resources', 'Assets.xcassets');

// ── Le W (repère 100 × 100) — identique à WEYDA_W_PATH_DATA (Android) et WeydaMark.swift ──
const W_PATH = 'M29.51,20.5 L14.41,63.72 C7.04,84.75 29.95,84.75 39.11,63.72 '
  + 'L57.97,20.5 L43.23,63.72 C36.09,84.75 64.32,84.75 71.69,63.72 L86.79,20.5';
const STROKE = 14.4;
const SHADOW_NEAR = 3.09;
const SHADOW_FAR = 6.17;
/** Part de la tuile occupée par le repère du W (WeydaTile : 0,56). */
const TILE_MARK = 0.56;

/** Tracé → liste de segments [x0, y0, x1, y1] (courbes de Bézier découpées en 48). */
function flatten(d) {
  const tokens = d.match(/[MLC]|-?\d*\.?\d+/g);
  const segs = [];
  let i = 0; let cmd = null; let x = 0; let y = 0;
  const num = () => parseFloat(tokens[i++]);
  while (i < tokens.length) {
    if (/[MLC]/.test(tokens[i])) cmd = tokens[i++];
    if (cmd === 'M') { x = num(); y = num(); cmd = 'L'; continue; }
    if (cmd === 'L') { const nx = num(); const ny = num(); segs.push([x, y, nx, ny]); x = nx; y = ny; continue; }
    if (cmd === 'C') {
      const [x1, y1, x2, y2, x3, y3] = [num(), num(), num(), num(), num(), num()];
      let px = x; let py = y;
      for (let k = 1; k <= 48; k++) {
        const t = k / 48; const u = 1 - t;
        const qx = u * u * u * x + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3;
        const qy = u * u * u * y + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3;
        segs.push([px, py, qx, qy]); px = qx; py = qy;
      }
      x = x3; y = y3;
    }
  }
  return segs;
}
const SEGMENTS = flatten(W_PATH);

function distanceToSegment(px, py, [x0, y0, x1, y1]) {
  const dx = x1 - x0; const dy = y1 - y0;
  const len2 = dx * dx + dy * dy;
  let t = len2 === 0 ? 0 : ((px - x0) * dx + (py - y0) * dy) / len2;
  t = Math.max(0, Math.min(1, t));
  const ex = px - (x0 + t * dx); const ey = py - (y0 + t * dy);
  return Math.sqrt(ex * ex + ey * ey);
}

// ── Toile RVBA en flottants ─────────────────────────────────────────────────

function canvas(size) {
  return { size, px: new Float64Array(size * size * 4) };
}
const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);

function fillLinearGradient(c, stops) {
  // Diagonale haut gauche → bas droite (Brush.linearGradient de Compose, dégradé du lanceur Android).
  const { size, px } = c;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const t = (x + y + 1) / (2 * size);
      let k = 0;
      while (k < stops.length - 2 && t > stops[k + 1][0]) k++;
      const [t0, c0] = stops[k]; const [t1, c1] = stops[k + 1];
      const f = Math.max(0, Math.min(1, (t - t0) / (t1 - t0)));
      const o = (y * size + x) * 4;
      for (let ch = 0; ch < 3; ch++) px[o + ch] = c0[ch] + (c1[ch] - c0[ch]) * f;
      px[o + 3] = 1;
    }
  }
}

function fillSolid(c, color) {
  for (let o = 0; o < c.px.length; o += 4) { c.px[o] = color[0]; c.px[o + 1] = color[1]; c.px[o + 2] = color[2]; c.px[o + 3] = 1; }
}

/** Trace le W (repère 100) dans le carré [ox, oy, ox + s, oy + s], couleur et opacité données, composé « par-dessus ». */
function strokeW(c, ox, oy, s, color, alpha = 1) {
  const scale = s / 100;
  const half = (STROKE / 2) * scale;
  const segs = SEGMENTS.map(([a, b, d, e]) => [ox + a * scale, oy + b * scale, ox + d * scale, oy + e * scale]);
  let minX = Infinity; let minY = Infinity; let maxX = -Infinity; let maxY = -Infinity;
  for (const [a, b, d, e] of segs) {
    minX = Math.min(minX, a, d); minY = Math.min(minY, b, e); maxX = Math.max(maxX, a, d); maxY = Math.max(maxY, b, e);
  }
  const x0 = Math.max(0, Math.floor(minX - half - 2)); const x1 = Math.min(c.size - 1, Math.ceil(maxX + half + 2));
  const y0 = Math.max(0, Math.floor(minY - half - 2)); const y1 = Math.min(c.size - 1, Math.ceil(maxY + half + 2));
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) {
      const cx = x + 0.5; const cy = y + 0.5;
      let d = Infinity;
      for (const seg of segs) { const v = distanceToSegment(cx, cy, seg); if (v < d) d = v; if (d <= half - 1) break; }
      const coverage = Math.max(0, Math.min(1, half + 0.5 - d)) * alpha;
      if (coverage <= 0) continue;
      const o = (y * c.size + x) * 4;
      const a = c.px[o + 3];
      const outA = coverage + a * (1 - coverage);
      for (let ch = 0; ch < 3; ch++) {
        c.px[o + ch] = outA === 0 ? 0 : (color[ch] * coverage + c.px[o + ch] * a * (1 - coverage)) / outA;
      }
      c.px[o + 3] = outA;
    }
  }
}

/** Le W extrudé (WeydaMarkExtruded) centré dans une tuile de `size` px. */
function extrudedTile(c, { far, near, front }) {
  const s = c.size * TILE_MARK;
  const o = (c.size - s) / 2;
  const unit = s / 100;
  strokeW(c, o + SHADOW_FAR * unit, o + SHADOW_FAR * unit, s, far);
  strokeW(c, o + SHADOW_NEAR * unit, o + SHADOW_NEAR * unit, s, near);
  strokeW(c, o, o, s, front);
}

// ── Encodage PNG ────────────────────────────────────────────────────────────

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}
function png(c, withAlpha) {
  const channels = withAlpha ? 4 : 3;
  const raw = Buffer.alloc((c.size * channels + 1) * c.size);
  for (let y = 0; y < c.size; y++) {
    const row = y * (c.size * channels + 1);
    raw[row] = 0;
    for (let x = 0; x < c.size; x++) {
      const o = (y * c.size + x) * 4;
      for (let ch = 0; ch < channels; ch++) {
        raw[row + 1 + x * channels + ch] = Math.round(Math.max(0, Math.min(1, c.px[o + ch])) * 255);
      }
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(c.size, 0); ihdr.writeUInt32BE(c.size, 4);
  ihdr[8] = 8; ihdr[9] = withAlpha ? 6 : 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ── Rendus ──────────────────────────────────────────────────────────────────

const EMERALD = {
  400: hex('#34D399'), 500: hex('#10B981'), 600: hex('#059669'), 700: hex('#047857'),
  800: hex('#065F46'), 900: hex('#064E3B'), 950: hex('#022C22'),
};
const WHITE = [1, 1, 1];

const iconDir = join(ASSETS, 'AppIcon.appiconset');
mkdirSync(iconDir, { recursive: true });

// Claire : le dégradé du lanceur Android (#10B981 → #0BA46F → #059669), W blanc, double extrusion.
const light = canvas(1024);
fillLinearGradient(light, [[0, EMERALD[500]], [0.55, hex('#0BA46F')], [1, EMERALD[600]]]);
extrudedTile(light, { far: EMERALD[800], near: EMERALD[950], front: WHITE });
writeFileSync(join(iconDir, 'AppIcon.png'), png(light, false));

// Sombre (iOS 18+) : fond nuit (Slate900 → Slate950), W emerald clair.
const dark = canvas(1024);
fillLinearGradient(dark, [[0, hex('#0F172A')], [1, hex('#020617')]]);
extrudedTile(dark, { far: EMERALD[800], near: EMERALD[900], front: EMERALD[400] });
writeFileSync(join(iconDir, 'AppIcon-dark.png'), png(dark, false));

// Teintée (iOS 18+) : niveaux de gris sur noir, le système applique la teinte choisie.
const tinted = canvas(1024);
fillSolid(tinted, [0, 0, 0]);
extrudedTile(tinted, { far: [0.32, 0.32, 0.32], near: [0.18, 0.18, 0.18], front: WHITE });
writeFileSync(join(iconDir, 'AppIcon-tinted.png'), png(tinted, false));

writeFileSync(join(iconDir, 'Contents.json'), `{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "AppIcon-dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "AppIcon-tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
`);

// W fantôme de l'écran de démarrage système : 160 pt, blanc à 14 % (comme splash_mark sur Android).
const splashDir = join(ASSETS, 'SplashMark.imageset');
mkdirSync(splashDir, { recursive: true });
for (const scale of [2, 3]) {
  const c = canvas(160 * scale);
  strokeW(c, 0, 0, c.size, WHITE, 0.14);
  writeFileSync(join(splashDir, `SplashMark@${scale}x.png`), png(c, true));
}
writeFileSync(join(splashDir, 'Contents.json'), `{
  "images" : [
    {
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "SplashMark@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "SplashMark@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
`);

console.log('✓ AppIcon (clair, sombre, teinté) 1024 px + SplashMark @2x/@3x');
