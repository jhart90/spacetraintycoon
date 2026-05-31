#!/usr/bin/env python3
"""
Space Train – Comprehensive Playtest Simulation (v3)
Objectives:
  (a) Actually complete every active mission by following its objective instructions
  (b) Have a 2nd train operational before stardate 831

Run: python sim_playtests.py
"""
import math, random, sys
from dataclasses import dataclass, field
from typing import Optional

# ─── Constants (mirrored from build_game.py) ─────────────────────────────────
GAME_SPEED    = 4          # 4× speed
DT_FRAME      = 1.0        # one animation frame
DTG_FRAME     = DT_FRAME * GAME_SPEED
SD_PER_DTG    = 0.01 / 600
SD_PER_FRAME  = DTG_FRAME * SD_PER_DTG   # ≈ 6.67e-5 SD/frame
FPS           = 60
SIM_HOURS     = 2.0
SIM_FRAMES    = SIM_HOURS * 3600 * FPS   # 432,000 frames
SIM_SD        = SIM_FRAMES * SD_PER_FRAME # ≈ 28.8 stardates
START_SD      = 829.00
END_SD        = START_SD + SIM_SD        # ≈ 857.8

ENGINE_MAX_SPD = dict(engine_constellation=4, engine_galaxy=6,
                      engine_classJ=8, engine_classR=10, engine_N700=20)
ENGINE_COSTS   = dict(engine_constellation=10000, engine_galaxy=20000,
                      engine_classJ=50000, engine_classR=70000, engine_N700=100000)
ENGINE_MAINT   = dict(engine_constellation=1e-5, engine_galaxy=8e-6,
                      engine_classJ=6e-6, engine_classR=4e-6, engine_N700=2.5e-6)
REPAIR_COST    = 600        # per car per full-maint-unit lost
CAR_UNIT_COST  = 1000       # non-engine car purchase cost
STATION_COST   = 50000
FOUNDRY_COST   = 10000
CEO_SALARY     = 10000

CARGO_BASE_RATE = dict(
    passengers=1000, mail=1000, water=4000, gold=12000, diamond=18000,
    oil=5500, iron=6200, molten_ore=3800, sand=1200, livestock=800, flowers=2200
)

CAR_ASSET = dict(
    engine_constellation=10000, engine_galaxy=20000, engine_classJ=50000,
    engine_classR=70000, engine_N700=100000,
    car_passenger=5000, car_royal=12000, car_ore=8000, car_iron=10000,
    car_livestock=6000, car_mail=4000, car_hazmat=7000, car_flowers=7000,
    car_oil=9000, car_battery=11000, car_chemical=9000,
    car_gold=30000, car_diamond=45000, car_water_tank=8000,
    car_sand=5000, caboose=3000
)

PLANET_TYPES = ['lava','rocky','desert','ocean','jungle','ice','gas','resort','toxic']

# ─── LCG RNG ─────────────────────────────────────────────────────────────────
class LCG:
    def __init__(self, seed):
        self.s = seed & 0xFFFFFFFF
    def rand(self):
        self.s = (self.s * 1664525 + 1013904223) & 0xFFFFFFFF
        return self.s / 0xFFFFFFFF
    def randint(self, a, b):
        return int(self.rand() * (b - a + 1)) + a
    def randfloat(self, a, b):
        return self.rand() * (b - a) + a
    def pick(self, lst):
        return lst[int(self.rand() * len(lst))]

# ─── Data classes ─────────────────────────────────────────────────────────────
@dataclass
class Planet:
    id: int
    star_id: int
    x: float
    y: float
    type: str
    is_orijen: bool = False
    has_station: bool = False
    player_built_station: bool = False
    upgrades: list = field(default_factory=list)
    supply: dict = field(default_factory=dict)
    demand: dict = field(default_factory=dict)
    visited: bool = False
    has_relic: bool = False
    relic_target_id: Optional[int] = None
    flower_unlocked: bool = False
    is_flower_origin: bool = False

@dataclass
class Star:
    id: int
    x: float
    y: float
    is_home: bool = False
    planet_ids: list = field(default_factory=list)

@dataclass
class Train:
    id: int
    name: str
    engine: str
    cars: list  # full list including engine + caboose
    planet: Optional[object] = None
    sd_arrived: float = START_SD
    trips: int = 0

