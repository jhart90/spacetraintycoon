#!/usr/bin/env node
// Parity harness (PLAN §9): run the REAL generateGalaxy() from index.html
// headlessly and dump the same structural invariants the Godot side checks
// (v_Godot/space-train-tycoon/Main.gd --check-galaxy).
//
// The JS uses unseeded Math.random(), so this verifies INVARIANT/rule parity
// (not bit-exact coordinates) across N runs. Usage:
//   node js_galaxy_dump.js [runs] [path/to/index.html]
//
// Approach: extract the single <script> block, eval it in a vm context whose
// window/document/etc. are "absorb-everything" Proxies so the browser-only
// top-level setup neither throws nor starts the game loop — it just DEFINES
// generateGalaxy(), which we then call ourselves.

const fs = require("fs");
const vm = require("vm");
const path = require("path");

const RUNS = parseInt(process.argv[2] || "12", 10);
const HTML = process.argv[3] || path.resolve(__dirname, "../../../index.html");

const html = fs.readFileSync(HTML, "utf8");
const m = html.match(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/i);
if (!m) { console.error("No <script> block found in " + HTML); process.exit(2); }
const code = m[1];

// Absorb-everything proxy: any get/call/construct returns itself; coerces to
// NaN/"" so arithmetic/string ops on browser objects never throw at top level.
function makeAbsorb() {
  const f = function () {};
  const p = new Proxy(f, {
    get(_t, prop) {
      if (prop === Symbol.toPrimitive) return () => 0;
      if (prop === "then") return undefined;        // not a thenable
      if (prop === Symbol.iterator) return function* () {}();
      return p;
    },
    set() { return true; },
    apply() { return p; },
    construct() { return p; },
    has() { return true; },
  });
  return p;
}
const absorb = makeAbsorb();

const sandbox = {
  console,
  Math, Date, JSON, Array, Object, String, Number, Boolean, RegExp, Map, Set,
  parseInt, parseFloat, isNaN, isFinite, Symbol, Promise, Error,
  Float32Array, Float64Array, Uint8Array, Int32Array, Uint32Array, ArrayBuffer,
  setTimeout: () => 0, clearTimeout: () => {}, setInterval: () => 0, clearInterval: () => {},
  requestAnimationFrame: () => 0, cancelAnimationFrame: () => {},
  fetch: () => ({ then: () => ({ catch: () => {} }), catch: () => {} }),
  performance: { now: () => 0 },
  navigator: { userAgent: "node", language: "en" },
  location: { href: "", search: "" },
  localStorage: { getItem: () => null, setItem: () => {}, removeItem: () => {} },
  addEventListener: () => {}, removeEventListener: () => {},
  Audio: function () { return absorb; }, Image: function () { return absorb; },
  alert: () => {}, prompt: () => null,
};
sandbox.window = sandbox;
sandbox.globalThis = sandbox;
sandbox.self = sandbox;
sandbox.document = absorb;

const ctx = vm.createContext(sandbox);
try {
  vm.runInContext(code, ctx, { filename: "index.html#script", timeout: 60000 });
} catch (e) {
  console.error("Top-level eval threw (generateGalaxy may still be defined):", e.message);
}

if (typeof ctx.generateGalaxy !== "function") {
  console.error("generateGalaxy is not defined after eval — shim insufficient.");
  process.exit(3);
}

const HOME_BIOMES = ["lava", "resort", "desert", "agri", "rocky", "chemical"];
const SYS_GAP = 800;

