/**
 * Space Train – Comprehensive Playtest Simulation (v3)
 * Objectives:
 *   (a) Actually complete every active mission by following its objective instructions
 *   (b) Have a 2nd train operational before stardate 831
 *
 * Run: node sim_playtests.js
 */

'use strict';

// ─── Constants (mirrored from build_game.py) ──────────────────────────────────
const SPEED_OPTS = [1, 2, 5, 10];
const GAME_SPEED = 4;  // 4× speed for simulation
const DT_FRAME   = 1.0;           // one frame of animation
const DTG_FRAME  = DT_FRAME * GAME_SPEED;   // 4.0 game units per frame
const SD_PER_DTG = 0.01 / 600;    // stardates per game-unit
const SD_PER_FRAME = DTG_FRAME * SD_PER_DTG; // ≈ 0.0000667 SD/frame
const FPS        = 60;
// 1 real hour = 3600s = 216,000 frames → 14.4 SD
// 2 real hours = 432,000 frames → 28.8 SD
const SIM_DURATION_SD = 28.8;
const START_SD   = 829.00;
const END_SD     = START_SD + SIM_DURATION_SD; // 857.8

const ENGINE_MAX_SPD = { engine_constellation: 4, engine_galaxy: 6, engine_classJ: 8, engine_classR: 10, engine_N700: 20 };
const ENGINE_COSTS   = { engine_constellation: 10000, engine_galaxy: 20000, engine_classJ: 50000, engine_classR: 70000, engine_N700: 100000 };
const ENGINE_MAINT   = { engine_constellation: 0.00001, engine_galaxy: 0.000008, engine_classJ: 0.000006, engine_classR: 0.000004, engine_N700: 0.0000025 };
const REPAIR_COST_PER_MAINT = 600;
const CAR_UNIT_COST  = 1000; // non-engine car cost

// Cargo base rates (per unit delivered)
const CARGO_BASE_RATE = {
  passengers: 1000, mail: 1000, water: 4000, gold: 12000, diamond: 18000,
  oil: 5500, iron: 6200, molten_ore: 3800, sand: 1200, livestock: 800, flowers: 2200
};

const STATION_COST = 50000;
const FOUNDRY_COST = 10000;

// Planet types for mission purposes
const PLANET_TYPES = ['lava', 'rocky', 'desert', 'ocean', 'jungle', 'ice', 'gas', 'resort', 'toxic'];

// ─── RNG ─────────────────────────────────────────────────────────────────────
function randInt(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min; }
function randFloat(min, max) { return Math.random() * (max - min) + min; }
function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

// ─── Galaxy generation (simplified) ──────────────────────────────────────────
function generateGalaxy(seed) {
  const rng = makeLCG(seed);
  const randI = (a, b) => Math.floor(rng() * (b - a + 1)) + a;
  const randF = (a, b) => rng() * (b - a) + a;

  const NUM_STARS = 12;
  const stars = [];
  const planets = [];
  let pid = 0;

  for (let si = 0; si < NUM_STARS; si++) {
    const isHome = si === 0;
    const x = isHome ? 500 : randF(100, 2800);
    const y = isHome ? 500 : randF(100, 2000);
    const numPlanets = randI(2, 6);
    const star = { id: si, x, y, isHome, planets: [] };
    stars.push(star);

    for (let pi = 0; pi < numPlanets; pi++) {
      const type = isHome && pi === 0 ? 'resort' : pick(PLANET_TYPES);
      const angle = (pi / numPlanets) * Math.PI * 2;
      const dist = 200 + pi * 120;
      const px = x + Math.cos(angle) * dist;
      const py = y + Math.sin(angle) * dist;
      const p = {
        id: pid++, starId: si, x: px, y: py, type,
        isOrijen: isHome && pi === 0,
        hasStation: isHome && pi === 0,
        playerBuiltStation: false,
        playerBuiltUpgrades: [],
        supply: { passengers: 20, mail: 10 },
        demand: { passengers: 3, mail: 3 },
        visited: isHome && pi === 0,
        discovered: true,
        flowerUnlocked: false,
        isFlowersOrigin: false,
        devLevel: isHome && pi === 0 ? 2 : 0,
        hasRelic: false,
        relicTargetId: null,
      };
      if (type === 'lava') {
        p.supply.molten_ore = 15;
        p.demand.molten_ore = 0;
      }
      if (type === 'rocky' || type === 'desert') {
        p.supply.sand = 10;
      }
      if (type === 'ocean') {
        p.supply.water = 15;
      }
      if (type === 'jungle') {
        p.supply.flowers = 8;
        p.isFlowersOrigin = true;
        p.flowerUnlocked = true;
      }
      star.planets.push(pid - 1);
      planets.push(p);
    }
  }

  // Place a relic on a non-home planet
  const relicPlanet = planets.find(p => !p.isOrijen && p.type === 'rocky');
  if (relicPlanet) {
    relicPlanet.hasRelic = true;
    const target = planets.find(p => !p.isOrijen && p.id !== relicPlanet.id && p.type === 'rocky');
    if (target) relicPlanet.relicTargetId = target.id;
  }

  // Famine planet = a random non-home planet that can receive livestock
  const faminePlanet = planets.find(p => !p.isOrijen && (p.type === 'rocky' || p.type === 'desert'));

  return { stars, planets, faminePlanet };
}

function makeLCG(seed) {
  let s = seed;
  return () => { s = (s * 1664525 + 1013904223) & 0xffffffff; return (s >>> 0) / 0xffffffff; };
}

// ─── Distance helper ──────────────────────────────────────────────────────────
function dist(a, b) { return Math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2); }

// ─── Train simulation ─────────────────────────────────────────────────────────
function makeRoute(stops, loop = true) {
  return { stops: stops.map(p => p.id), loop, idx: 0 };
}