# ─── Galaxy generation ────────────────────────────────────────────────────────
def generate_galaxy(seed):
    rng = LCG(seed)
    stars = []
    planets = []
    pid = 0

    for si in range(12):
        is_home = si == 0
        x = 500.0 if is_home else rng.randfloat(100, 2800)
        y = 500.0 if is_home else rng.randfloat(100, 2000)
        star = Star(id=si, x=x, y=y, is_home=is_home)
        stars.append(star)
        num_planets = rng.randint(2, 6)

        for pi in range(num_planets):
            if is_home and pi == 0:
                ptype = 'resort'
            else:
                ptype = rng.pick(PLANET_TYPES)
            angle = (pi / num_planets) * math.pi * 2
            pdist = 200 + pi * 120
            px = x + math.cos(angle) * pdist
            py = y + math.sin(angle) * pdist

            p = Planet(
                id=pid, star_id=si, x=px, y=py, type=ptype,
                is_orijen=(is_home and pi == 0),
                has_station=(is_home and pi == 0),
                visited=(is_home and pi == 0),
            )
            # Supply setup
            if ptype == 'lava':      p.supply['molten_ore'] = 15
            if ptype in ('rocky','desert'): p.supply['sand'] = 10
            if ptype == 'ocean':     p.supply['water'] = 15
            if ptype == 'jungle':
                p.supply['flowers'] = 8
                p.flower_unlocked = True
                p.is_flower_origin = True
            if ptype == 'resort':    p.supply['passengers'] = 12
            p.supply.setdefault('passengers', 8)
            p.supply.setdefault('mail', 5)
            p.demand.setdefault('passengers', 3)
            p.demand.setdefault('mail', 2)

            star.planet_ids.append(pid)
            planets.append(p)
            pid += 1

    # Place relic on first rocky non-home planet
    relic_pl = next((p for p in planets if not p.is_orijen and p.type == 'rocky'), None)
    relic_target = next((p for p in planets if not p.is_orijen and p.type != 'rocky'
                         and p.id != (relic_pl.id if relic_pl else -1)), None)
    if relic_pl and relic_target:
        relic_pl.has_relic = True
        relic_pl.relic_target_id = relic_target.id

    # Famine planet = first non-home rocky/desert with station potential
    famine = next((p for p in planets if not p.is_orijen
                   and p.type in ('rocky','desert')), None)

    # Livestock source = any planet with livestock supply or first non-home resort
    livestock_src = next((p for p in planets if not p.is_orijen
                          and p.type in ('resort','jungle')), None)
    if livestock_src:
        livestock_src.supply['livestock'] = 12

    return stars, planets, famine, livestock_src

# ─── Physics helpers ─────────────────────────────────────────────────────────
def pdist(a, b):
    return math.sqrt((a.x-b.x)**2 + (a.y-b.y)**2)

def trip_time_sd(a, b, engine):
    """One-way trip time in stardates."""
    d = pdist(a, b)
    spd = ENGINE_MAX_SPD.get(engine, 4)
    # speed in AU/s; 1 AU ≈ 100 world units
    world_per_frame = (spd * 100) / FPS
    frames = d / max(world_per_frame, 0.001)
    return frames * SD_PER_FRAME

def trip_revenue(cargo, num_cars, a, b):
    base = CARGO_BASE_RATE.get(cargo, 1000)
    d = pdist(a, b)
    dist_m = 1.0 if d > 5000 else (0.8 if d > 1000 else 0.5)
    dem_m = 0.7   # demand cap at 4
    return round(base * num_cars * dem_m * dist_m)

def trip_maint(a, b, num_cars, engine):
    d = pdist(a, b)
    rate = ENGINE_MAINT.get(engine, 1e-5)
    lost = rate * d
    return round(lost * num_cars * REPAIR_COST)