function invariants(g) {
  const stars = g.stars, planets = g.planets;
  const home = stars[g.homeStarId];
  const homePlanets = home.planetIds.map((id) => planets.find((p) => p.id === id));
  const biomes = homePlanets.map((p) => p.type.id);
  const orijen = homePlanets[1];
  const relics = planets.filter((p) => p.isAlienRelic);

  // system radii + nearest-to-home (the intentionally-tight pair we exclude)
  const sysR = new Array(stars.length).fill(0);
  for (const p of planets) sysR[p.starId] = Math.max(sysR[p.starId], p.orbitRadius + p.radius);
  let nearIdx = -1, nearD = Infinity;
  for (let i = 0; i < stars.length; i++) {
    if (i === g.homeStarId) continue;
    const d = Math.hypot(stars[i].x - home.x, stars[i].y - home.y);
    if (d < nearD) { nearD = d; nearIdx = i; }
  }
  let overlaps = 0;
  for (let i = 0; i < stars.length; i++)
    for (let j = i + 1; j < stars.length; j++) {
      if ((i === g.homeStarId && j === nearIdx) || (i === nearIdx && j === g.homeStarId)) continue;
      const d = Math.hypot(stars[j].x - stars[i].x, stars[j].y - stars[i].y);
      if (d < (sysR[i] + sysR[j] + SYS_GAP) * 0.99) overlaps++;
    }

  const orijenP = planets.find((p) => p.id === g.origenId);
  const populated = planets.filter((p) => (p.population || 0) > 0).length;
  const withDemand = planets.filter((p) => Object.keys(p.demandRate || {}).length > 0).length;

  return {
    stars: stars.length, planets: planets.length, blackHoles: (g.blackHoles || []).length,
    homeName: home.name, homeSize: home.size,
    homePlanetCount: homePlanets.length,
    homeBiomesMatch: JSON.stringify(biomes) === JSON.stringify(HOME_BIOMES),
    orijenStarterL: !!orijen && orijen.isStarter && orijen.name === "Orijen" && orijen.size === "L",
    relics: relics.length, relicsAllStationed: relics.every((p) => p.hasStation),
    overlaps,
    bhClearOfHome: (g.blackHoles || []).every((b) => Math.hypot(b.x, b.y) >= 35000),
    orijenPop: orijenP ? orijenP.population : 0,
    orijenHealth: orijenP ? orijenP.economicHealth : 0,
    orijenPassSupply: orijenP ? (orijenP.supplyRate && orijenP.supplyRate.passengers) || 0 : 0,
    populated, withDemand,
  };
}

const agg = { stars: [], planets: [], blackHoles: [], relics: [], orijenPop: [], populated: [] };
let failRuns = 0;
for (let r = 0; r < RUNS; r++) {
  const g = ctx.generateGalaxy();
  const iv = invariants(g);
  agg.stars.push(iv.stars); agg.planets.push(iv.planets);
  agg.blackHoles.push(iv.blackHoles); agg.relics.push(iv.relics);
  agg.orijenPop.push(iv.orijenPop); agg.populated.push(iv.populated);
  const ok = iv.homeName === "Gigi Prime" && iv.homeSize === "M" && iv.homePlanetCount === 6 &&
    iv.homeBiomesMatch && iv.orijenStarterL && iv.relics <= 16 && iv.relicsAllStationed &&
    iv.overlaps === 0 && iv.blackHoles <= 4 && iv.bhClearOfHome &&
    iv.orijenPop >= 1e6 && iv.orijenPop <= 1e7 + 1 &&
    iv.orijenHealth >= 0.3 && iv.orijenHealth <= 1.5 && iv.orijenPassSupply > 0 &&
    iv.populated > 0 && iv.withDemand > 0;
  if (!ok) { failRuns++; console.log("  RUN " + r + " FAIL:", JSON.stringify(iv)); }
}
const rng = (a) => `${Math.min(...a)}..${Math.max(...a)}`;
console.log("=== JS generateGalaxy invariants over " + RUNS + " runs ===");
console.log("stars range:      " + rng(agg.stars));
console.log("planets range:    " + rng(agg.planets));
console.log("blackHoles range: " + rng(agg.blackHoles));
console.log("relics range:     " + rng(agg.relics));
console.log("orijenPop range:  " + rng(agg.orijenPop));
console.log("populated range:  " + rng(agg.populated));
console.log("=== INVARIANT PARITY " + (failRuns === 0 ? "PASS" : "FAIL (" + failRuns + " runs)") + " ===");
process.exit(failRuns === 0 ? 0 : 1);
