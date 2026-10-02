#!/usr/bin/env node
// Convertit les icônes Lucide de l'app Android (VectorDrawable XML) en SVG d'Asset Catalog iOS.
//
//   node scripts/convert-icons.mjs
//
// Source : <dépôt privé>/android/app/src/main/res/drawable/ic_cat_*.xml + ic_map_pin.xml
//          (par défaut ../weydaa-site/android/…, sinon variable WEYDA_ANDROID_RES)
// Sortie : Weyda/Resources/Assets.xcassets/Categories/<nom>.imageset/{<nom>.svg, Contents.json}
//          — vectoriel conservé, rendu « template » (teinté à l'usage comme sur Android).

import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const RES = process.env.WEYDA_ANDROID_RES
  ?? resolve(ROOT, '..', 'weydaa-site', 'android', 'app', 'src', 'main', 'res');
const DRAWABLE = join(RES, 'drawable');
const OUT = join(ROOT, 'Weyda', 'Resources', 'Assets.xcassets', 'Categories');

const attr = (tag, name) => tag.match(new RegExp(`android:${name}="([^"]*)"`))?.[1];

/** #AARRGGBB / #RRGGBB → couleur SVG (null = transparent). Teinte noire : l'icône est un gabarit. */
function svgColor(android) {
  if (!android) return null;
  const hex = android.replace('#', '');
  const alpha = hex.length === 8 ? parseInt(hex.slice(0, 2), 16) : 255;
  return alpha === 0 ? null : '#000000';
}

function convert(file) {
  const xml = readFileSync(join(DRAWABLE, file), 'utf8').replace(/<!--[\s\S]*?-->/g, '');
  if (/<group/.test(xml)) throw new Error(`${file} : <group> non pris en charge`);
  const root = xml.match(/<vector[\s\S]*?>/)[0];
  const w = attr(root, 'viewportWidth');
  const h = attr(root, 'viewportHeight');
  const paths = [...xml.matchAll(/<path[\s\S]*?\/>/g)].map(([tag]) => {
    const d = attr(tag, 'pathData');
    const fill = svgColor(attr(tag, 'fillColor'));
    const stroke = svgColor(attr(tag, 'strokeColor'));
    const parts = [`d="${d}"`, `fill="${fill ?? 'none'}"`];
    if (stroke) {
      parts.push(`stroke="${stroke}"`, `stroke-width="${attr(tag, 'strokeWidth') ?? '1'}"`);
      parts.push(`stroke-linecap="${attr(tag, 'strokeLineCap') ?? 'butt'}"`);
      parts.push(`stroke-linejoin="${attr(tag, 'strokeLineJoin') ?? 'miter'}"`);
    }
    return `  <path ${parts.join(' ')}/>`;
  });
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">`,
    ...paths,
    '</svg>',
    '',
  ].join('\n');
}

const contents = (name) => JSON.stringify({
  images: [{ filename: `${name}.svg`, idiom: 'universal' }],
  info: { author: 'xcode', version: 1 },
  properties: { 'preserves-vector-representation': true, 'template-rendering-intent': 'template' },
}, null, 2).replace(/"([^"]+)": /g, '"$1" : ') + '\n';

if (!existsSync(DRAWABLE)) throw new Error(`Introuvable : ${DRAWABLE} (définir WEYDA_ANDROID_RES)`);
const files = readdirSync(DRAWABLE).filter((f) => /^ic_cat_.*\.xml$/.test(f) || f === 'ic_map_pin.xml').sort();
mkdirSync(OUT, { recursive: true });
writeFileSync(join(OUT, 'Contents.json'), '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n');
for (const file of files) {
  const name = file.replace(/\.xml$/, '');
  const dir = join(OUT, `${name}.imageset`);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, `${name}.svg`), convert(file));
  writeFileSync(join(dir, 'Contents.json'), contents(name));
}
console.log(`✓ ${files.length} icônes → ${OUT}`);