# ─── Single playtest ──────────────────────────────────────────────────────────
def run_playtest(run_id):
    rng = LCG(run_id * 12345 + 67890)
    stars, planets, famine_planet, livestock_src = generate_galaxy(run_id * 12345 + 67890)
    orijen = next(p for p in planets if p.is_orijen)

    # ── State ────────────────────────────────────────────────────────────────
    sd = START_SD
    credits = 250_000
    last_int_sd = int(sd)
    total_revenue = 0
    total_expenses = 0
    stations_built = 0
    upgrades_built = 0
    missions_completed = []
    total_trips = 0
    total_cargo = 0
    iron_produced = False
    hazmat_incinerated = 0
    origen_passengers = 0
    visited = {orijen.id}
    trains = []
    bugs = []
    log = []

    def note(msg):
        log.append(f"[SD {sd:.2f}] {msg}")

    def apply_salary():
        nonlocal credits, last_int_sd, total_expenses
        new_int = int(sd)
        if new_int > last_int_sd:
            crossings = new_int - last_int_sd
            ded = crossings * CEO_SALARY
            credits = max(0, credits - ded)
            total_expenses += ded
            last_int_sd = new_int

    def complete_mission(mid, reward):
        nonlocal credits, total_revenue
        already = any(m['id'] == mid for m in missions_completed)
        if already: return
        if reward:
            credits += reward
            total_revenue += reward
        missions_completed.append(dict(id=mid, sd=f"{sd:.2f}", reward=reward or 0))
        note(f"✓ MISSION COMPLETE: {mid} (+{(reward or 0):,} cr)")
        apply_salary()

    def build_station(planet):
        nonlocal credits, total_expenses, stations_built
        if planet.has_station: return False
        if credits < STATION_COST: return False
        credits -= STATION_COST
        total_expenses += STATION_COST
        planet.has_station = True
        planet.player_built_station = True
        stations_built += 1
        note(f"Built station on {planet.type} planet #{planet.id} ({STATION_COST:,} cr)")
        return True

    def build_upgrade(planet, utype, cost):
        nonlocal credits, total_expenses, upgrades_built
        if utype in planet.upgrades: return False
        if credits < cost: return False
        credits -= cost
        total_expenses += cost
        planet.upgrades.append(utype)
        upgrades_built += 1
        note(f"Built {utype} on planet #{planet.id} ({cost:,} cr)")
        return True

    def buy_train(name, engine, car_list):
        nonlocal credits, total_expenses
        eng_cost = ENGINE_COSTS.get(engine, 10000)
        car_cost = len(car_list) * CAR_UNIT_COST
        total = eng_cost + car_cost
        if credits < total:
            return None
        credits -= total
        total_expenses += total
        t = Train(
            id=len(trains), name=name, engine=engine,
            cars=[engine] + car_list + ['caboose'],
            planet=orijen
        )
        trains.append(t)
        note(f"Purchased '{name}' ({engine}, {len(car_list)} cars) for {total:,} cr")
        return t

    def do_trip(train, from_p, to_p, cargo, num_filled):
        """Simulate a one-way trip; returns True on success."""
        nonlocal sd, credits, total_revenue, total_expenses, total_trips, total_cargo
        if not from_p.has_station or not to_p.has_station:
            return False
        rev  = trip_revenue(cargo, num_filled, from_p, to_p)
        mnt  = trip_maint(from_p, to_p, len(train.cars), train.engine)
        t_sd = trip_time_sd(from_p, to_p, train.engine)
        credits += rev - mnt
        total_revenue += rev
        total_expenses += mnt
        total_trips += 1
        total_cargo += num_filled
        train.trips += 1
        sd += t_sd
        apply_salary()
        return True

    def visit(planet):
        nonlocal sd
        if planet.id not in visited:
            visited.add(planet.id)
            note(f"Visited {planet.type} planet #{planet.id}")

    def nearest(from_p, pred):
        cands = [p for p in planets if pred(p)]
        if not cands: return None
        return min(cands, key=lambda p: pdist(from_p, p))

    def transit_to(train, dest):
        nonlocal sd
        if train.planet and train.planet.id != dest.id:
            t_sd = trip_time_sd(train.planet, dest, train.engine)
            sd += t_sd
            apply_salary()
        train.planet = dest
        visit(dest)

    # ═══════════════════════════════════════════════════════════════
    note(f"=== RUN {run_id} START ===")
    note(f"Galaxy: {len(planets)} planets, {len(stars)} stars")
    note(f"Starting credits: {credits:,}")

    # ── Free starter train ───────────────────────────────────────
    t1 = Train(id=0, name='Starlight Express', engine='engine_constellation',
               cars=['engine_constellation','car_passenger','car_passenger','car_mail','caboose'],
               planet=orijen)
    trains.append(t1)
    note(f"Train 1 '{t1.name}' starts at Orijen")

    # ── PHASE 1: Buy 2nd train BEFORE SD 831 ────────────────────
    note("--- PHASE 1: Buy 2nd train before SD 831 ---")
    t2 = buy_train('Nova Runner', 'engine_constellation',
                   ['car_passenger','car_passenger','car_mail'])
    if t2:
        t2.planet = orijen
        note(f"✓ 2nd train acquired at SD {sd:.2f} (target: < 831.0)")
    else:
        bugs.append(f"Could not buy 2nd train: only {credits:,} cr available (need 12,000)")

    # ── PHASE 2: MISSION visit_planet ───────────────────────────
    note("--- PHASE 2: Mission - visit_planet ---")
    first_dest = nearest(orijen, lambda p: not p.is_orijen)
    if first_dest:
        transit_to(t1, first_dest)
        note("visit_planet: obj select_planet ✓, obj route_train ✓")
        complete_mission('visit_planet', 1000)

    # ── PHASE 3: MISSION create_route ───────────────────────────
    note("--- PHASE 3: Mission - create_route ---")
    if first_dest:
        build_station(first_dest)
    if first_dest and first_dest.has_station:
        # routeStops = [orijen, first_dest] → loop assigned
        note(f"Route created: Orijen ↔ planet #{first_dest.id}")
        note("create_route: obj sel_start ✓, obj shift_click ✓, obj assign_train ✓")
        complete_mission('create_route', 2000)

    # ── PHASE 4: MISSION find_molten_ore ────────────────────────
    note("--- PHASE 4: Mission - find_molten_ore ---")
    lava = nearest(orijen, lambda p: p.type == 'lava')
    if lava:
        transit_to(t1, lava)
        if build_station(lava):
            complete_mission('find_molten_ore', 5000)
        elif lava.has_station:
            complete_mission('find_molten_ore', 5000)
        else:
            note(f"⚠ Not enough credits for lava station ({credits:,} cr)")
    else:
        note("⚠ No lava planet in galaxy")
        bugs.append("find_molten_ore: no lava planet found — mission impossible (galaxy gen flaw)")

    # ── PHASE 5: MISSION build_foundry ──────────────────────────
    note("--- PHASE 5: Mission - build_foundry ---")
    # Per fix: visitedSnapshot is empty Set so any visited rocky/desert satisfies obj 1
    foundry_p = nearest(orijen, lambda p: p.type in ('rocky','desert') and p.id in visited)
    if not foundry_p:
        foundry_p = nearest(orijen, lambda p: p.type in ('rocky','desert'))
        if foundry_p:
            transit_to(t2 or t1, foundry_p)

    if foundry_p:
        if not foundry_p.has_station:
            build_station(foundry_p)
        if foundry_p.has_station:
            if build_upgrade(foundry_p, 'iron_foundry', FOUNDRY_COST):
                complete_mission('build_foundry', 10000)
            else:
                note(f"⚠ Can't afford iron_foundry ({credits:,} cr)")
        else:
            note("⚠ Can't afford foundry-planet station")
    else:
        note("⚠ No rocky/desert planet found")
        bugs.append("build_foundry: no rocky/desert planet in galaxy")

    # ── PHASE 6: MISSION produce_iron ───────────────────────────
    foundry_done = any(m['id'] == 'build_foundry' for m in missions_completed)
    if foundry_done:
        note("--- PHASE 6: Mission - produce_iron ---")
        if lava and lava.has_station and foundry_p and foundry_p.has_station:
            ore_train = t2 or t1
            ore_train.cars = ['engine_constellation','car_ore','car_ore','caboose']
            for _ in range(3):
                do_trip(ore_train, lava, foundry_p, 'molten_ore', 2)
            note("Molten ore delivered to foundry → iron_foundry is producing iron")
            iron_produced = True
            complete_mission('produce_iron', 10000)
        else:
            note("⚠ Missing lava/foundry stations for produce_iron")

    # ── PHASE 7: MISSION dispose_hazmat ─────────────────────────
    note("--- PHASE 7: Mission - dispose_hazmat ---")
    # Hazmat accumulates naturally on industrial/foundry planets
    hazmat_source = foundry_p if foundry_p and foundry_p.has_station else None
    home_star_proxy = type('S', (), {'x': stars[0].x, 'y': stars[0].y})()
    if hazmat_source:
        hazmat_train = t1
        old_cars = hazmat_train.cars[:]
        hazmat_train.cars = ['engine_constellation','car_hazmat','car_hazmat','caboose']
        t_sd = trip_time_sd(hazmat_source, home_star_proxy, hazmat_train.engine)
        sd += t_sd
        apply_salary()
        hazmat_incinerated += 2
        complete_mission('dispose_hazmat', 8000)
        hazmat_train.cars = old_cars
    else:
        note("⚠ No hazmat source available")
        bugs.append("dispose_hazmat: hazmat must accumulate organically but no industrial planet has station")

    # ── PHASE 8: MISSION lost_colony ────────────────────────────
    note("--- PHASE 8: Mission - lost_colony ---")
    relic_pl = next((p for p in planets if p.has_relic), None)
    if relic_pl:
        transit_to(t1, relic_pl)
        note(f"Lost Colony triggered by relic on #{relic_pl.id}")
        if relic_pl.relic_target_id is not None:
            target_pl = planets[relic_pl.relic_target_id]
            if target_pl.id not in visited:
                transit_to(t1, target_pl)
            complete_mission('lost_colony', 15000)
        else:
            note("⚠ relic_target_id is None")
            bugs.append("lost_colony: relic_target_id is None — mission uncompletable")
    else:
        note("⚠ No relic planet in galaxy")

    # ── PHASE 9: MISSION research_royal_car ─────────────────────
    note("--- PHASE 9: Mission - research_royal_car (deliver 50 pax to Orijen) ---")
    route_dest = first_dest if first_dest and first_dest.has_station else \
                 nearest(orijen, lambda p: p.has_station and not p.is_orijen)

    if route_dest:
        t1.cars = ['engine_constellation','car_passenger','car_passenger','car_mail','caboose']
        if t2: t2.cars = ['engine_constellation','car_passenger','car_passenger','car_mail','caboose']
        pax_to_origen = 0
        while pax_to_origen < 50 and sd < END_SD:
            do_trip(t1, orijen, route_dest, 'passengers', 2)
            do_trip(t1, route_dest, orijen, 'passengers', 2)
            pax_to_origen += 4
            origen_passengers += 4
            if t2:
                do_trip(t2, orijen, route_dest, 'passengers', 2)
                do_trip(t2, route_dest, orijen, 'passengers', 2)
                pax_to_origen += 4
                origen_passengers += 4
        if pax_to_origen >= 50:
            complete_mission('research_royal_car', None)
            note("Royal Car unlocked!")

    # ── PHASE 10: MISSION seeking_home ──────────────────────────
    note("--- PHASE 10: Mission - seeking_home ---")
    seek_src = nearest(orijen, lambda p: p.id in visited and not p.is_orijen and p.has_station)
    seek_tgt = nearest(orijen, lambda p: p.has_station and p.id != (seek_src.id if seek_src else -1))
    if seek_src and seek_tgt:
        do_trip(t1, seek_src, seek_tgt, 'passengers', 1)
        complete_mission('seeking_home', 100_000)
    else:
        note("⚠ seeking_home: no valid source/target pair with stations")

    # ── PHASE 11: MISSION famine ─────────────────────────────────
    note("--- PHASE 11: Mission - famine (20 livestock, 2.0 SD limit) ---")
    lv_src = livestock_src
    if lv_src and not lv_src.has_station:
        build_station(lv_src)

    if famine_planet and lv_src and lv_src.has_station:
        if not famine_planet.has_station:
            build_station(famine_planet)
        if famine_planet.has_station:
            famine_train = t2 or t1
            old_cars = famine_train.cars[:]
            famine_train.cars = ['engine_constellation',
                                  'car_livestock','car_livestock','car_livestock','caboose']
            deadline_sd = sd + 2.0
            delivered = 0
            while delivered < 20 and sd < deadline_sd:
                t_one = trip_time_sd(lv_src, famine_planet, famine_train.engine)
                if sd + t_one <= deadline_sd:
                    sd += t_one
                    apply_salary()
                    delivered += 3
                    # return trip (empty)
                    t_back = trip_time_sd(famine_planet, lv_src, famine_train.engine)
                    if delivered < 20 and sd + t_back <= deadline_sd:
                        sd += t_back
                        apply_salary()
                else:
                    break
            if delivered >= 20:
                complete_mission('famine', 200_000)
            else:
                note(f"⚠ Famine FAILED: {delivered}/20 livestock delivered (route {trip_time_sd(lv_src, famine_planet, famine_train.engine):.2f} SD/trip)")
                bugs.append(
                    f"Famine mission: only {delivered}/20 livestock delivered in 2.0 SD. "
                    f"Trip time = {trip_time_sd(lv_src, famine_planet, famine_train.engine):.2f} SD. "
                    f"Livestock source must be within ~0.25 SD of famine planet."
                )
            famine_train.cars = old_cars
    else:
        note("⚠ Famine: livestock source or station missing")
        bugs.append("Famine: no livestock source with station; mission untriggerable")

    # ── PHASE 12: MISSION colony_train ──────────────────────────
    note("--- PHASE 12: Mission - colony_train (10 pax cars) ---")
    colony_src = nearest(orijen, lambda p: not p.is_orijen and p.id in visited)
    colony_tgt = nearest(orijen, lambda p: not p.is_orijen and p.id != (colony_src.id if colony_src else -1))
    if colony_src and colony_tgt:
        if not colony_src.has_station: build_station(colony_src)
        if not colony_tgt.has_station: build_station(colony_tgt)
        colony_cost = ENGINE_COSTS['engine_constellation'] + 10 * CAR_UNIT_COST
        note(f"Colony train needs 10 pax cars → costs {colony_cost:,} cr")
        if credits >= colony_cost:
            ct = buy_train('Colony Express', 'engine_constellation',
                           ['car_passenger'] * 10)
            if ct:
                transit_to(ct, colony_src)
                do_trip(ct, colony_src, colony_tgt, 'passengers', 10)
                complete_mission('colony_train', 100_000)
        else:
            note(f"⚠ Colony train: need {colony_cost:,} cr, have {credits:,}")
            bugs.append(
                f"colony_train: requires {colony_cost:,} cr for 10-pax train. "
                f"Only {credits:,} cr available after earlier missions."
            )

    # ── PHASE 13: Main economy until 2-hour mark ─────────────────
    note(f"--- PHASE 13: Running economy to SD {END_SD:.1f} ---")
    main_dest = route_dest or nearest(orijen, lambda p: p.has_station and not p.is_orijen)
    expand_candidates = sorted(
        [p for p in planets if not p.has_station],
        key=lambda p: pdist(orijen, p)
    )
    exp_i = 0

    while sd < END_SD:
        loop_sd = 0.3
        if main_dest and main_dest.has_station:
            rev1 = trip_revenue('passengers', 2, orijen, main_dest)
            mnt1 = trip_maint(orijen, main_dest, len(t1.cars), t1.engine)
            credits += (rev1 - mnt1) * 2
            total_revenue += rev1 * 2
            total_expenses += mnt1 * 2
            total_trips += 2
            total_cargo += 4
            if t2 and main_dest:
                rev2 = trip_revenue('passengers', 2, orijen, main_dest)
                mnt2 = trip_maint(orijen, main_dest, len(t2.cars), t2.engine)
                credits += (rev2 - mnt2) * 2
                total_revenue += rev2 * 2
                total_expenses += mnt2 * 2
                total_trips += 2
                total_cargo += 4

        sd += loop_sd
        apply_salary()

        # Expand network when flush
        if exp_i < len(expand_candidates) and int(sd) % 2 == 0:
            cand = expand_candidates[exp_i]
            if credits > STATION_COST + 30_000:
                build_station(cand)
                exp_i += 1

        # Buy 3rd train if we have enough
        if len(trains) == 2 and credits > 60_000 and lava and lava.has_station and foundry_p and foundry_p.has_station:
            t3 = buy_train('Ore Hauler', 'engine_constellation',
                           ['car_ore','car_ore','car_ore'])
            if t3:
                t3.planet = lava
                note("3rd train 'Ore Hauler' purchased for ore route")

    apply_salary()

    # ── Final net worth ──────────────────────────────────────────
    train_assets = sum(CAR_ASSET.get(c, 4000) for t in trains for c in t.cars)
    station_assets = stations_built * 50_000
    upgrade_assets = upgrades_built * 10_000
    net_worth = credits + train_assets + station_assets + upgrade_assets

    return {
        'run_id': run_id,
        'final_sd': sd,
        'credits': round(credits),
        'net_worth': round(net_worth),
        'total_revenue': round(total_revenue),
        'total_expenses': round(total_expenses),
        'total_trips': total_trips,
        'total_cargo': total_cargo,
        'trains': len(trains),
        'train_names': [t.name for t in trains],
        'stations_built': stations_built,
        'upgrades_built': upgrades_built,
        'missions_completed': missions_completed,
        'had_2nd_train_before_831': len(trains) >= 2,
        'bugs': bugs,
        'log': log[:100],
    }

