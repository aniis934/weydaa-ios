#!/usr/bin/env node
// Convertit les chaînes de l'app Android (strings.xml fr / ar / en) en catalogue iOS.
//
//   node scripts/convert-strings.mjs            → écrit les deux fichiers générés
//   node scripts/convert-strings.mjs --check    → échoue s'ils ne sont pas à jour
//
// Source : <dépôt privé>/android/app/src/main/res/values{,-ar,-en}/strings.xml
//          (par défaut ../weydaa-site/android/…, sinon variable WEYDA_ANDROID_RES)
//          + scripts/ios-strings.json (chaînes propres à iOS, remplacements, exclusions)
// Sorties : Weyda/Resources/Localizable.xcstrings (mêmes clés, mêmes traductions)
//           Weyda/Core/Localization/L10n.swift   (accès typés : L10n.navHome, L10n.priceDzd(_:)…)
//
// Les fichiers générés sont commités : la CI n'a pas accès au dépôt privé.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const RES = process.env.WEYDA_ANDROID_RES
  ?? resolve(ROOT, '..', 'weydaa-site', 'android', 'app', 'src', 'main', 'res');
const LANGS = { fr: 'values', ar: 'values-ar', en: 'values-en' };
const SOURCE_LANG = 'fr';
const OUT_CATALOG = join(ROOT, 'Weyda', 'Resources', 'Localizable.xcstrings');
const OUT_SWIFT = join(ROOT, 'Weyda', 'Core', 'Localization', 'L10n.swift');
const IOS_STRINGS = join(ROOT, 'scripts', 'ios-strings.json');
const CHECK = process.argv.includes('--check');

const BACKSLASH = String.fromCharCode(92);

// ── Lecture d'un strings.xml ────────────────────────────────────────────────

function decodeEntities(s) {
  return s
    .replace(/&#x([0-9a-fA-F]+);/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#([0-9]+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');
}

/** Règles d'Android : guillemets englobants, espaces repliés, échappements par barre oblique inverse. */
function androidText(raw) {
  let s = decodeEntities(raw);
  const quoted = s.length >= 2 && s.startsWith('"') && s.endsWith('"');
  if (quoted) s = s.slice(1, -1);
  else s = s.replace(/\s+/g, ' ').trim();
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c !== BACKSLASH) { out += c; continue; }
    const n = s[++i];
    if (n === 'n') out += '\n';
    else if (n === 't') out += '\t';
    else if (n === 'u') { out += String.fromCharCode(parseInt(s.slice(i + 1, i + 5), 16)); i += 4; }
    else if (n !== undefined) out += n; // \' \" \\ \@ \?
  }
  if (/<[a-zA-Z]/.test(out)) throw new Error(`Balise HTML non prise en charge : ${raw}`);
  return out;
}

function parseStringsXml(path) {
  const xml = readFileSync(path, 'utf8').replace(/<!--[\s\S]*?-->/g, '');
  const strings = new Map();
  const plurals = new Map();
  for (const m of xml.matchAll(/<string\s+name="([^"]+)"[^>]*?(?:\/>|>([\s\S]*?)<\/string>)/g)) {
    if (/translatable="false"/.test(m[0].slice(0, m[0].indexOf('>')))) continue;
    strings.set(m[1], androidText(m[2] ?? ''));
  }
  for (const m of xml.matchAll(/<plurals\s+name="([^"]+)"[^>]*>([\s\S]*?)<\/plurals>/g)) {
    const items = {};
    for (const it of m[2].matchAll(/<item\s+quantity="([a-z]+)"\s*>([\s\S]*?)<\/item>/g)) {
      items[it[1]] = androidText(it[2]);
    }
    plurals.set(m[1], items);
  }
  return { strings, plurals };
}

// ── Formats Android → formats Apple ─────────────────────────────────────────

