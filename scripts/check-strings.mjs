#!/usr/bin/env node
// Garde-fou du catalogue, lancé par la CI avant la compilation (aucun accès au dépôt privé requis) :
//  · chaque clé a fr, ar ET en, état « translated », texte non vide ;
//  · un pluriel a toujours sa variante « other » ;
//  · les mêmes spécificateurs (%1$@, %lld…) dans les trois langues ;
//  · L10n.allKeys == clés du catalogue (le Swift généré n'a pas dérivé).

import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const catalog = JSON.parse(readFileSync(join(ROOT, 'Weyda', 'Resources', 'Localizable.xcstrings'), 'utf8'));
const swift = readFileSync(join(ROOT, 'Weyda', 'Core', 'Localization', 'L10n.swift'), 'utf8');
const LANGS = ['fr', 'ar', 'en'];
const errors = [];

const specs = (s) => [...s.matchAll(/%(\d+\$)?[-+ 0#]*\d*(\.\d+)?(lld|@|f)/g)].map((m) => m[0]).sort().join(' ');

for (const [key, entry] of Object.entries(catalog.strings)) {
  let reference = null;
  for (const lang of LANGS) {
    const loc = entry.localizations?.[lang];
    if (!loc) { errors.push(`${key} : pas de ${lang}`); continue; }
    let text;
    if (loc.stringUnit) {
      text = loc.stringUnit.value;
      if (loc.stringUnit.state !== 'translated') errors.push(`${key} [${lang}] : état ${loc.stringUnit.state}`);
    } else if (loc.variations?.plural) {
      const other = loc.variations.plural.other?.stringUnit;
      if (!other) { errors.push(`${key} [${lang}] : pluriel sans « other »`); continue; }
      text = other.value;
    } else {
      errors.push(`${key} [${lang}] : forme inconnue`);
      continue;
    }
    if (!text || !text.trim()) errors.push(`${key} [${lang}] : texte vide`);
    const s = specs(text);
    if (reference === null) reference = s;
    else if (s !== reference) errors.push(`${key} [${lang}] : arguments « ${s} » ≠ « ${reference} »`);
  }
}

const listed = [...swift.matchAll(/^ {8}"([^"]+)",$/gm)].map((m) => m[1]);
const keys = Object.keys(catalog.strings);
const missing = keys.filter((k) => !listed.includes(k));
const extra = listed.filter((k) => !keys.includes(k));
if (missing.length) errors.push(`L10n.swift ne connaît pas : ${missing.join(', ')}`);
if (extra.length) errors.push(`L10n.swift cite des clés absentes du catalogue : ${extra.join(', ')}`);

if (errors.length) {
  console.error(`✗ ${errors.length} problème(s) dans le catalogue :`);
  for (const e of errors) console.error(`  · ${e}`);
  process.exit(1);
}
console.log(`✓ Catalogue cohérent : ${keys.length} clés × ${LANGS.length} langues.`);