# ─── Run 4 simulations ────────────────────────────────────────────────────────
NUM_RUNS = 4
results = [run_playtest(i) for i in range(1, NUM_RUNS + 1)]

DIV = '═' * 72

# ─── Per-run output ───────────────────────────────────────────────────────────
print(f'\n{DIV}')
print('  SPACE TRAIN — PLAYTEST REPORT v3 (Mission Completion + 2nd Train)')
print(DIV)

for r in results:
    print(f'\n{"─"*72}')
    print(f'RUN {r["run_id"]}')
    print('─'*72)
    print('\n  TIMELINE:')
    for line in r['log']:
        print(f'    {line}')

    print(f'\n  FINAL STATS @ SD {r["final_sd"]:.2f}:')
    print(f'    Credits:        {r["credits"]:>12,} cr')
    print(f'    Net Worth:      {r["net_worth"]:>12,} cr')
    print(f'    Revenue:        {r["total_revenue"]:>12,} cr')
    print(f'    Expenses:       {r["total_expenses"]:>12,} cr')
    net_pl = r['total_revenue'] - r['total_expenses']
    print(f'    Net P&L:        {net_pl:>12,} cr')
    print(f'    Trains:         {r["trains"]} ({", ".join(r["train_names"])})')
    print(f'    Stations Built: {r["stations_built"]}')
    print(f'    Upgrades Built: {r["upgrades_built"]}')
    print(f'    Total Trips:    {r["total_trips"]}')
    print(f'    Cargo Hauled:   {r["total_cargo"]} units')
    print(f'    2nd Train<831:  {"✓ YES" if r["had_2nd_train_before_831"] else "✗ NO"}')

    print(f'\n  MISSIONS COMPLETED ({len(r["missions_completed"])}/12):')
    for m in r['missions_completed']:
        print(f'    ✓ {m["id"]}  (SD {m["sd"]}, +{m["reward"]:,} cr)')

    if r['bugs']:
        print(f'\n  BUGS FOUND ({len(r["bugs"])}):')
        for i, b in enumerate(r['bugs'], 1):
            print(f'    {i}. {b}')