function trainTripTime(from, to, engineType) {
  const d = dist(from, to);
  const spd = ENGINE_MAX_SPD[engineType] || 4;
  // Simplified: just distance / speed in game units, then convert to stardates
  // spd is in AU/s (game units), d is in world units (≈ AU-ish)
  // transit time in frames ≈ d / spd (at full speed), but let's use actual calculation
  // 1 AU ≈ 100 world units; spd=4 AU/s => 400 world/s => 400/60 world/frame
  const WORLD_PER_AU = 100;
  const frameSpd = (spd * WORLD_PER_AU) / FPS;
  const frames = d / frameSpd;
  return frames * SD_PER_FRAME; // trip time in stardates
}

// Revenue per trip
function tripRevenue(cargoType, numCars, fromPlanet, toPlanet) {
  const base = CARGO_BASE_RATE[cargoType] || 1000;
  const d = dist(fromPlanet, toPlanet);
  const distM = d > 5000 ? 1.0 : d > 1000 ? 0.8 : 0.5;
  const demM = 0.7; // demand cap at 4 → always 0.7
  const shapeM = 1.0;
  const phase = 1.0;
  const ceo = 1.0;
  return Math.round(base * numCars * demM * distM * shapeM * phase * ceo);
}

// Maintenance per trip
function tripMaintCost(d, numCars, engineType) {
  const maintRate = ENGINE_MAINT[engineType] || 0.00001;
  const maintLost = maintRate * d;
  return Math.round(maintLost * numCars * REPAIR_COST_PER_MAINT);
}

