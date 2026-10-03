// Fusionne les chaînes des agents (ios-team/strings/<agent>.json) dans scripts/ios-strings.json du worktree iOS.
// Usage : node scripts/merge-agent-strings.mjs <dépôt iOS> <fichier agent> [<fichier agent>…]
// (fichiers des agents : même format que scripts/ios-strings.json ; puis node scripts/convert-strings.mjs)
// Refuse : clé en double entre agents, clé « add » déjà présente côté Android ou iOS, langue manquante.
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [repo, ...files] = process.argv.slice(2);
const target = join(repo, 'scripts', 'ios-strings.json');
const ios = JSON.parse(readFileSync(target, 'utf8'));
const l10n = readFileSync(join(repo, 'Weyda', 'Core', 'Localization', 'L10n.swift'), 'utf8');
const existing = new Set([...l10n.matchAll(/^\s+"([a-z0-9_]+)",$/gm)].map((m) => m[1]));

const problems = [];
const seen = new Map();
const checkLangs = (key, value) => {
  for (const lang of ['fr', 'ar', 'en']) {
    if (value[lang] === undefined) problems.push(`${key} : langue ${lang} manquante`);
  }
};
for (const file of files) {
  const data = JSON.parse(readFileSync(file, 'utf8'));
  for (const [key, value] of Object.entries(data.add ?? {})) {
    if (seen.has(key)) problems.push(`${key} : ajoutée par ${seen.get(key)} et ${file}`);
    if (existing.has(key) && !(key in ios.add)) problems.push(`${key} : existe déjà (Android) — à mettre en override`);
    seen.set(key, file);
    checkLangs(key, value);
    ios.add[key] = value;
  }
  for (const [key, value] of Object.entries(data.override ?? {})) {
    if (!existing.has(key)) problems.push(`${key} : override d'une clé inexistante`);
    checkLangs(key, value);
    ios.override[key] = value;
  }
}
if (problems.length) {
  console.error(problems.join('\n'));
  process.exit(1);
}
writeFileSync(target, JSON.stringify(ios, null, 2) + '\n');
console.log(`ios-strings.json : ${Object.keys(ios.add).length} ajouts, ${Object.keys(ios.override).length} overrides`);