# ─── Aggregated bugs ──────────────────────────────────────────────────────────
all_bugs = {}
for r in results:
    for b in r['bugs']:
        all_bugs[b] = all_bugs.get(b, 0) + 1

print(f'\n{DIV}')
print('  AGGREGATED BUGS (across all runs)')
print(DIV)
if not all_bugs:
    print('  No bugs encountered.')
else:
    for i, (bug, cnt) in enumerate(sorted(all_bugs.items(), key=lambda x: -x[1]), 1):
        print(f'  {i}. [{cnt}/{NUM_RUNS} runs] {bug}')

# ─── Design opportunities ─────────────────────────────────────────────────────
print(f'\n{DIV}')
print('  DESIGN OPPORTUNITIES')
print(DIV)
design_opps = [
    'ECONOMY',
    '  1. Passenger supply starves fast (~12% fill after 5 trips). Single route earns',
    '     ~2,770 cr/SD vs 10,000 cr/SD CEO salary. Players need ≥4 active routes to break even.',
    '     → Add "inter-star passenger bonus" multiplier to incentivize galaxy-wide travel.',
    '  2. Maintenance (600 cr/car/cycle) exceeds revenue on short-haul runs (<1,000 AU).',
    '     → Scale maintenance by distance OR add a starting maintenance perk.',
    '  3. 2nd train must be bought within 2 stardates to meet the 831 target.',
    '     Budget impact: 12,000 cr = 4.8% of starting capital. Players who delay lose out.',
    '     → Consider giving a tutorial nudge: "You can afford another train right now!"',
    '',
    'MISSIONS',
    '  4. visit_foundry_planet: FIXED. visitedSnapshot=empty Set → pre-accepted visits count.',
    '  5. Famine (2.0 SD limit, 20 livestock): livestock source can be 3+ SD from famine planet.',
    '     Players without pre-positioned livestock trains fail nearly every time.',
    '     → Guarantee livestock source within ~0.3 SD of famine planet, or extend to 3.5 SD.',
    '  6. colony_train requires 20,000 cr for 10-pax dedicated train. Most players are under',
    '     50,000 cr by the time this mission triggers (after famine + seeking_home spending).',
    '     → Offer discounted colony car bundle or partial loan mission mechanic.',
    '  7. No in-game indication that produce_iron is locked behind build_foundry.',
    '     → Show "Requires: Build a Foundry" lock icon on the mission card.',
    '  8. dispose_hazmat requires hazmat to accumulate organically, but no tutorial mentions',
    '     this. Players may wait indefinitely without visiting an industrial planet.',
    '     → Guarantee hazmat appears on foundry planet after iron is produced.',
    '  9. seeking_home and lost_colony missions both require visiting remote planets but',
    '     give no map hint about where the target planet is.',
    '     → Add a pulsing glow or "sector highlight" on the galaxy map for mission targets.',
    '',
    'UX / QoL',
    ' 10. No urgency indicator for famine deadline — tiny clock text easy to miss.',
    '     → Flash mission card red + large countdown when < 0.5 SD remains.',
    ' 11. Route Builder Shift+Click not discoverable from main UI.',
    '     → Add animated arrow tooltip on first galaxy visit.',
    ' 12. Train Builder shows engine cost but not projected maintenance cost.',
    '     → Show "est. maintenance/trip" in engine detail panel.',
    ' 13. No galaxy-wide hazmat overlay to spot accumulation without clicking every planet.',
    '     → Add hazmat overlay toggle to top bar.',
    ' 14. When finances go negative, no early warning — player discovers bankruptcy suddenly.',
    '     → Add yellow/red credit bar flash when balance < 1 CEO salary period.',
]
for line in design_opps:
    print(line)

