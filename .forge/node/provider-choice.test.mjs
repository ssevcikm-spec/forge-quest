#!/usr/bin/env node
// Test volby poskytovatele – bez sítě, bez klíčů. Ověřuje tři věci, na kterých
// stojí opakované pokusy agenta:
//   1) rotace podle run_key je deterministická (stejný běh = stejná volba),
//   2) různé run_key dají různé pořadí (pokusy se nepotkají se stejným modelem),
//   3) „--next" po neúspěchu opravdu přeskočí na DALŠÍHO poskytovatele.
//
// Použití: node .forge/node/provider-choice.test.mjs

import assert from "node:assert/strict";
import { fnv1a, rotateOrder, startIndex, probeOrder } from "./provider-choice.mjs";

const P = [{ name: "a" }, { name: "b" }, { name: "c" }, { name: "d" }, { name: "e" }];
let checks = 0;
const ok = (popis) => { checks++; console.log(`  OK   ${popis}`); };

// 1) determinismus
const r1 = rotateOrder(P, "run-1");
const r2 = rotateOrder(P, "run-1");
assert.deepEqual(r1, r2);
ok("stejný run_key → stejné pořadí (běh je reprodukovatelný)");

// bez seedu se nic nemění (chování před rotací)
assert.deepEqual(rotateOrder(P, ""), P);
assert.deepEqual(rotateOrder(P, null), P);
ok("bez run_key zůstává pořadí z providers.json");

// 2) rotace opravdu točí – na 20 různých běhů musí vyjít aspoň 3 různé začátky
const zacatky = new Set();
for (let i = 0; i < 20; i++) zacatky.add(rotateOrder(P, `run-${i}`)[0].name);
assert.ok(zacatky.size >= 3, `různých začátků: ${zacatky.size}`);
ok(`různé run_key → různé začátky (${zacatky.size} z 5 poskytovatelů)`);

// rotace je jen posun – všichni poskytovatelé zůstávají
assert.deepEqual([...rotateOrder(P, "x")].sort((a, b) => a.name.localeCompare(b.name)), P);
ok("rotace nikoho neztratí (je to jen posun pořadí)");

// 3) --next přeskočí na dalšího
const order = rotateOrder(P, "run-1");
const prvni = order[0].name;
const druhy = probeOrder(order, startIndex(order, prvni, true))[0].name;
assert.notEqual(druhy, prvni);
assert.equal(druhy, order[1].name);
ok(`--next po '${prvni}' zkusí '${druhy}' (jiný model)`);

// --next se z neznámého jména chová jako první pokus
assert.equal(startIndex(order, "neexistuje", true), 0);
ok("neznámý poskytovatel v provider.json → začni od začátku");

// pořadí zkoušení projde všechny právě jednou (žádné zacyklení)
const poradi = probeOrder(order, 2).map((p) => p.name);
assert.equal(new Set(poradi).size, P.length);
assert.equal(poradi.length, P.length);
ok("pořadí zkoušení projde každého poskytovatele právě jednou");

// hash se nesmí zbláznit na delším vstupu
assert.equal(typeof fnv1a("26484181-47eb-4db5-adc7-fa8b5c457d9b"), "number");
assert.ok(fnv1a("a") !== fnv1a("b"));
ok("hash dává různá čísla pro různé vstupy");

console.log(`\n${checks} kontrol, 0 selhání`);