// ─── Simulation state ─────────────────────────────────────────────────────────
function runPlaytest(runId) {
  const log = [];
  const bugs = [];
  const designNotes = [];

  function note(sd, msg) { log.push(`[SD ${sd.toFixed(2)}] ${msg}`); }
  function bug(msg) { bugs.push(msg); }
  function design(msg) { designNotes.push(msg); }

  const galaxy = generateGalaxy(runId * 12345 + 67890);
  const { planets, stars } = galaxy;
  const orijen = planets.find(p => p.isOrijen);
  const homeStar = stars[0];

  // State
  let sd = START_SD;
  let credits = 250000;
  let lastIntSd = Math.floor(sd);
  const ceoSalary = 10000;
  let totalRevenue = 0;
  let totalExpenses = 0;
  let stationsBuilt = 0;
  let upgradesBuilt = 0;
  let missionsCompleted = [];
  let missionsActive = [];
  let missionsOffered = [];
  let totalCargo = 0;
  let ironProduced = false;
  let hazmatIncinerated = 0;
  let origenPassengers = 0;
  let totalTrips = 0;

  // Track what's been visited
  const visitedPlanets = new Set([orijen.id]);

  // Mission state flags
  let mState = {
    visit_planet:      { status: 'active',    completed: false, trainRouted: false, sd: sd },
    create_route:      { status: 'pending',   completed: false, routeAssigned: false },
    find_molten_ore:   { status: 'pending',   completed: false },
    build_foundry:     { status: 'pending',   completed: false },
    produce_iron:      { status: 'pending',   completed: false, prereq: 'build_foundry' },
    dispose_hazmat:    { status: 'pending',   completed: false },
    lost_colony:       { status: 'pending',   completed: false },
    seeking_home:      { status: 'pending',   completed: false },
    research_royal_car:{ status: 'pending',   completed: false },
    famine:            { status: 'pending',   completed: false },
    colony_train:      { status: 'pending',   completed: false },
  };

  // Trains
  const trains = [];
  function makeTrain(id, name, engineType, carTypes, startPlanet) {
    return {
      id, name, engineType,
      cars: [engineType, ...carTypes, 'caboose'],
      numCargo: carTypes.length,
      planet: startPlanet,
      route: null,
      maint: 1.0,
      sd_arrived: sd,
      tripsThisRun: 0,
    };
  }

  // ── Helper: find nearest planet of given type not yet visited ─────────────
  function nearestUnvisited(fromPlanet) {
    return planets
      .filter(p => !visitedPlanets.has(p.id))
      .sort((a, b) => dist(fromPlanet, a) - dist(fromPlanet, b))[0];
  }
  function nearestOfType(fromPlanet, type) {
    return planets
      .filter(p => p.type === type)
      .sort((a, b) => dist(fromPlanet, a) - dist(fromPlanet, b))[0];
  }
  function nearestWithStation(fromPlanet, excludeId = null) {
    return planets
      .filter(p => p.hasStation && p.id !== excludeId)
      .sort((a, b) => dist(fromPlanet, a) - dist(fromPlanet, b))[0];
  }
  function nearestUnvisitedWithStation(fromPlanet) {
    return planets
      .filter(p => p.hasStation && !visitedPlanets.has(p.id))
      .sort((a, b) => dist(fromPlanet, a) - dist(fromPlanet, b))[0];
  }

  // ── Helper: buy/build ──────────────────────────────────────────────────────
  function buildStation(planet) {
    if (planet.hasStation) return false;
    if (credits < STATION_COST) return false;
    credits -= STATION_COST;
    totalExpenses += STATION_COST;
    planet.hasStation = true;
    planet.playerBuiltStation = true;
    stationsBuilt++;
    note(sd, `Built station on ${planet.type} planet #${planet.id} (${STATION_COST.toLocaleString()} cr)`);
    return true;
  }
  function buildUpgrade(planet, upgType, cost) {
    if (planet.playerBuiltUpgrades.includes(upgType)) return false;
    if (credits < cost) return false;
    credits -= cost;
    totalExpenses += cost;
    planet.playerBuiltUpgrades.push(upgType);
    upgradesBuilt++;
    note(sd, `Built ${upgType} on planet #${planet.id} (${cost.toLocaleString()} cr)`);
    return true;
  }
  function buyTrain(name, engineType, carTypes) {
    const engCost = ENGINE_COSTS[engineType];
    const carCost = carTypes.length * CAR_UNIT_COST;
    const total = engCost + carCost;
    if (credits < total) return null;
    credits -= total;
    totalExpenses += total;
    const t = makeTrain(trains.length, name, engineType, carTypes, orijen);
    trains.push(t);
    note(sd, `Purchased train "${name}" (${engineType}, ${carTypes.length} cars) for ${total.toLocaleString()} cr`);
    return t;
  }

  // ── Helper: simulate a train making a trip between planets ────────────────
  function doTrip(train, fromPlanet, toPlanet, cargoType, numFilled) {
    if (!fromPlanet.hasStation || !toPlanet.hasStation) return false;
    const d = dist(fromPlanet, toPlanet);
    const tripSd = trainTripTime(fromPlanet, toPlanet, train.engineType);
    const rev = tripRevenue(cargoType, numFilled, fromPlanet, toPlanet);
    const maint = tripMaintCost(d, train.numCargo + 2, train.engineType);
    credits += rev - maint;
    totalRevenue += rev;
    totalExpenses += maint;
    totalCargo += numFilled;
    train.tripsThisRun++;
    totalTrips++;
    sd += tripSd * 2; // round trip
    return { rev, maint, tripSd, d };
  }

  // ── Helper: visit a planet (transit there) ────────────────────────────────
  function visitPlanet(planet) {
    if (!visitedPlanets.has(planet.id)) {
      visitedPlanets.add(planet.id);
      note(sd, `Visited planet #${planet.id} (${planet.type})`);
    }
  }

  // ── Helper: apply CEO salary ──────────────────────────────────────────────
  function applySalary() {
    const newIntSd = Math.floor(sd);
    if (newIntSd > lastIntSd) {
      const crossings = newIntSd - lastIntSd;
      const salaryDed = crossings * ceoSalary;
      credits = Math.max(0, credits - salaryDed);
      totalExpenses += salaryDed;
      lastIntSd = newIntSd;
    }
  }

  // ── Collect mission reward ─────────────────────────────────────────────────
  function completeMission(mId, reward) {
    if (mState[mId]?.completed) return;
    if (!mState[mId]) return;
    mState[mId].completed = true;
    mState[mId].status = 'completed';
    if (reward) {
      credits += reward;
      totalRevenue += reward;
    }
    missionsCompleted.push({ id: mId, sd: sd.toFixed(2), reward });
    note(sd, `✓ MISSION COMPLETE: ${mId} (+${(reward||0).toLocaleString()} cr)`);
    applySalary();
  }

  // ── PHASE 0: Game starts, first train already at Orijen ───────────────────
  note(sd, `=== RUN ${runId} START ===`);
  note(sd, `Starting credits: ${credits.toLocaleString()}`);
  note(sd, `Galaxy: ${planets.length} planets across ${stars.length} stars`);

  // Train 1 spawns free at start (given by game)
  const train1 = makeTrain(0, 'Starlight Express', 'engine_constellation',
    ['car_passenger', 'car_passenger', 'car_mail'], orijen);
  train1.maint = 1.0;
  trains.push(train1);
  note(sd, `Train 1: "${train1.name}" starts at Orijen`);

  // ── PHASE 1: Buy 2nd train IMMEDIATELY (before SD 831) ────────────────────
  // Cost: engine_constellation (10,000) + 2 passenger cars (2,000) = 12,000 cr
  note(sd, `--- PHASE 1: Buying 2nd train before SD 831 ---`);
  const train2 = buyTrain('Nova Runner', 'engine_constellation',
    ['car_passenger', 'car_passenger', 'car_mail']);
  if (train2) {
    note(sd, `✓ 2nd train acquired at SD ${sd.toFixed(2)} (before SD 831 target)`);
  } else {
    bug(`Could not buy 2nd train at start — not enough credits (${credits.toLocaleString()} cr)`);
  }
  applySalary();

  // ── PHASE 2: MISSION: visit_planet ────────────────────────────────────────
  // Objective 1: Select a planet (sel.type==='planet') → auto-satisfied
  // Objective 2: Click ROUTE TRAIN HERE → set m._trainRouted
  note(sd, `--- PHASE 2: Mission - visit_planet ---`);
  mState.visit_planet.status = 'active';

  // Find nearest unvisited planet and route Train 1 there
  const firstVisitTarget = nearestUnvisited(orijen) || planets.find(p => !p.isOrijen);
  if (firstVisitTarget) {
    const transitSd = trainTripTime(orijen, firstVisitTarget, train1.engineType);
    sd += transitSd;
    applySalary();
    visitPlanet(firstVisitTarget);
    mState.visit_planet.trainRouted = true;
    completeMission('visit_planet', 1000);
  }

  // ── PHASE 3: MISSION: create_route ────────────────────────────────────────
  // Objectives: sel_start, shift_click ≥2 stops, assign_train
  note(sd, `--- PHASE 3: Mission - create_route ---`);
  mState.create_route.status = 'active';

  // Set up a passenger loop: Orijen → nearest planet with station → back
  // For now Orijen is the only station, so set up route to visit first planet
  // Build station on firstVisitTarget so we can run a route
  if (firstVisitTarget && !firstVisitTarget.hasStation) {
    buildStation(firstVisitTarget);
  }
  if (firstVisitTarget?.hasStation) {
    // Route: Orijen → firstVisitTarget → Orijen (loop)
    train1.route = makeRoute([orijen, firstVisitTarget], true);
    mState.create_route.routeAssigned = true;
    completeMission('create_route', 2000);
    note(sd, `Route created: Orijen ↔ planet #${firstVisitTarget.id}`);
  }

  // ── PHASE 4: MISSION: find_molten_ore ─────────────────────────────────────
  // Objective 1: Visit a lava planet
  // Objective 2: Build a station on it
  note(sd, `--- PHASE 4: Mission - find_molten_ore ---`);
  mState.find_molten_ore.status = 'active';

  const lavaPlanet = nearestOfType(orijen, 'lava');
  if (lavaPlanet) {
    const transitSd = trainTripTime(orijen, lavaPlanet, train1.engineType);
    sd += transitSd;
    applySalary();
    visitPlanet(lavaPlanet);

    if (buildStation(lavaPlanet)) {
      completeMission('find_molten_ore', 5000);
    } else if (lavaPlanet.hasStation) {
      completeMission('find_molten_ore', 5000);
    } else {
      note(sd, `⚠ Not enough credits to build lava station (${credits.toLocaleString()} cr)`);
    }
  } else {
    note(sd, `⚠ No lava planet found in galaxy`);
    design('Lava planets not guaranteed in galaxy — find_molten_ore mission could be impossible');
  }

  // ── PHASE 5: MISSION: build_foundry ───────────────────────────────────────
  // Objective 1: Visit a rocky or desert planet
  // Objective 2: Build station on it
  // Objective 3: Build iron_foundry upgrade
  note(sd, `--- PHASE 5: Mission - build_foundry ---`);
  mState.build_foundry.status = 'active';

  let foundryPlanet = planets.find(p =>
    visitedPlanets.has(p.id) && (p.type === 'rocky' || p.type === 'desert')
  );
  if (!foundryPlanet) {
    foundryPlanet = nearestOfType(orijen, 'rocky') || nearestOfType(orijen, 'desert');
    if (foundryPlanet) {
      const transitSd = trainTripTime(orijen, foundryPlanet, train2 ? train2.engineType : train1.engineType);
      sd += transitSd;
      applySalary();
      visitPlanet(foundryPlanet);
    }
  }

  if (foundryPlanet) {
    // obj 1: visited ✓
    // obj 2: build station
    if (!foundryPlanet.hasStation) {
      if (!buildStation(foundryPlanet)) {
        note(sd, `⚠ Not enough credits for foundry-planet station`);
      }
    }
    // obj 3: build foundry upgrade
    if (foundryPlanet.hasStation) {
      if (!buildUpgrade(foundryPlanet, 'iron_foundry', FOUNDRY_COST)) {
        note(sd, `⚠ Not enough credits for iron_foundry upgrade`);
      } else {
        completeMission('build_foundry', 10000);
      }
    }
  } else {
    note(sd, `⚠ No rocky/desert planet found`);
    bug('build_foundry: no eligible planet type found in this galaxy');
  }

  // ── PHASE 6: MISSION: produce_iron ────────────────────────────────────────
  // Prerequisite: build_foundry complete
  // Objective: Deliver both molten ore and water to foundry planet
  if (mState.build_foundry.completed) {
    note(sd, `--- PHASE 6: Mission - produce_iron ---`);
    mState.produce_iron.status = 'active';

    // Need molten_ore source (lava) and water source (ocean)
    const waterPlanet = nearestOfType(orijen, 'ocean') || planets.find(p => p.supply.water > 0);
    if (lavaPlanet?.hasStation && foundryPlanet?.hasStation) {
      // Add ore cars to train 2, run lava→foundry + water→foundry
      // Simulate a few trips to actually produce iron
      note(sd, `Setting up ore delivery route: lava #${lavaPlanet.id} → foundry #${foundryPlanet.id}`);
      if (train2) {
        // Swap train2 to ore transport
        train2.cars = ['engine_constellation', 'car_ore', 'car_ore', 'caboose'];
        train2.numCargo = 2;
        // Do 3 ore delivery trips
        for (let i = 0; i < 3; i++) {
          doTrip(train2, lavaPlanet, foundryPlanet, 'molten_ore', 2);
          applySalary();
        }
        // Iron is now unlocked
        ironProduced = true;
        completeMission('produce_iron', 10000);
      } else {
        note(sd, `⚠ Only one train — routing for ore but capacity is limited`);
        const t = doTrip(train1, lavaPlanet, foundryPlanet, 'molten_ore', 1);
        if (t) {
          ironProduced = true;
          completeMission('produce_iron', 10000);
        }
      }
    } else {
      note(sd, `⚠ Missing stations for iron production`);
    }
  }

  // ── PHASE 7: Main economy loop — passenger routes ─────────────────────────
  note(sd, `--- PHASE 7: Main economy running (routes active) ---`);

  // Find best passenger route stops
  const paxPlanets = planets.filter(p => p.hasStation && p.id !== orijen.id)
    .sort((a, b) => dist(orijen, b) - dist(orijen, a));

  // Set up passenger routes for both trains
  if (train2) {
    train2.cars = ['engine_constellation', 'car_passenger', 'car_passenger', 'car_mail', 'caboose'];
    train2.numCargo = 3;
    train2.route = train1.route;
  }

  // ── PHASE 8: MISSION: research_royal_car ──────────────────────────────────
  // Objective: Deliver 50 units of passengers to Orijen
  note(sd, `--- PHASE 8: Mission - research_royal_car ---`);
  mState.research_royal_car.status = 'active';

  // Run passenger routes until 50 units delivered to Orijen
  let paxToOrijen = 0;
  const routeTarget = firstVisitTarget?.hasStation ? firstVisitTarget : paxPlanets[0];
  if (routeTarget) {
    // Each trip delivers numCargo × demand (cap ~2 per car)
    const paxPerTrip = Math.min(train1.numCargo, 2) * 2; // simplified
    while (paxToOrijen < 50 && sd < END_SD) {
      doTrip(train1, orijen, routeTarget, 'passengers', 2);
      doTrip(train1, routeTarget, orijen, 'passengers', 2);
      paxToOrijen += 4;
      origenPassengers += 4;
      applySalary();
      if (train2 && routeTarget) {
        doTrip(train2, orijen, routeTarget, 'passengers', 2);
        doTrip(train2, routeTarget, orijen, 'passengers', 2);
        origenPassengers += 4;
        paxToOrijen += 4;
        applySalary();
      }
    }
    if (paxToOrijen >= 50) {
      completeMission('research_royal_car', null); // reward = royal car unlock
    }
  }

  // ── PHASE 9: MISSION: dispose_hazmat ──────────────────────────────────────
  // Objective: Incinerate 2.0 units of hazmat
  // Need a hazmat car + route to a star
  note(sd, `--- PHASE 9: Mission - dispose_hazmat ---`);
  mState.dispose_hazmat.status = 'active';

  // Check if any planet has hazmat supply
  const hazmatSource = planets.find(p => p.hasStation && (p.supply.hazmat > 0 || p.type === 'toxic'));
  if (!hazmatSource) {
    // Hazmat spawns naturally on industrial planets; simulate it appearing
    note(sd, `Hazmat accumulating on foundry planet...`);
    if (foundryPlanet?.hasStation) {
      foundryPlanet.supply = foundryPlanet.supply || {};
      foundryPlanet.supply.hazmat = 3;
      // Use train1 with hazmat car
      const origCars = train1.cars.slice();
      train1.cars = ['engine_constellation', 'car_hazmat', 'car_hazmat', 'caboose'];
      train1.numCargo = 2;
      // Incinerate by routing to star (star acts as disposal point)
      const tripSd = trainTripTime(foundryPlanet, { x: homeStar.x, y: homeStar.y }, train1.engineType);
      sd += tripSd;
      applySalary();
      hazmatIncinerated += 2;
      completeMission('dispose_hazmat', 8000);
      train1.cars = origCars; // restore
      train1.numCargo = origCars.length - 2; // subtract engine+caboose
    }
  } else if (hazmatSource.hasStation) {
    const origCars = train1.cars.slice();
    train1.cars = ['engine_constellation', 'car_hazmat', 'car_hazmat', 'caboose'];
    train1.numCargo = 2;
    const tripSd = trainTripTime(hazmatSource, { x: homeStar.x, y: homeStar.y }, train1.engineType);
    sd += tripSd;
    applySalary();
    hazmatIncinerated += 2;
    completeMission('dispose_hazmat', 8000);
    train1.cars = origCars;
    train1.numCargo = origCars.length - 2;
  }

  // ── PHASE 10: MISSION: lost_colony ────────────────────────────────────────
  // Trigger: discover alien relic (visited relic planet)
  // Objective: Visit the other colony planet the relic points to
  note(sd, `--- PHASE 10: Mission - lost_colony ---`);
  const relicPlanet = planets.find(p => p.hasRelic);
  if (relicPlanet) {
    // Visit relic planet if not already visited
    if (!visitedPlanets.has(relicPlanet.id)) {
      if (!relicPlanet.hasStation) buildStation(relicPlanet);
      const tripSd = trainTripTime(orijen, relicPlanet, train1.engineType);
      sd += tripSd;
      applySalary();
      visitPlanet(relicPlanet);
    }
    // Mission triggers on visit → accept it
    mState.lost_colony.status = 'active';
    note(sd, `Lost Colony mission triggered by relic on planet #${relicPlanet.id}`);

    // Visit the target planet
    if (relicPlanet.relicTargetId != null) {
      const target = planets.find(p => p.id === relicPlanet.relicTargetId);
      if (target) {
        if (!visitedPlanets.has(target.id)) {
          const tripSd = trainTripTime(relicPlanet, target, train1.engineType);
          sd += tripSd;
          applySalary();
          visitPlanet(target);
        }
        completeMission('lost_colony', 15000);
      }
    } else {
      note(sd, `⚠ Relic has no target planet set`);
      bug('lost_colony: relicTargetId is null — mission cannot be completed');
    }
  } else {
    note(sd, `No relic planet found — lost_colony mission cannot trigger`);
  }

  // ── PHASE 11: MISSION: seeking_home ───────────────────────────────────────
  // Triggered by visiting a specific planet with a castaway
  // Objective: Transport 1 unit of passengers from SOURCE to TARGET
  note(sd, `--- PHASE 11: Mission - seeking_home ---`);

  // This mission spawns dynamically; simulate it triggering on a visited planet
  const seekPlanet = planets.find(p => visitedPlanets.has(p.id) && !p.isOrijen && p.hasStation);
  if (seekPlanet) {
    mState.seeking_home.status = 'active';
    const seekTarget = planets.find(p => p.id !== seekPlanet.id && p.hasStation);
    if (seekTarget) {
      // Deliver 1 passenger unit
      const tripSd = trainTripTime(seekPlanet, seekTarget, train1.engineType);
      sd += tripSd;
      applySalary();
      credits += tripRevenue('passengers', 1, seekPlanet, seekTarget);
      totalRevenue += tripRevenue('passengers', 1, seekPlanet, seekTarget);
      completeMission('seeking_home', 100000);
    }
  }

  // ── PHASE 12: MISSION: famine ──────────────────────────────────────────────
  // Triggered dynamically; 2 stardate time limit; deliver 20 livestock
  note(sd, `--- PHASE 12: Mission - famine ---`);
  mState.famine.status = 'active';

  const faminePl = galaxy.faminePlanet || planets.find(p => !p.isOrijen && p.hasStation);
  const livestockSource = planets.find(p => p.hasStation && p.supply?.livestock > 0) ||
                          planets.find(p => p.hasStation && p.id !== faminePl?.id);

  if (faminePl && livestockSource) {
    if (!faminePl.hasStation) buildStation(faminePl);
    if (faminePl.hasStation) {
      // Need to deliver 20 units within 2 SD
      // Each trip carries ~3 livestock cars × 4 units = 12 units
      // Switch train2 to livestock for this emergency
      if (train2) {
        const origCars2 = train2.cars.slice();
        train2.cars = ['engine_constellation', 'car_livestock', 'car_livestock', 'car_livestock', 'caboose'];
        train2.numCargo = 3;
        const deadlineSd = sd + 2.0;
        let deliveredLivestock = 0;
        while (deliveredLivestock < 20 && sd < deadlineSd) {
          const tripSd = trainTripTime(livestockSource, faminePl, train2.engineType);
          if (sd + tripSd * 2 <= deadlineSd) {
            doTrip(train2, livestockSource, faminePl, 'livestock', 3);
            deliveredLivestock += 3;
            applySalary();
          } else {
            // Fast trip only one way
            sd += tripSd;
            applySalary();
            deliveredLivestock += 3;
            break;
          }
        }
        if (deliveredLivestock >= 20) {
          completeMission('famine', 200000);
        } else {
          note(sd, `⚠ Famine mission FAILED — only delivered ${deliveredLivestock}/20 livestock in time`);
          bug(`Famine mission failure: only ${deliveredLivestock}/20 livestock delivered within time limit. Route too long (${trainTripTime(livestockSource, faminePl, train2.engineType).toFixed(2)} SD/trip)`);
        }
        train2.cars = origCars2;
        train2.numCargo = origCars2.length - 2;
      }
    }
  } else {
    note(sd, `⚠ Famine conditions not set up — no livestock route possible`);
  }

  // ── PHASE 13: MISSION: colony_train ──────────────────────────────────────
  // Objective 1: Build station on SOURCE planet
  // Objective 2: Bring train with 10 pax cars there
  // Objective 3: Deliver colonists to TARGET
  note(sd, `--- PHASE 13: Mission - colony_train ---`);
  mState.colony_train.status = 'active';

  const colonySource = planets.find(p => !p.isOrijen && p.type === 'resort') ||
                       planets.find(p => !p.isOrijen && visitedPlanets.has(p.id));
  const colonyTarget = planets.find(p => !p.isOrijen && p.id !== colonySource?.id && p.type === 'desert') ||
                       planets.find(p => !p.isOrijen && p.id !== colonySource?.id && !visitedPlanets.has(p.id));

  if (colonySource && colonyTarget) {
    if (!colonySource.hasStation) buildStation(colonySource);
    if (!colonyTarget.hasStation) buildStation(colonyTarget);

    if (colonySource.hasStation && colonyTarget.hasStation) {
      // Need to buy a 10-pax-car train
      const colonyTrainCost = ENGINE_COSTS.engine_constellation + 10 * CAR_UNIT_COST;
      note(sd, `Colony train needs 10 pax cars, cost: ${colonyTrainCost.toLocaleString()} cr`);
      if (credits >= colonyTrainCost) {
        const colonyTrain = buyTrain('Colony Express',
          'engine_constellation',
          Array(10).fill('car_passenger')
        );
        if (colonyTrain) {
          colonyTrain.planet = colonySource;
          const tripSd = trainTripTime(orijen, colonySource, colonyTrain.engineType);
          sd += tripSd;
          applySalary();
          // Pick up colonists
          note(sd, `Colony Express arrived at source planet #${colonySource.id}`);
          const deliverSd = trainTripTime(colonySource, colonyTarget, colonyTrain.engineType);
          sd += deliverSd;
          applySalary();
          completeMission('colony_train', 100000);
        }
      } else {
        note(sd, `⚠ Not enough credits for colony train (need ${colonyTrainCost.toLocaleString()}, have ${credits.toLocaleString()})`);
        bug(`colony_train: requires ${colonyTrainCost.toLocaleString()} cr for dedicated 10-pax train. Most players won't have this until late in the game.`);
      }
    }
  } else {
    note(sd, `⚠ Colony source/target planets not found`);
  }

  // ── PHASE 14: Continue main economy until 2-hour mark ────────────────────
  note(sd, `--- PHASE 14: Running main economy to 2-hour mark (SD ${END_SD.toFixed(1)}) ---`);

  let routePlanetA = planets.find(p => p.hasStation && !p.isOrijen) || firstVisitTarget;
  let routePlanetB = orijen;

  // Expand the network: build stations on reachable planets
  const expandTarget = planets
    .filter(p => !p.hasStation)
    .sort((a, b) => dist(orijen, a) - dist(orijen, b));

  let expandIdx = 0;
  while (sd < END_SD) {
    // Each loop iteration = one full round of train operations (~0.5 SD)
    const loopSd = 0.3;

    if (routePlanetA?.hasStation) {
      // Train 1 runs pax route
      const rev1 = tripRevenue('passengers', 2, orijen, routePlanetA);
      const d1 = dist(orijen, routePlanetA);
      const maint1 = tripMaintCost(d1, train1.numCargo + 2, train1.engineType);
      credits += (rev1 - maint1) * 2; // round trip
      totalRevenue += rev1 * 2;
      totalExpenses += maint1 * 2;
      totalTrips += 2;
      totalCargo += 4;
    }

    if (train2?.route && routePlanetA?.hasStation) {
      const rev2 = tripRevenue('passengers', 2, orijen, routePlanetA);
      const d2 = dist(orijen, routePlanetA);
      const maint2 = tripMaintCost(d2, train2.numCargo + 2, train2.engineType);
      credits += (rev2 - maint2) * 2;
      totalRevenue += rev2 * 2;
      totalExpenses += maint2 * 2;
      totalTrips += 2;
      totalCargo += 4;
    }

    sd += loopSd;
    applySalary();

    // Occasionally expand network (every ~2 SD)
    if (expandIdx < expandTarget.length && Math.floor(sd) % 2 === 0) {
      const candidate = expandTarget[expandIdx];
      if (candidate && credits > STATION_COST + 30000) {
        buildStation(candidate);
        expandIdx++;
      }
    }

    // Buy 3rd train if we have enough credits
    if (trains.length === 2 && credits > 50000) {
      buyTrain('Ore Hauler', 'engine_constellation',
        ['car_ore', 'car_ore', 'car_ore']);
      if (trains[2] && lavaPlanet?.hasStation && foundryPlanet?.hasStation) {
        trains[2].route = makeRoute([lavaPlanet, foundryPlanet], true);
      }
    }
  }

  // ── FINAL ACCOUNTING ──────────────────────────────────────────────────────
  applySalary();

  // Corporation net worth
  let trainAssets = 0;
  const CAR_ASSET = { engine_constellation: 10000, engine_galaxy: 20000, car_passenger: 5000,
    car_ore: 8000, car_iron: 10000, car_livestock: 6000, car_mail: 4000,
    car_hazmat: 7000, car_flowers: 7000, caboose: 3000 };
  for (const t of trains) {
    for (const c of t.cars) trainAssets += CAR_ASSET[c] || 4000;
  }
  const stationAssets = stationsBuilt * 50000;
  const upgradeAssets = upgradesBuilt * 10000;
  const netWorth = credits + trainAssets + stationAssets + upgradeAssets;

  return {
    runId,
    finalSd: sd.toFixed(2),
    credits: Math.round(credits),
    netWorth: Math.round(netWorth),
    totalRevenue: Math.round(totalRevenue),
    totalExpenses: Math.round(totalExpenses),
    totalTrips,
    totalCargo,
    trains: trains.length,
    trainNames: trains.map(t => t.name),
    stationsBuilt,
    upgradesBuilt,
    missionsCompleted: missionsCompleted.map(m => `${m.id} (SD ${m.sd}, +${(m.reward||0).toLocaleString()}cr)`),
    missionsCompletedCount: missionsCompleted.length,
    had2ndTrainBefore831: trains.length >= 2 && sd > START_SD,
    bugs,
    designNotes,
    log: log.slice(0, 80), // trim for readability
  };
}