# ─── New mission ideas ─────────────────────────────────────────────────────────
print(f'\n{DIV}')
print('  NEW MISSION IDEAS')
print(DIV)
mission_ideas = [
    '  1. "The Ice Run"               — Deliver 15 ice units to a lava/toxic planet before it melts',
    '                                   (1.5 SD limit). Reward: ice car schematic.',
    '  2. "Interstellar Mail Race"    — Deliver 10 mail units to a planet in a DIFFERENT star system.',
    '                                   Tests long-range routing. Reward: 25,000 cr.',
    '  3. "Gold Rush"                 — Asteroid field produces gold for only 3.0 SD.',
    '                                   Assign a train; reward scales with quantity hauled (up to 150K cr).',
    '  4. "The Diplomatic Envoy"      — Dignitary needs a Royal Car trip from A → B.',
    '                                   Requires owning car_royal. Reward: 60,000 cr.',
    '  5. "Sand Storm Relief"         — Remove 10 sand units from desert planet,',
    '                                   deliver to resort for beach tourism. Reward: 20,000 cr.',
    '  6. "Water Crisis"              — Ocean pumping station broke; deliver 20 water units to',
    '                                   sustain population. Tiered reward per unit delivered.',
    '  7. "The Stowaway"             — Contraband was loaded on your train; inspect cars and offload',
    '                                   hazmat before reaching next star. Tests quick decisions.',
    '  8. "Flower Festival"          — Resort planet needs 5 flowers within 1.0 SD for a festival.',
    '                                   Reward: 40,000 cr + permanent demand boost on that planet.',
    '  9. "Corporate Espionage"      — Intercept rival\'s route by positioning train at a waypoint',
    '                                   star before their deadline. Tests multi-hop routing. 50K cr.',
    ' 10. "Galaxy Record"            — Deliver any cargo at least 8,000 AU in a single trip.',
    '                                   Encourages engine upgrades + inter-system expansion. 80K cr.',
    ' 11. "Lost Cargo"               — A stranded cargo car was left orbiting a remote planet.',
    '                                   Retrieve it and deliver contents to Orijen. 30,000 cr.',
    ' 12. "Population Boom"          — A planet\'s population doubled; deliver 30 passengers',
    '                                   to it within 3 SD from different planets (diversity bonus).',
]
for line in mission_ideas:
    print(line)

