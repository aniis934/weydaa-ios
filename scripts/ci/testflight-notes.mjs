#!/usr/bin/env node
// Notes « À tester » (What to Test) d'un build TestFlight, écrites par l'API App Store Connect.
// Lancé par le job « notes » de ios-release (Linux), après l'envoi du build. Aucune dépendance : fetch
// et crypto de Node (jeton JWT ES256 signé avec la clé API d'équipe). Au mieux : un échec ici ne retire
// rien à la publication (le build est déjà chez Apple) ; les notes se saisissent alors à la main.
//
// Environnement : ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (contenu du .p8, brut ou en base64), BUNDLE_ID,
// MARKETING_VERSION, BUILD_NUMBER, NOTES, NOTES_LOCALE (fr-FR), WAIT_MINUTES (40).

import { createPrivateKey, sign } from 'node:crypto';
import { appendFileSync } from 'node:fs';

const API = 'https://api.appstoreconnect.apple.com/v1';
const read = (name, fallback = '') => (process.env[name] ?? fallback).trim();
const compact = (name) => read(name).replace(/[\s"]+/g, '');

const keyId = compact('ASC_KEY_ID');
const issuerId = compact('ASC_ISSUER_ID');
const bundleId = read('BUNDLE_ID', 'com.weydaa.app');
const version = read('MARKETING_VERSION');
const build = read('BUILD_NUMBER');
const notes = read('NOTES').slice(0, 4000); // limite d'Apple pour « À tester »
const locale = read('NOTES_LOCALE', 'fr-FR') || 'fr-FR';
const waitMinutes = Number(read('WAIT_MINUTES', '40')) || 40;

function summary(...lines) {
  const file = process.env.GITHUB_STEP_SUMMARY;
  if (file) appendFileSync(file, `${lines.join('\n')}\n`);
}

function fail(message) {
  console.log(`::error title=Notes TestFlight::${message}`);
  summary(
    `**Notes TestFlight non écrites** : ${message}`,
    '',
    'Le build est bien envoyé : saisir les notes à la main (App Store Connect → TestFlight → le build → « À tester »).',
  );
  process.exit(1);
}

function privateKeyPem() {
  const raw = process.env.ASC_KEY_P8 ?? '';
  const pem = raw.includes('BEGIN PRIVATE KEY')
    ? raw
    : Buffer.from(raw.replace(/\s+/g, ''), 'base64').toString('utf8');
  return pem.replace(/\r/g, '');
}

let signingKey = null;

// Jeton d'API App Store Connect : JWT ES256, 15 min (Apple refuse plus de 20 min), un neuf par requête.
function token() {
  const now = Math.floor(Date.now() / 1000);
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const header = encode({ alg: 'ES256', kid: keyId, typ: 'JWT' });
  const payload = encode({ iss: issuerId, iat: now, exp: now + 15 * 60, aud: 'appstoreconnect-v1' });
  const signature = sign('sha256', Buffer.from(`${header}.${payload}`), { key: signingKey, dsaEncoding: 'ieee-p1363' });
  return `${header}.${payload}.${signature.toString('base64url')}`;
}

class ApiError extends Error {
  constructor(status, detail) {
    super(`HTTP ${status} — ${detail}`);
    this.status = status;
  }
}

async function api(method, path, body) {
  const response = await fetch(`${API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(60_000),
  });
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    // corps non JSON : le texte brut sert au message d'erreur
  }
  if (!response.ok) {
    const detail = json?.errors?.map((e) => [e.code, e.title, e.detail].filter(Boolean).join(' ')).join(' | ');
    throw new ApiError(response.status, detail || text.slice(0, 300));
  }
  return json;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const query = (params) => new URLSearchParams(params).toString();

async function findBuild(appId) {
  const params = {
    'filter[app]': appId,
    'filter[version]': build,
    'fields[builds]': 'version,processingState,uploadedDate',
    limit: '10',
  };
  if (version) params['filter[preReleaseVersion.version]'] = version;
  const result = await api('GET', `/builds?${query(params)}`);
  return result?.data?.[0] ?? null;
}

async function writeNotes(buildId) {
  const path = `/builds/${buildId}/betaBuildLocalizations?${query({ 'fields[betaBuildLocalizations]': 'locale,whatsNew', limit: '50' })}`;
  const existing = await api('GET', path);
  const current = existing?.data?.find((item) => item.attributes?.locale === locale);
  if (current) {
    await api('PATCH', `/betaBuildLocalizations/${current.id}`, {
      data: { type: 'betaBuildLocalizations', id: current.id, attributes: { whatsNew: notes } },
    });
  } else {
    await api('POST', '/betaBuildLocalizations', {
      data: {
        type: 'betaBuildLocalizations',
        attributes: { locale, whatsNew: notes },
        relationships: { build: { data: { type: 'builds', id: buildId } } },
      },
    });
  }
}

async function main() {
  const missing = ['ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_KEY_P8', 'BUILD_NUMBER'].filter((name) => !read(name));
  if (missing.length) fail(`variables absentes : ${missing.join(', ')}`);
  if (!notes) {
    console.log('Aucune note fournie : rien à écrire.');
    return;
  }
  try {
    signingKey = createPrivateKey(privateKeyPem());
  } catch {
    fail('ASC_KEY_P8 illisible (contenu du fichier .p8 attendu, ou ce contenu en base64)');
  }

  const apps = await api('GET', `/apps?${query({ 'filter[bundleId]': bundleId, 'fields[apps]': 'bundleId,name' })}`);
  const app = apps?.data?.find((item) => item.attributes?.bundleId === bundleId);
  if (!app) fail(`aucune app « ${bundleId} » dans App Store Connect`);

  console.log(`Attente du build ${version} (${build}) dans App Store Connect (${waitMinutes} min au plus)…`);
  const deadline = Date.now() + waitMinutes * 60_000;
  let found = null;
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      found = found ?? (await findBuild(app.id));
      if (found) {
        await writeNotes(found.id);
        console.log(`Notes écrites (${locale}) sur le build ${version} (${build}).`);
        summary(`- Notes « À tester » écrites dans TestFlight (${locale}).`);
        return;
      }
      console.log('Build pas encore visible (traitement Apple) — nouvel essai dans 30 s.');
    } catch (error) {
      // 409 / 422 : build encore en traitement chez Apple → on réessaie. Toute autre erreur : arrêt.
      if (!(error instanceof ApiError) || ![409, 422].includes(error.status)) throw error;
      lastError = error;
      console.log(`Pas encore possible (${error.message}) — nouvel essai dans 30 s.`);
    }
    await sleep(30_000);
  }
  fail(
    found
      ? `notes refusées par App Store Connect : ${lastError?.message ?? 'délai dépassé'}`
      : `build ${version} (${build}) toujours introuvable après ${waitMinutes} min`,
  );
}

main().catch((error) => fail(error?.message ?? String(error)));