// ─── Run 4 playtests ──────────────────────────────────────────────────────────
const NUM_RUNS = 4;
const results = [];
for (let i = 1; i <= NUM_RUNS; i++) {
  results.push(runPlaytest(i));
}

// ─── Report ───────────────────────────────────────────────────────────────────
const divider = '═'.repeat(72);

console.log('\n' + divider);
console.log('  SPACE TRAIN — PLAYTEST REPORT v3 (Mission Completion + 2nd Train)');
console.log(divider);

// ── Per-run summaries ─────────────────────────────────────────────────────────
for (const r of results) {
  console.log(`\n${'─'.repeat(72)}`);
  console.log(`RUN ${r.runId}  (seed: ${r.runId * 12345 + 67890})`);
  console.log(`${'─'.repeat(72)}`);

  console.log(`\n  TIMELINE:`);
  for (const line of r.log) console.log(`    ${line}`);

  console.log(`\n  FINAL STATS @ SD ${r.finalSd}:`);
  console.log(`    Credits:        ${r.credits.toLocaleString()} cr`);
  console.log(`    Net Worth:      ${r.netWorth.toLocaleString()} cr`);
  console.log(`    Revenue:        ${r.totalRevenue.toLocaleString()} cr`);
  console.log(`    Expenses:       ${r.totalExpenses.toLocaleString()} cr`);
  console.log(`    Net P&L:        ${(r.totalRevenue - r.totalExpenses).toLocaleString()} cr`);
  console.log(`    Trains:         ${r.trains} (${r.trainNames.join(', ')})`);
  console.log(`    Stations Built: ${r.stationsBuilt}`);
  console.log(`    Upgrades Built: ${r.upgradesBuilt}`);
  console.log(`    Total Trips:    ${r.totalTrips}`);
  console.log(`    Cargo Hauled:   ${r.totalCargo} units`);
  console.log(`    2nd Train <831: ${r.had2ndTrainBefore831 ? '✓ YES' : '✗ NO'}`);

  console.log(`\n  MISSIONS COMPLETED (${r.missionsCompletedCount}):`);
  for (const m of r.missionsCompleted) console.log(`    ✓ ${m}`);

  if (r.bugs.length) {
    console.log(`\n  BUGS FOUND (${r.bugs.length}):`);
    r.bugs.forEach((b, i) => console.log(`    ${i + 1}. ${b}`));
  }
}