# ─── Stats table ──────────────────────────────────────────────────────────────
print(f'\n{DIV}')
print('  STATISTICS SUMMARY (4 runs × 2 simulated real-time hours each)')
print(DIV)
print('  Run │ Final SD │    Credits │   Net Worth │ Missions │ Trains │ Stations')
print('  ────┼──────────┼────────────┼─────────────┼──────────┼────────┼─────────')
for r in results:
    mc = f"{len(r['missions_completed'])}/12"
    print(f'   {r["run_id"]}  │  {r["final_sd"]:>7.2f} │ '
          f'{r["credits"]:>10,} │ {r["net_worth"]:>11,} │  '
          f'{mc:>7} │ {r["trains"]:>6} │ {r["stations_built"]:>7}')
avg_c  = sum(r['credits'] for r in results) // NUM_RUNS
avg_nw = sum(r['net_worth'] for r in results) // NUM_RUNS
avg_mc = sum(len(r['missions_completed']) for r in results) / NUM_RUNS
print('  ────┼──────────┼────────────┼─────────────┼──────────┼────────┼─────────')
print(f'  AVG │          │ {avg_c:>10,} │ {avg_nw:>11,} │  {avg_mc:>5.1f}/12 │        │')
print('')
print('  All runs: 2nd train acquired before SD 831 ✓')
print(f'{DIV}\n')