const SPEC = /%(\d+\$)?([-+ 0#]*)(\d+)?(\.\d+)?([sdf%])/g;

function toAppleFormat(s) {
  return s.replace(SPEC, (all, pos = '', flags = '', width = '', prec = '', conv) => {
    if (conv === '%') return '%%';
    const apple = conv === 's' ? '@' : conv === 'd' ? 'lld' : 'f';
    return `%${pos}${flags}${width}${prec}${apple}`;
  });
}

/** Types Swift des arguments, déduits des spécificateurs (positionnels ou non). */
function argTypes(s) {
  const types = [];
  let next = 0;
  for (const m of s.matchAll(SPEC)) {
    if (m[5] === '%') continue;
    const index = m[1] ? parseInt(m[1], 10) - 1 : next++;
    types[index] = m[5] === 's' ? 'String' : m[5] === 'd' ? 'Int' : 'Double';
  }
  for (let i = 0; i < types.length; i++) {
    if (!types[i]) throw new Error(`Argument ${i + 1} manquant dans « ${s} »`);
  }
  return types;
}

// ── Assemblage ──────────────────────────────────────────────────────────────

function load() {
  const perLang = {};
  for (const [lang, dir] of Object.entries(LANGS)) {
    const path = join(RES, dir, 'strings.xml');
    if (!existsSync(path)) throw new Error(`Introuvable : ${path} (définir WEYDA_ANDROID_RES)`);
    perLang[lang] = parseStringsXml(path);
  }
  const ios = JSON.parse(readFileSync(IOS_STRINGS, 'utf8'));
  const exclude = new Set(ios.exclude ?? []);
  const entries = new Map(); // clé → { kind, values: {lang: string | {quantity: string}} }

  const src = perLang[SOURCE_LANG];
  for (const key of src.strings.keys()) {
    if (exclude.has(key)) continue;
    const values = {};
    for (const lang of Object.keys(LANGS)) {
      const v = perLang[lang].strings.get(key);
      if (v === undefined) throw new Error(`Clé « ${key} » absente en ${lang}`);
      values[lang] = v;
    }
    entries.set(key, { kind: 'string', values, origin: 'android' });
  }
  for (const key of src.plurals.keys()) {
    if (exclude.has(key)) continue;
    const values = {};
    for (const lang of Object.keys(LANGS)) {
      const v = perLang[lang].plurals.get(key);
      if (!v) throw new Error(`Pluriel « ${key} » absent en ${lang}`);
      if (!v.other) throw new Error(`Pluriel « ${key} » sans « other » en ${lang}`);
      values[lang] = v;
    }
    entries.set(key, { kind: 'plural', values, origin: 'android' });
  }
  for (const [key, values] of Object.entries(ios.override ?? {})) {
    const e = entries.get(key);
    if (!e) throw new Error(`Remplacement d'une clé inconnue : ${key}`);
    if (e.kind !== 'string') throw new Error(`Remplacement d'un pluriel non pris en charge : ${key}`);
    e.values = { ...values };
    e.origin = 'ios-override';
  }
  for (const [key, values] of Object.entries(ios.add ?? {})) {
    if (entries.has(key)) throw new Error(`Ajout d'une clé qui existe déjà : ${key}`);
    const isPlural = typeof values.fr === 'object';
    entries.set(key, { kind: isPlural ? 'plural' : 'string', values: { ...values }, origin: 'ios' });
  }
  for (const [key, e] of entries) {
    for (const lang of Object.keys(LANGS)) {
      if (e.values[lang] === undefined) throw new Error(`Clé « ${key} » sans traduction ${lang}`);
    }
  }
  return new Map([...entries].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
}

// ── Écriture du catalogue (.xcstrings) ──────────────────────────────────────

function unit(value) {
  return { stringUnit: { state: 'translated', value: toAppleFormat(value) } };
}

function catalog(entries) {
  const strings = {};
  for (const [key, e] of entries) {
    const localizations = {};
    for (const lang of Object.keys(LANGS).sort()) {
      if (e.kind === 'string') {
        localizations[lang] = unit(e.values[lang]);
      } else {
        const plural = {};
        for (const q of Object.keys(e.values[lang]).sort()) plural[q] = unit(e.values[lang][q]);
        localizations[lang] = { variations: { plural } };
      }
    }
    strings[key] = { extractionState: 'manual', localizations };
  }
  // Mise en forme d'Xcode : « clé" : valeur », 2 espaces.
  return JSON.stringify({ sourceLanguage: SOURCE_LANG, strings, version: '1.0' }, null, 2)
    .replace(/"([^"\\]*(?:\\.[^"\\]*)*)": /g, '"$1" : ') + '\n';
}

// ── Écriture des accès Swift (L10n.swift) ───────────────────────────────────

const SWIFT_KEYWORDS = new Set(['associatedtype', 'class', 'deinit', 'enum', 'extension', 'fileprivate', 'func',
  'import', 'init', 'inout', 'internal', 'let', 'open', 'operator', 'private', 'protocol', 'public', 'rethrows',
  'static', 'struct', 'subscript', 'typealias', 'var', 'break', 'case', 'continue', 'default', 'defer', 'do',
  'else', 'fallthrough', 'for', 'guard', 'if', 'in', 'repeat', 'return', 'switch', 'where', 'while', 'as', 'Any',
  'catch', 'false', 'is', 'nil', 'super', 'self', 'Self', 'throw', 'throws', 'true', 'try', 'some', 'any']);

function camel(key) {
  const name = key.replace(/[_-]+([a-zA-Z0-9])/g, (_, c) => c.toUpperCase());
  return SWIFT_KEYWORDS.has(name) ? `\`${name}\`` : name;
}

function docComment(text) {
  return text.replace(/\s+/g, ' ').replace(/\*\//g, '* /').trim();
}

function swift(entries) {
  const lines = [
    '// GÉNÉRÉ par scripts/convert-strings.mjs — NE PAS MODIFIER À LA MAIN.',
    '// Source : strings.xml de l\'app Android (fr / ar / en) + scripts/ios-strings.json.',
    '// swiftlint:disable all',
    '',
    'import Foundation',
    '',
    'nonisolated enum L10n {',
  ];
  const names = new Map();
  for (const key of entries.keys()) {
    const name = camel(key);
    if (names.has(name)) throw new Error(`« ${key} » et « ${names.get(name)} » donnent le même accès Swift : ${name}`);
    names.set(name, key);
  }
  for (const [key, e] of entries) {
    const fr = e.kind === 'string' ? e.values.fr : e.values.fr.other;
    const types = argTypes(fr);
    if (e.kind === 'plural' && types[0] !== 'Int') throw new Error(`Pluriel « ${key} » : le 1er argument doit être un entier`);
    for (const lang of ['ar', 'en']) {
      const other = e.kind === 'string' ? e.values[lang] : e.values[lang].other;
      const t = argTypes(other);
      if (t.join() !== types.join()) throw new Error(`« ${key} » : arguments ${lang} (${t}) ≠ fr (${types})`);
    }
    lines.push(`    /// ${docComment(fr)}`);
    if (types.length === 0) {
      lines.push(`    static var ${camel(key)}: String { tr("${key}") }`);
    } else {
      const params = types.map((t, i) => `_ p${i + 1}: ${t}`).join(', ');
      const args = types.map((_, i) => `p${i + 1}`).join(', ');
      lines.push(`    static func ${camel(key)}(${params}) -> String { tr("${key}", ${args}) }`);
    }
  }
  lines.push('');
  lines.push('    /// Toutes les clés du catalogue (test de parité).');
  lines.push('    static let allKeys: [String] = [');
  for (const key of entries.keys()) lines.push(`        "${key}",`);
  lines.push('    ]');
  lines.push('');
  lines.push('    /// Clés à variantes de pluriel.');
  lines.push('    static let pluralKeys: [String] = [');
  for (const [key, e] of entries) if (e.kind === 'plural') lines.push(`        "${key}",`);
  lines.push('    ]');
  lines.push('}');
  return lines.join('\n') + '\n';
}

// ── Principal ───────────────────────────────────────────────────────────────

const entries = load();
const outputs = [[OUT_CATALOG, catalog(entries)], [OUT_SWIFT, swift(entries)]];

const android = [...entries].filter(([, e]) => e.origin === 'android' && /android|play store|google play/i.test(
  e.kind === 'string' ? e.values.fr : Object.values(e.values.fr).join(' ')));
if (android.length) {
  console.warn(`⚠ ${android.length} chaîne(s) parlent d'Android — à remplacer (override) quand leur écran arrive :`);
  for (const [key] of android) console.warn(`   · ${key}`);
}

if (CHECK) {
  const stale = outputs.filter(([p, c]) => !existsSync(p) || readFileSync(p, 'utf8') !== c);
  if (stale.length) {
    console.error(`✗ Fichiers générés périmés : ${stale.map(([p]) => p).join(', ')}`);
    process.exit(1);
  }
  console.log(`✓ Catalogue à jour (${entries.size} clés).`);
} else {
  for (const [p, c] of outputs) writeFileSync(p, c);
  const plurals = [...entries.values()].filter((e) => e.kind === 'plural').length;
  console.log(`✓ ${entries.size} clés (${plurals} pluriels) × ${Object.keys(LANGS).length} langues → ${OUT_CATALOG}`);
}