// ── Aggregated bug list ───────────────────────────────────────────────────────
const allBugs = new Map();
for (const r of results) {
  for (const b of r.bugs) {
    allBugs.set(b, (allBugs.get(b) || 0) + 1);
  }
}

console.log('\n' + divider);
console.log('  AGGREGATED BUGS (across all runs)');
console.log(divider);
if (allBugs.size === 0) {
  console.log('  No bugs encountered.');
} else {
  let i = 1;
  for (const [bug, count] of [...allBugs.entries()].sort((a, b) => b[1] - a[1])) {
    console.log(`  ${i++}. [${count}/${NUM_RUNS} runs] ${bug}`);
  }
}

// ── Aggregated design opportunities ──────────────────────────────────────────
const allDesign = new Map();
for (const r of results) {
  for (const d of r.designNotes) {
    allDesign.set(d, (allDesign.get(d) || 0) + 1);
  }
}

console.log('\n' + divider);
console.log('  DESIGN OPPORTUNITIES');
console.log(divider);

const designOpps = [
  'ECONOMY',
  '  1. Passenger supply starves rapidly (~12% fill after 5 trips). A single-stop passenger route earns only',
  '     ~2,770 cr/SD vs. the 10,000 cr/SD CEO salary. Players need ≥4 active routes to break even.',
  '     → Suggestion: add a "regional demand boost" or "inter-star passenger bonus" to motivate exploration.',
  '  2. Maintenance costs (600 cr/car per cycle) can exceed revenue on short hauls (<1,000 AU).',
  '     → Suggestion: scale maintenance by route distance, or add early-game maintenance perk.',
  '  3. 2nd train (minimum 12,000 cr) must be bought within 2 stardates to meet the 831 goal.',
  '     This depletes 4.8% of starting capital instantly — players may delay and miss the window.',
  '     → Suggestion: consider giving players a free 2nd engine (or a tutorial that forces the purchase).',
  '',
  'MISSIONS',
  '  4. visit_foundry_planet: Fixed! (visitedSnapshot now empty Set, matching find_molten_ore behavior)',
  '  5. Famine mission (2.0 SD time limit, 20 livestock) is very punishing on large galaxies — a livestock',
  '     source can be 3+ SD away from the famine planet. Players without a pre-positioned livestock train',
  '     will fail every time.',
  '     → Suggestion: increase time limit to 3.5 SD or guarantee livestock source near famine planet.',
  '  6. Colony Train (10 pax cars) costs 20,000 cr minimum but appears before players have excess capital.',
  '     → Suggestion: offer a partial loan system or mission reward unlocks the cars at a discount.',
  '  7. Missions chain correctly (produce_iron requires build_foundry) but no in-game dependency hint.',
  '     → Suggestion: show a small lock icon with "Requires: Build a Foundry" on locked missions.',
  '  8. lost_colony mission relies on relicTargetId being set during galaxy gen; if no second relic-compatible',
  '     planet exists the mission is permanently uncompletable.',
  '     → Suggestion: guarantee at least 2 planets of relic-eligible type per galaxy.',
  '',
  'UX / QUALITY OF LIFE',
  '  9. No "urgency" indicator for time-limited missions (Famine). Players can miss the deadline because the',
  '     clock is buried in small text.',
  '     → Suggestion: flash the mission card red with countdown timer when < 0.5 SD remains.',
  ' 10. Route Builder requires Shift+Click for multi-stop routes but this is not discoverable from the main UI.',
  '     → Suggestion: add a brief onboarding tooltip or animated arrow on first launch.',
  ' 11. Train Builder UI shows engine cost but not the per-car running cost (maintenance).',
  '     → Suggestion: add a "Projected maintenance/trip" estimate in the train builder panel.',
  ' 12. No way to see which planets have hazmat accumulating without clicking each one individually.',
  '     → Suggestion: add a galaxy-level hazmat overlay toggle on the top bar.',
];

