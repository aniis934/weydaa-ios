#!/usr/bin/env node
// Convertit les 14 illustrations 3D des catégories du site (public/categories/<slug>_lg.webp, 512 px, fond pastel
// plein) en images d'Asset Catalog iOS : PNG sans perte @2x (128 px) et @3x (192 px) pour une tuile de 64 pt au
// plus — la tuile de l'accueil (60 pt) est dessinée à 180 px depuis 192 : nette, sans surcoût mémoire.
//
//   node scripts/convert-category-art.mjs
//
// Source : <dépôt privé>/public/categories (par défaut ../weydaa-site/public/categories, sinon WEYDA_CATEGORY_ART).
// Décodage WebP : `sharp`, pris dans node_modules du dépôt du site (aucune dépendance ajoutée ici).
// Sortie : Weyda/Resources/Assets.xcassets/CategoryArt/art_cat_<slug>.imageset/{@2x,@3x}.png + Contents.json
//          (« Autres » sert aussi de repli pour une catégorie inconnue, voir CategoryIcon.artworkName).

import { writeFileSync, mkdirSync, existsSync, rmSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SITE = resolve(ROOT, '..', 'weydaa-site');
const SRC = process.env.WEYDA_CATEGORY_ART ?? join(SITE, 'public', 'categories');
const OUT = join(ROOT, 'Weyda', 'Resources', 'Assets.xcassets', 'CategoryArt');

/** Côté de la tuile de référence (pt) : @2x et @3x en découlent. */
const BASE_PT = 64;

// Slugs racines de l'API (= CategoryIcon.knownSlugs) ; le nom d'asset remplace « - » par « _ ».
const SLUGS = [
  'vehicules', 'immobilier', 'electronique', 'emploi', 'electromenager', 'mode', 'maison',
  'services', 'animaux', 'loisirs', 'materiel-pro', 'artisanat', 'voyage', 'autres',
];

const sharp = createRequire(join(SITE, 'package.json'))('sharp');

/** JSON au format d'Xcode (« clé » : valeur). */
const xcodeJSON = (value) => JSON.stringify(value, null, 2).replace(/": /g, '" : ') + '\n';
const INFO = { author: 'xcode', version: 1 };

const contents = (name) => xcodeJSON({
  images: [
    { idiom: 'universal', scale: '1x' },
    { filename: `${name}@2x.png`, idiom: 'universal', scale: '2x' },
    { filename: `${name}@3x.png`, idiom: 'universal', scale: '3x' },
  ],
  info: INFO,
});

/** Le site a posé chaque illustration (80 % du côté, centrée) sur un aplat pastel voisin de son fond, mais pas
 *  identique — et ce fond n'est pas uni (il s'éclaircit souvent vers un coin) : un carré se devinait, et un sujet
 *  qui touchait son bord (Maison, Loisirs) y était coupé net. Correctif : la marge prolonge, côté par côté, la
 *  couleur du fond relevée juste à l'intérieur du carré (profil lissé, sujet écarté), et la jointure se fond sur
 *  2 % du côté. Le sujet lui-même n'est pas retouché. */
const INNER_MARGIN = 0.1;
const FEATHER = 0.02;
/** Bande de relevé, en pixels à l'intérieur du bord (512 px) ; écart au-delà duquel un pixel est « sujet ». */
const BAND = [3, 12];
const SUBJECT_DELTA = 8;
const SMOOTH = 24;

/** Profil de fond le long d'un côté : `sample(s, d)` = pixel à la position s, à d pixels du bord. */
function sideProfile(sample, from, to) {
  const all = [];
  for (let s = from; s < to; s++) for (let d = BAND[0]; d < BAND[1]; d++) all.push(sample(s, d));
  const median = [0, 1, 2].map((c) => all.map((p) => p[c]).sort((a, b) => a - b)[all.length >> 1]);
  const raw = [];
  for (let s = from; s < to; s++) {
    const kept = [];
    for (let d = BAND[0]; d < BAND[1]; d++) {
      const p = sample(s, d);
      if (Math.max(...p.map((v, c) => Math.abs(v - median[c]))) <= SUBJECT_DELTA) kept.push(p);
    }
    raw.push(kept.length ? [0, 1, 2].map((c) => kept.reduce((sum, p) => sum + p[c], 0) / kept.length) : null);
  }
  // Trous (sujet contre le bord) : interpolés entre les voisins valides ; côté entièrement masqué : la médiane.
  const filled = raw.map((value, i) => {
    if (value) return value;
    let a = i - 1;
    let b = i + 1;
    while (a >= 0 && !raw[a]) a--;
    while (b < raw.length && !raw[b]) b++;
    if (a < 0 && b >= raw.length) return median;
    if (a < 0) return raw[b];
    if (b >= raw.length) return raw[a];
    const t = (i - a) / (b - a);
    return [0, 1, 2].map((c) => raw[a][c] * (1 - t) + raw[b][c] * t);
  });
  // Lissage (deux passes de moyenne glissante) : la marge varie en douceur, sans rayures.
  let profile = filled;
  for (let pass = 0; pass < 2; pass++) {
    profile = profile.map((_, i) => {
      const lo = Math.max(0, i - SMOOTH);
      const hi = Math.min(profile.length - 1, i + SMOOTH);
      const sum = [0, 0, 0];
      for (let j = lo; j <= hi; j++) for (let c = 0; c < 3; c++) sum[c] += profile[j][c];
      return sum.map((v) => v / (hi - lo + 1));
    });
  }
  return profile;
}

async function withoutSeam(src) {
  const { data, info } = await sharp(src).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  const side = info.width;
  const b0 = Math.round(side * INNER_MARGIN);
  const b1 = side - b0;
  const px = (x, y) => {
    const i = (y * side + x) * 3;
    return [data[i], data[i + 1], data[i + 2]];
  };
  const left = sideProfile((s, d) => px(b0 + d, s), b0, b1);
  const right = sideProfile((s, d) => px(b1 - 1 - d, s), b0, b1);
  const top = sideProfile((s, d) => px(s, b0 + d), b0, b1);
  const bottom = sideProfile((s, d) => px(s, b1 - 1 - d), b0, b1);
  const clamp = (v) => Math.min(Math.max(v, b0), b1 - 1) - b0;
  const mix = (a, b, t) => [0, 1, 2].map((c) => a[c] * (1 - t) + b[c] * t);

  /** Couleur de fond en (x, y) : le profil du ou des côtés les plus proches, pondérés par l'éloignement. */
  const background = (x, y) => {
    const dl = x + 0.5 - b0;
    const dr = b1 - x - 0.5;
    const dt = y + 0.5 - b0;
    const db = b1 - y - 0.5;
    const horizontal = dl < dr ? left[clamp(y)] : right[clamp(y)];
    const vertical = dt < db ? top[clamp(x)] : bottom[clamp(x)];
    const dh = Math.max(Math.min(dl, dr), 0.01);
    const dv = Math.max(Math.min(dt, db), 0.01);
    if (dh <= 0.01 && dv <= 0.01) return mix(horizontal, vertical, 0.5);
    return mix(horizontal, vertical, dh / (dh + dv));
  };

  const feather = side * FEATHER;
  const out = Buffer.alloc(data.length);
  for (let y = 0; y < side; y++) {
    for (let x = 0; x < side; x++) {
      const inside = Math.min(x + 0.5 - b0, b1 - x - 0.5, y + 0.5 - b0, b1 - y - 0.5);
      const t = Math.min(Math.max(inside / feather, 0), 1);
      const w = t * t * (3 - 2 * t);
      const i = (y * side + x) * 3;
      const bg = w < 1 ? background(x, y) : null;
      for (let c = 0; c < 3; c++) {
        out[i + c] = Math.round(bg ? data[i + c] * w + bg[c] * (1 - w) : data[i + c]);
      }
    }
  }
  return { data: out, info: { width: side, height: side, channels: 3 } };
}

async function main() {
  if (existsSync(OUT)) rmSync(OUT, { recursive: true });
  mkdirSync(OUT, { recursive: true });
  writeFileSync(join(OUT, 'Contents.json'), xcodeJSON({ info: INFO }));
  let total = 0;
  for (const slug of SLUGS) {
    const src = join(SRC, `${slug}_lg.webp`);
    if (!existsSync(src)) throw new Error(`illustration manquante : ${src}`);
    const name = `art_cat_${slug.replace(/-/g, '_')}`;
    const dir = join(OUT, `${name}.imageset`);
    mkdirSync(dir);
    const seamless = await withoutSeam(src);
    for (const scale of [2, 3]) {
      const px = BASE_PT * scale;
      // Lanczos (réduction 512 → 192/128) puis PNG RVB sans alpha : l'illustration est opaque (fond pastel).
      const png = await sharp(seamless.data, { raw: seamless.info })
        .resize(px, px, { kernel: 'lanczos3' })
        .png({ compressionLevel: 9, adaptiveFiltering: true })
        .toBuffer();
      writeFileSync(join(dir, `${name}@${scale}x.png`), png);
      total += png.length;
    }
    writeFileSync(join(dir, 'Contents.json'), contents(name));
    console.log(`[OK] ${name}`);
  }
  console.log(`${SLUGS.length} illustrations, ${(total / 1024).toFixed(0)} Ko (@2x + @3x) → ${OUT}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
