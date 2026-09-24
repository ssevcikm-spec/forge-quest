#!/usr/bin/env node
// Vybere prvního bezplatného poskytovatele LLM, který opravdu odpovídá, a předá
// jeho nastavení dalším krokům workflow (přes GITHUB_ENV) i nástroji aider.
//
// Proč: free tiery padají na 429 a jednotlivé služby mají výpadky. Místo aby
// agent spadl, zkusí se řetězec providerů popořadě a použije se první funkční.
//
// Použití v Actions:
//   node .forge/pick-provider.mjs
// a dál už stačí jen $OPENAI_API_BASE, $OPENAI_API_KEY, $FORGE_MODEL.

import { readFileSync, appendFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const config = JSON.parse(readFileSync(join(HERE, 'providers.json'), 'utf8'));

async function probe(baseUrl, apiKey, model) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 45000);
  try {
    const res = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      signal: ctrl.signal,
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'content-type': 'application/json',
        // OpenRouter si potrpí na identifikaci aplikace
        'HTTP-Referer': 'https://github.com/',
        'X-Title': 'forge-agent',
      },
      body: JSON.stringify({
        model,
        messages: [{ role: 'user', content: 'ping' }],
        max_tokens: 8,
      }),
    });
    const text = await res.text();
    if (!res.ok) return { ok: false, reason: `HTTP ${res.status}: ${text.slice(0, 160)}` };
    return { ok: true, answer: text.slice(0, 80) };
  } catch (e) {
    return { ok: false, reason: String(e).slice(0, 160) };
  } finally {
    clearTimeout(timer);
  }
}

const chosen = [];
for (const p of config.providers) {
  const apiKey = process.env[p.keyEnv];
  if (!apiKey) {
    console.log(`- ${p.name}: přeskočeno (chybí ${p.keyEnv})`);
    continue;
  }
  for (const model of p.models) {
    const r = await probe(p.baseUrl, apiKey, model);
    if (r.ok) {
      console.log(`✓ ${p.name} / ${model} odpovídá – použiji tento model`);
      chosen.push({ provider: p.name, baseUrl: p.baseUrl, model, keyEnv: p.keyEnv, apiKey });
      break;
    }
    console.log(`✗ ${p.name} / ${model}: ${r.reason}`);
  }
  if (chosen.length) break;
}

if (!chosen.length) {
  console.error('CHYBA: žádný z bezplatných poskytovatelů neodpověděl.');
  console.error('Zkontroluj, že jsou v GitHub Secrets GEMINI_API_KEY / GROQ_API_KEY / OPENROUTER_API_KEY.');
  process.exit(1);
}

const c = chosen[0];
const envFile = process.env.GITHUB_ENV;
const lines = [
  `OPENAI_API_BASE=${c.baseUrl}`,
  `OPENAI_API_KEY=${c.apiKey}`,
  `FORGE_MODEL=${c.model}`,
  `FORGE_PROVIDER=${c.provider}`,
];
if (envFile) appendFileSync(envFile, lines.join('\n') + '\n');
writeFileSync(join(HERE, 'provider.json'), JSON.stringify({
  provider: c.provider, base_url: c.baseUrl, model: c.model, picked_at: new Date().toISOString(),
}, null, 2));

console.log(`\nVybráno: ${c.provider} → ${c.model}`);
if (!envFile) console.log('(GITHUB_ENV není nastaven – běžím mimo CI, hodnoty výše se nikam nezapsaly)');