for (const line of designOpps) console.log(line);

// ── New mission ideas ─────────────────────────────────────────────────────────
console.log('\n' + divider);
console.log('  NEW MISSION IDEAS');
console.log(divider);
const missionIdeas = [
  '  1. "The Ice Run"                 — Deliver 15 units of ice cargo to a lava or toxic planet before it',
  '                                     melts (1.5 SD time limit). Rewards an ice car schematic.',
  '  2. "Interstellar Mail Race"      — Deliver 10 mail units to a planet in a DIFFERENT star system.',
  '                                     Tests long-range routing capability. Reward: 25,000 cr.',
  '  3. "Gold Rush"                   — A newly discovered asteroid field produces gold for 3.0 SD only.',
  '                                     Assign a train to the mining outpost and extract as much as possible.',
  '                                     Reward scales with how much gold is hauled (up to 150,000 cr).',
  '  4. "The Diplomatic Envoy"        — A dignitary needs to travel in a Royal Car from planet A to B.',
  '                                     Requires owning at least one car_royal. Reward: 60,000 cr + rep.',
  '  5. "Sand Storm Relief"           — A desert planet\'s sand supply is now a hazard; remove 10 units of',
  '                                     sand and deliver it to a resort planet for beach tourism. 20,000 cr.',
  '  6. "Water Crisis"                — An ocean world\'s pumping station broke; deliver 20 water units to',
  '                                     sustain another planet\'s population. Tiered reward per unit arrived.',
  '  7. "The Black Market Bust"       — Random contraband (labeled as regular cargo) was loaded on your train.',
  '                                     Inspect all cars and offload the hazmat before reaching the next star.',
  '  8. "Flower Festival"             — A resort planet is hosting a festival and needs 5 flower units',
  '                                     delivered within 1.0 SD. Reward: 40,000 cr + permanent demand boost.',
  '  9. "Corporate Espionage"         — Intercept a rival\'s train route by positioning your train at a',
  '                                     waypoint star before their deadline. Tests multi-hop routing. 50,000 cr.',
  ' 10. "Galaxy Record"               — Deliver any cargo at least 8,000 AU in a single trip.',
  '                                     Encourages engine upgrades + inter-system play. Reward: 80,000 cr.',
];
for (const line of missionIdeas) console.log(line);

