#!/usr/bin/env node
// Zeptá se Gemini na obrázek a vrátí text – „oči" pro agenta v CI.
//
// Proč to agent potřebuje: agent v GitHub Actions nemá jak zkontrolovat, co
// vlastně vygeneroval. Bez tohohle kroku pozná jen to, že soubor existuje.
//
// Použití:
//   node .forge/vision.mjs sprite.png "Je na obrázku čitelný herní sprite? Co zobrazuje?"
//   node .forge/vision.mjs snimek.png "Je ve scéně vidět hráč a mince?"
//
// Klíč se bere z GEMINI_API_KEY (v Actions z GitHub Secrets). Model se zkouší
// popořadě, protože jednotlivé názvy se v čase mění.
//
// Návratový kód: 0 = odpověď přišla, 1 = nepodařilo se (běh se tím nezhodí,
// jen se to ohlásí – viz použití s `|| true` ve workflow).

import { readFileSync } from 'node:fs';
import { extname } from 'node:path';

const [imagePath, question = 'Co je na obrázku? Odpověz česky a stručně.'] = process.argv.slice(2);
if (!imagePath) {
  console.error('Použití: node .forge/vision.mjs <obrazek> "<dotaz>"');
  process.exit(2);
}

const key = process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY;
if (!key) {
  console.error('Chybí GEMINI_API_KEY – bez něj kontrola obrázku nejde.');
  process.exit(1);
}

const MIME = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.gif': 'image/gif' };
const mime = MIME[extname(imagePath).toLowerCase()] || 'image/png';
const data = readFileSync(imagePath).toString('base64');

const MODELS = ['gemini-flash-latest', 'gemini-2.5-flash', 'gemini-2.0-flash'];

const body = JSON.stringify({
  contents: [{
    parts: [
      { text: question },
      { inline_data: { mime_type: mime, data } },
    ],
  }],
});

let lastError = '';
for (const model of MODELS) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`;
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body,
    });
    const text = await res.text();
    if (!res.ok) {
      lastError = `${model}: HTTP ${res.status} ${text.slice(0, 200)}`;
      continue;
    }
    const json = JSON.parse(text);
    const answer = json?.candidates?.[0]?.content?.parts?.map((p) => p.text).filter(Boolean).join('\n');
    if (!answer) {
      lastError = `${model}: odpověď bez textu (${json?.candidates?.[0]?.finishReason || '?'})`;
      continue;
    }
    console.log(answer.trim());
    process.exit(0);
  } catch (e) {
    lastError = `${model}: ${String(e).slice(0, 200)}`;
  }
}

console.error(`Kontrola obrázku selhala. Poslední chyba: ${lastError}`);
process.exit(1);