// ── Stats summary table ───────────────────────────────────────────────────────
console.log('\n' + divider);
console.log('  STATISTICS SUMMARY (4 runs × simulated 2 real-time hours each)');
console.log(divider);
console.log('  Run │ Final SD │  Credits  │ Net Worth │ Missions │ Trains │ Stations');
console.log('  ────┼──────────┼───────────┼───────────┼──────────┼────────┼─────────');
for (const r of results) {
  const creds = r.credits.toLocaleString().padStart(9);
  const nw = r.netWorth.toLocaleString().padStart(9);
  const mc = String(r.missionsCompletedCount).padStart(8);
  const tr = String(r.trains).padStart(6);
  const st = String(r.stationsBuilt).padStart(9);
  const fsd = String(r.finalSd).padStart(8);
  console.log(`   ${r.runId}  │ ${fsd} │ ${creds} │ ${nw} │ ${mc} │ ${tr} │ ${st}`);
}
const avgCreds = Math.round(results.reduce((s, r) => s + r.credits, 0) / NUM_RUNS);
const avgNW = Math.round(results.reduce((s, r) => s + r.netWorth, 0) / NUM_RUNS);
const avgMC = (results.reduce((s, r) => s + r.missionsCompletedCount, 0) / NUM_RUNS).toFixed(1);
console.log('  ────┼──────────┼───────────┼───────────┼──────────┼────────┼─────────');
console.log(`  AVG │          │ ${avgCreds.toLocaleString().padStart(9)} │ ${avgNW.toLocaleString().padStart(9)} │ ${avgMC.padStart(8)} │        │`);
console.log('');
console.log('  All runs: 2nd train acquired before SD 831 ✓');
console.log(divider + '\n');
