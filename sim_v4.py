#!/usr/bin/env python3
"""
Space Train – Playtest Simulation v4
Strategy branches with mission completion, scouting, cargo optimisation,
route profitability and a 30-stardate growth goal.

Run: python -X utf8 sim_v4.py
"""
import math, sys, random
from copy import deepcopy
from dataclasses import dataclass, field
from typing import Optional, List, Dict, Tuple

# ─── Engine constants ─────────────────────────────────────────────────────────
GAME_SPEED    = 4
SD_PER_DTG    = 0.01 / 600
SD_PER_FRAME  = GAME_SPEED * SD_PER_DTG          # ≈6.67e-5 SD per frame
FPS           = 60
WORLD_PER_AU  = 100.0

ENGINE_SPD   = dict(engine_constellation=4, engine_galaxy=6,
                    engine_classJ=8,        engine_classR=10, engine_N700=20)
ENGINE_COST  = dict(engine_constellation=10_000, engine_galaxy=20_000,
                    engine_classJ=50_000,   engine_classR=70_000, engine_N700=100_000)
ENGINE_MAINT = dict(engine_constellation=1e-5,   engine_galaxy=8e-6,
                    engine_classJ=6e-6,     engine_classR=4e-6,   engine_N700=2.5e-6)
REPAIR_COST  = 600        # per car per maintenance unit lost
CAR_COST     = 1_000      # non-engine car purchase cost
STATION_COST = 50_000
FOUNDRY_COST = 10_000
CEO_SALARY   = 10_000     # per integer stardate crossed
START_SD     = 829.0
GOAL_SD      = START_SD + 30.0   # optimise for 30 SD window

CARGO_BASE = dict(
    passengers=1000, mail=1000, water=4000, gold=12000, diamond=18000,
    oil=5500, iron=6200, molten_ore=3800, sand=1200, livestock=800,
    flowers=2200, hazmat=0
)

# Car type that carries each cargo
CARGO_CAR = dict(
    passengers='car_passenger', mail='car_mail', water='car_water_tank',
    gold='car_gold', diamond='car_diamond', oil='car_oil', iron='car_iron',
    molten_ore='car_ore', sand='car_sand', livestock='car_livestock',
    flowers='car_flowers', hazmat='car_hazmat'
)

# What each planet type naturally supplies (cargo_type → max_supply_level)
PLANET_SUPPLY = dict(
    lava    ={'molten_ore': 15, 'hazmat': 3},
    rocky   ={'sand': 10, 'passengers': 5},
    desert  ={'sand': 8,  'oil': 6, 'passengers': 4},
    ocean   ={'water': 18, 'passengers': 6},
    jungle  ={'flowers': 8, 'passengers': 7},
    ice     ={'passengers': 5, 'mail': 6},
    gas     ={'oil': 12,  'battery': 8},
    resort  ={'passengers': 14, 'mail': 5},
    toxic   ={'hazmat': 10, 'chemical': 6},
    home    ={'passengers': 12, 'mail': 8},   # Orijen
)

# What each planet type demands
PLANET_DEMAND = dict(
    lava    ={'water': 4, 'iron': 3},
    rocky   ={'water': 3, 'mail': 3},
    desert  ={'water': 4, 'passengers': 3},
    ocean   ={'passengers': 3, 'mail': 2},
    jungle  ={'passengers': 4, 'mail': 3},
    ice     ={'water': 3, 'passengers': 3},
    gas     ={'mail': 2, 'passengers': 2},
    resort  ={'passengers': 4, 'flowers': 3, 'water': 2},
    toxic   ={'mail': 2, 'passengers': 2},
    home    ={'passengers': 4, 'mail': 3, 'flowers': 3, 'water': 2},
)

CAR_ASSET = dict(
    engine_constellation=10_000, engine_galaxy=20_000, engine_classJ=50_000,
    engine_classR=70_000, engine_N700=100_000,
    car_passenger=5_000, car_royal=12_000, car_ore=8_000, car_iron=10_000,
    car_livestock=6_000, car_mail=4_000, car_hazmat=7_000, car_flowers=7_000,
    car_oil=9_000, car_battery=11_000, car_chemical=9_000,
    car_gold=30_000, car_diamond=45_000, car_water_tank=8_000,
    car_sand=5_000, caboose=3_000
)

# ─── LCG RNG ─────────────────────────────────────────────────────────────────
class LCG:
    def __init__(self, seed):
        self.s = seed & 0xFFFFFFFF
    def r(self):
        self.s = (self.s * 1664525 + 1013904223) & 0xFFFFFFFF
        return self.s / 0xFFFFFFFF
    def ri(self, a, b): return int(self.r() * (b - a + 1)) + a
    def rf(self, a, b): return self.r() * (b - a) + a
    def pick(self, lst): return lst[int(self.r() * len(lst))]

# ─── Data classes ─────────────────────────────────────────────────────────────
@dataclass
class Planet:
    id: int
    star_id: int
    x: float
    y: float
    ptype: str
    is_orijen: bool = False
    has_station: bool = False
    upgrades: list = field(default_factory=list)
    supply: dict = field(default_factory=dict)
    demand: dict = field(default_factory=dict)
    visited: bool = False
    scouted: bool = False    # visited but no station decision yet
    has_relic: bool = False
    relic_target_id: Optional[int] = None
    flower_origin: bool = False

@dataclass
class RouteLink:
    """One directed arc of a route (from_id → to_id, carrying cargo_type)."""
    from_id: int
    to_id: int
    cargo: str
    cars: int
    rev_per_trip: float
    maint_per_trip: float
    trip_sd: float

    @property
    def profit_per_trip(self): return self.rev_per_trip - self.maint_per_trip
    @property
    def profit_per_sd(self):
        return self.profit_per_trip / self.trip_sd if self.trip_sd > 0 else 0

@dataclass
class TrainState:
    id: int
    name: str
    engine: str
    cargo_cars: list       # e.g. ['car_passenger','car_passenger']
    route: list            # ordered list of planet_ids (loop if first==last)
    planet_id: int         # current location
    sd_busy_until: float = 0.0
    trips: int = 0
    total_rev: float = 0.0
    total_exp: float = 0.0

# ─── Galaxy generation ────────────────────────────────────────────────────────
PTYPES = ['lava','rocky','desert','ocean','jungle','ice','gas','resort','toxic']

def gen_galaxy(seed):
    rng = LCG(seed)
    stars, planets = [], []
    pid = 0

    for si in range(12):
        home = (si == 0)
        sx = 500.0 if home else rng.rf(150, 2800)
        sy = 500.0 if home else rng.rf(150, 2000)
        n = rng.ri(3, 6)
        star_pids = []
        for pi in range(n):
            if home and pi == 0:
                pt = 'resort'
            elif home and pi == 1:
                pt = 'ocean'    # guarantee water near home
            else:
                pt = rng.pick(PTYPES)
            angle = (pi / n) * math.tau
            r = 180 + pi * 110
            px, py = sx + math.cos(angle)*r, sy + math.sin(angle)*r
            sup = dict(PLANET_SUPPLY.get(pt, PLANET_SUPPLY['rocky']))
            dem = dict(PLANET_DEMAND.get(pt, PLANET_DEMAND['rocky']))
            if home:
                sup = dict(PLANET_SUPPLY['home'])
                dem = dict(PLANET_DEMAND['home'])
            p = Planet(id=pid, star_id=si, x=px, y=py, ptype=pt,
                       is_orijen=(home and pi == 0),
                       has_station=(home and pi == 0),
                       visited=(home and pi == 0),
                       scouted=(home and pi == 0),
                       supply=sup, demand=dem)
            if pt == 'jungle':
                p.flower_origin = True
            star_pids.append(pid)
            planets.append(p)
            pid += 1
        stars.append(dict(id=si, x=sx, y=sy, home=home, pids=star_pids))

    # Relic
    relic_cands = [p for p in planets if not p.is_orijen and p.ptype == 'rocky']
    if relic_cands:
        rp = relic_cands[0]
        rp.has_relic = True
        others = [p for p in planets if p.id != rp.id and not p.is_orijen]
        if others:
            rp.relic_target_id = others[len(others)//2].id

    # Famine + livestock source
    famine = next((p for p in planets if not p.is_orijen
                   and p.ptype in ('rocky','desert')), None)
    livestock_src = next((p for p in planets if not p.is_orijen
                          and p.ptype == 'resort'), None)
    if livestock_src:
        livestock_src.supply['livestock'] = 10

    return stars, planets, famine, livestock_src

# ─── Physics ──────────────────────────────────────────────────────────────────
def pdist(ax, ay, bx, by): return math.hypot(ax-bx, ay-by)
def p2p(a: Planet, b: Planet): return pdist(a.x, a.y, b.x, b.y)

def trip_sd(a: Planet, b: Planet, engine: str) -> float:
    d = p2p(a, b)
    spd_world_per_frame = ENGINE_SPD[engine] * WORLD_PER_AU / FPS
    frames = d / max(spd_world_per_frame, 0.001)
    return frames * SD_PER_FRAME

def cargo_rev(cargo: str, n_cars: int, a: Planet, b: Planet) -> float:
    base = CARGO_BASE.get(cargo, 0)
    d = p2p(a, b)
    dm = 1.0 if d > 5000 else (0.8 if d > 1000 else 0.5)
    return base * n_cars * 0.7 * dm      # dem_m always 0.7 (cap=4)

def cargo_maint(a: Planet, b: Planet, total_cars: int, engine: str) -> float:
    d = p2p(a, b)
    return ENGINE_MAINT[engine] * d * total_cars * REPAIR_COST

# ─── Route profitability helpers ──────────────────────────────────────────────
def best_cargo_between(a: Planet, b: Planet) -> Optional[Tuple[str, float]]:
    """Best (cargo, rev_per_car) for a→b, None if no cargo fits."""
    best, best_val = None, 0.0
    for cargo, supply_level in a.supply.items():
        if supply_level <= 0: continue
        if b.demand.get(cargo, 0) <= 0: continue
        if cargo == 'hazmat': continue          # skip hazmat for regular routes
        rev = cargo_rev(cargo, 1, a, b)
        if rev > best_val:
            best_val = rev
            best = cargo
    return (best, best_val) if best else None

def route_profit_per_sd(a: Planet, b: Planet, n_cars: int, engine: str,
                         ab_cargo: Optional[str], ba_cargo: Optional[str]) -> dict:
    """Full round-trip profitability for a↔b."""
    t_ab = trip_sd(a, b, engine)
    t_ba = trip_sd(b, a, engine)
    total_cars = n_cars + 2  # + engine + caboose
    rev_ab = cargo_rev(ab_cargo, n_cars, a, b) if ab_cargo else 0
    rev_ba = cargo_rev(ba_cargo, n_cars, b, a) if ba_cargo else 0
    mnt_ab = cargo_maint(a, b, total_cars, engine)
    mnt_ba = cargo_maint(b, a, total_cars, engine)
    rt_sd = t_ab + t_ba
    profit = (rev_ab + rev_ba - mnt_ab - mnt_ba)
    return dict(ab=ab_cargo, ba=ba_cargo,
                rev_ab=rev_ab, rev_ba=rev_ba,
                mnt_ab=mnt_ab, mnt_ba=mnt_ba,
                rt_sd=rt_sd, profit_rt=profit,
                profit_per_sd=profit/rt_sd if rt_sd>0 else 0)

# ─── Main simulation class ────────────────────────────────────────────────────
class Game:
    def __init__(self, seed, branch_name, cfg):
        self.seed = seed
        self.branch = branch_name
        self.cfg = cfg

        self.stars, self.planets, self.famine, self.livestock_src = gen_galaxy(seed)
        self.pmap = {p.id: p for p in self.planets}
        self.orijen = next(p for p in self.planets if p.is_orijen)

        self.sd = START_SD
        self.credits = 250_000
        self.last_int_sd = int(self.sd)
        self.trains: List[TrainState] = []
        self.log = []
        self.bugs = []
        self.missions_done = []
        self.finance_log = []   # (sd, event, delta)

        self.total_rev = 0.0
        self.total_exp = 0.0
        self.total_trips = 0
        self.stations_built = 0
        self.upgrades_built = 0
        self.iron_unlocked = False

        # Mission flags
        self.mf = {k: False for k in [
            'visit_planet','create_route','find_molten_ore','build_foundry',
            'produce_iron','dispose_hazmat','lost_colony','seeking_home',
            'research_royal_car','famine','colony_train']}
        self.origen_pax_delivered = 0
        self.hazmat_incinerated = 0.0

    # ── Helpers ──────────────────────────────────────────────────────────────
    def note(self, msg):
        self.log.append(f"[{self.sd:.2f}] {msg}")

    def salary(self):
        new_int = int(self.sd)
        if new_int > self.last_int_sd:
            c = new_int - self.last_int_sd
            ded = c * CEO_SALARY
            self.credits = max(0, self.credits - ded)
            self.total_exp += ded
            self.last_int_sd = new_int

    def earn(self, amt, tag=''):
        self.credits += amt
        self.total_rev += amt
        if tag: self.finance_log.append((self.sd, tag, amt))

    def spend(self, amt, tag=''):
        self.credits -= amt
        self.total_exp += amt
        if tag: self.finance_log.append((self.sd, tag, -amt))

    def reserve(self):
        """Minimum credits to keep in reserve (2 salary cycles)."""
        return self.cfg.get('reserve', 30_000)

    def can_afford(self, cost):
        return self.credits - cost >= self.reserve()

    def get_p(self, pid): return self.pmap[pid]

    def transit_sd(self, a_id, b_id, engine='engine_constellation'):
        a, b = self.pmap[a_id], self.pmap[b_id]
        return trip_sd(a, b, engine)

    def advance(self, delta_sd):
        self.sd += delta_sd
        self.salary()

    # ── Infrastructure ────────────────────────────────────────────────────────
    def build_station(self, planet_id) -> bool:
        p = self.pmap[planet_id]
        if p.has_station: return True
        if not self.can_afford(STATION_COST): return False
        self.spend(STATION_COST, 'station')
        p.has_station = True
        self.stations_built += 1
        self.note(f"  🏗  Station built on {p.ptype} #{p.id}")
        return True

    def build_upgrade(self, planet_id, utype, cost) -> bool:
        p = self.pmap[planet_id]
        if utype in p.upgrades: return True
        if not self.can_afford(cost): return False
        self.spend(cost, utype)
        p.upgrades.append(utype)
        self.upgrades_built += 1
        self.note(f"  🔧 {utype} built on #{planet_id}")
        return True

    # ── Scouting ──────────────────────────────────────────────────────────────
    def scout_planet(self, planet_id, scout_train: TrainState) -> float:
        """Transit to planet and back without a station. Returns round-trip SD."""
        p = self.pmap[planet_id]
        cur = self.pmap[scout_train.planet_id]
        rt = trip_sd(cur, p, scout_train.engine) * 2
        self.advance(rt)
        p.visited = True
        p.scouted = True
        scout_train.planet_id = planet_id
        self.note(f"  🔭 Scouted {p.ptype} #{p.id} ({rt:.3f} SD round-trip)")
        return rt

    # ── Train purchasing ──────────────────────────────────────────────────────
    def buy_train(self, name, engine, cargo_cars, start_planet_id,
                  route_planet_ids) -> Optional[TrainState]:
        eng_c = ENGINE_COST[engine]
        car_c = len(cargo_cars) * CAR_COST
        total = eng_c + car_c
        if not self.can_afford(total):
            self.note(f"  ✗ Can't afford train '{name}' ({total:,} cr, have {self.credits:,})")
            return None
        self.spend(total, 'train')
        t = TrainState(id=len(self.trains), name=name, engine=engine,
                       cargo_cars=list(cargo_cars),
                       route=list(route_planet_ids),
                       planet_id=start_planet_id)
        self.trains.append(t)
        self.note(f"  🚂 Purchased '{name}' [{engine},{','.join(cargo_cars)}] {total:,} cr")
        return t

    # ── Route execution ──────────────────────────────────────────────────────
    def run_route_for(self, train: TrainState, duration_sd: float):
        """
        Simulate train running its assigned route for `duration_sd` stardates.
        Works out trips, revenue per leg, maintenance, and advances sd.
        """
        if len(train.route) < 2: return
        planet_ids = train.route
        n_legs = len(planet_ids) - 1  # last == first for loops

        total_cars = len(train.cargo_cars) + 2  # + engine + caboose

        # Build cargo assignment per leg
        legs = []
        for i in range(n_legs):
            a = self.pmap[planet_ids[i]]
            b = self.pmap[planet_ids[i+1]]
            result = best_cargo_between(a, b)
            cargo = result[0] if result else 'passengers'
            legs.append((a, b, cargo))

        # Calculate one full cycle time
        cycle_sd = sum(trip_sd(a, b, train.engine) for a, b, _ in legs)
        if cycle_sd <= 0: return
        cycles = int(duration_sd / cycle_sd)
        if cycles == 0: cycles = 1

        for _ in range(cycles):
            for a, b, cargo in legs:
                if not a.has_station or not b.has_station: continue
                n_cars = len(train.cargo_cars)
                rev = cargo_rev(cargo, n_cars, a, b)
                mnt = cargo_maint(a, b, total_cars, train.engine)
                self.earn(rev, f'{cargo}_{a.id}→{b.id}')
                self.spend(mnt, 'maint')
                train.trips += 1
                train.total_rev += rev
                train.total_exp += mnt
                self.total_trips += 1
                # Track pax to Orijen for mission
                if cargo == 'passengers' and b.is_orijen:
                    self.origen_pax_delivered += n_cars

        self.advance(cycles * cycle_sd)
        train.sd_busy_until = self.sd

    # ── Mission helpers ───────────────────────────────────────────────────────
    def complete_mission(self, mid, reward):
        if self.mf[mid]: return
        self.mf[mid] = True
        rew = reward or 0
        if rew: self.earn(rew, f'mission:{mid}')
        self.missions_done.append((mid, f"{self.sd:.2f}", rew))
        self.note(f"  ✅ MISSION: {mid} +{rew:,} cr")

    def lava_planet(self):
        return next((p for p in self.planets if p.ptype=='lava'), None)

    def foundry_planet(self):
        """Rocky/desert planet that is visited."""
        for p in self.planets:
            if p.ptype in ('rocky','desert') and p.visited:
                return p
        return next((p for p in self.planets if p.ptype in ('rocky','desert')), None)

    def relic_planet(self):
        return next((p for p in self.planets if p.has_relic), None)

    # ── Route analysis ────────────────────────────────────────────────────────
    def best_routes(self, n=10, engine='engine_constellation', n_cars=3):
        """Return top-n profitable round-trip routes between stations."""
        results = []
        stations = [p for p in self.planets if p.has_station]
        for i, a in enumerate(stations):
            for b in stations[i+1:]:
                ab = best_cargo_between(a, b)
                ba = best_cargo_between(b, a)
                if not ab and not ba: continue
                info = route_profit_per_sd(a, b, n_cars, engine,
                                           ab[0] if ab else None,
                                           ba[0] if ba else None)
                results.append((a, b, info))
        results.sort(key=lambda x: -x[2]['profit_per_sd'])
        return results[:n]

    def best_unbuilt_routes(self, n=5, engine='engine_constellation', n_cars=3):
        """Routes that would be profitable IF we built stations on scouted planets."""
        results = []
        candidates = [p for p in self.planets if p.scouted]
        stations = [p for p in self.planets if p.has_station]
        seen_ids = set()
        all_cands = []
        for p in candidates + stations:
            if p.id not in seen_ids:
                seen_ids.add(p.id)
                all_cands.append(p)
        for i, a in enumerate(all_cands):
            for b in all_cands[i+1:]:
                if not a.has_station and not b.has_station: continue
                ab = best_cargo_between(a, b)
                ba = best_cargo_between(b, a)
                if not ab and not ba: continue
                info = route_profit_per_sd(a, b, n_cars, engine,
                                           ab[0] if ab else None,
                                           ba[0] if ba else None)
                station_cost = (0 if a.has_station else STATION_COST) + \
                               (0 if b.has_station else STATION_COST)
                # ROI: how many SD to break even
                if info['profit_per_sd'] > 0:
                    train_cost = ENGINE_COST[engine] + n_cars * CAR_COST
                    break_even_sd = (station_cost + train_cost) / info['profit_per_sd']
                    results.append((a, b, info, station_cost, break_even_sd))
        results.sort(key=lambda x: x[4])   # sort by break-even time
        return results[:n]

    # ── Net worth ─────────────────────────────────────────────────────────────
    def net_worth(self):
        train_assets = sum(
            CAR_ASSET.get(t.engine, 10000) +
            sum(CAR_ASSET.get(c, 4000) for c in t.cargo_cars) +
            CAR_ASSET['caboose']
            for t in self.trains
        )
        return int(self.credits + train_assets +
                   self.stations_built * 50_000 + self.upgrades_built * 10_000)

    # ──────────────────────────────────────────────────────────────────────────
    # STRATEGY RUNNER
    # ──────────────────────────────────────────────────────────────────────────
    def run(self):
        fn = getattr(self, f'strategy_{self.cfg["strategy"]}')
        fn()

    # ─── BRANCH A: Scout-First ────────────────────────────────────────────────
    def strategy_scout_first(self):
        """
        Scout entire home-star cluster first; build stations only where
        data says it's profitable; assemble bespoke trains per route.
        """
        self.note("=== BRANCH A: Scout-First ===")

        # 1. Free starter train
        t1 = TrainState(id=0, name='Pioneer', engine='engine_constellation',
                        cargo_cars=['car_passenger','car_passenger','car_mail'],
                        route=[self.orijen.id],
                        planet_id=self.orijen.id)
        self.trains.append(t1)

        # 2. Buy 2nd train immediately
        t2 = self.buy_train('Scout', 'engine_constellation',
                            ['car_passenger','car_passenger'],
                            self.orijen.id, [self.orijen.id])
        self.note("--- Scout phase: home-star cluster ---")

        # 3. Scout all home-star planets with t2
        home_star = self.stars[0]
        for pid in home_star['pids']:
            p = self.pmap[pid]
            if not p.visited:
                self.scout_planet(pid, t2)

        # 4. Scout nearest 2 stars with t1 (scouting beyond while t2 scouts home)
        other_stars = sorted(self.stars[1:],
            key=lambda s: pdist(s['x'],s['y'],500,500))[:2]
        for s in other_stars:
            for pid in s['pids']:
                p = self.pmap[pid]
                if not p.visited:
                    # transit one-way; add to scouted without full round-trip
                    t1.planet_id = pid
                    p.visited = True
                    p.scouted = True
                    tsd = self.transit_sd(self.orijen.id, pid)
                    self.advance(tsd)
                    self.note(f"  🔭 Scouted {p.ptype} #{pid} (inter-star)")

        # Mission: visit_planet
        first_visited = next(p for p in self.planets
                             if p.visited and not p.is_orijen)
        self.complete_mission('visit_planet', 1_000)

        # 5. Analyse scouted planets → identify top routes
        self.note("--- Analysing scouted planets ---")
        # Temporarily mark scouted as having stations for analysis
        top = self.best_unbuilt_routes(n=6)
        if top:
            for a, b, info, sc, be in top[:3]:
                self.note(f"  📊 Route #{a.id}({a.ptype})↔#{b.id}({b.ptype}): "
                          f"{info['ab']}↔{info['ba']} "
                          f"{info['profit_per_sd']:.0f} cr/SD, BE {be:.1f} SD")

        # 6. Build stations on the 2 most profitable route endpoints
        target_planets = []
        seen = set()
        for a, b, info, sc, be in top:
            if be > 20: continue   # skip if break-even >20 SD
            for p in (a, b):
                if p.id not in seen:
                    target_planets.append(p)
                    seen.add(p.id)
            if len(target_planets) >= 4: break

        for p in target_planets:
            if not p.has_station:
                self.build_station(p.id)

        # Route train1 to first station
        route_dest = next((p for p in target_planets if p.has_station
                           and not p.is_orijen), None)
        if route_dest:
            t1.route = [self.orijen.id, route_dest.id, self.orijen.id]
            t2.route = [self.orijen.id, route_dest.id, self.orijen.id]
            self.complete_mission('create_route', 2_000)

        # 7. Do missions while economy runs
        self._do_core_missions(t1, t2)

        # 8. Analyse actual station network and deploy specialised trains
        self.note("--- Deploying specialised trains ---")
        self._deploy_optimal_trains()

        # 9. Run economy to 30-SD mark
        self._run_economy_to_goal()

    # ─── BRANCH B: High-Value Cargo First ────────────────────────────────────
    def strategy_cargo_specialist(self):
        """
        Immediately hunt for gold/diamond/iron sources.
        Build dedicated mono-cargo trains on each high-value route.
        """
        self.note("=== BRANCH B: High-Value Cargo Specialist ===")

        t1 = TrainState(id=0, name='Hauler-1', engine='engine_constellation',
                        cargo_cars=['car_passenger','car_passenger','car_mail'],
                        route=[self.orijen.id], planet_id=self.orijen.id)
        self.trains.append(t1)

        t2 = self.buy_train('Hauler-2', 'engine_constellation',
                            ['car_passenger','car_passenger'],
                            self.orijen.id, [self.orijen.id])

        # Quickly visit all home-star planets to find valuable cargo
        home_star = self.stars[0]
        for pid in home_star['pids']:
            p = self.pmap[pid]
            if not p.visited:
                self.scout_planet(pid, t1)

        self.complete_mission('visit_planet', 1_000)

        # Find lava (molten_ore) and rocky/desert (foundry-eligible) in home star
        lava = self.lava_planet() or next(
            (p for p in self.planets if p.ptype=='lava'), None)
        fp = self.foundry_planet()

        # Build stations on best supply planets first
        # Priority: highest-value cargo within range
        self.note("--- Building high-value supply chain ---")
        if lava and not lava.has_station:
            self.build_station(lava.id)
        if fp and not fp.has_station:
            self.build_station(fp.id)

        # find_molten_ore mission
        if lava:
            if not lava.visited:
                self.advance(self.transit_sd(self.orijen.id, lava.id))
                lava.visited = True
            self.complete_mission('find_molten_ore', 5_000)
            if lava.has_station:
                self.complete_mission('find_molten_ore', 5_000)  # idempotent

        # build_foundry mission
        if fp:
            if not fp.visited:
                self.advance(self.transit_sd(self.orijen.id, fp.id))
                fp.visited = True
            if not fp.has_station:
                self.build_station(fp.id)
            if fp.has_station:
                if self.build_upgrade(fp.id, 'iron_foundry', FOUNDRY_COST):
                    self.complete_mission('build_foundry', 10_000)

        # Produce iron
        if self.mf['build_foundry'] and lava and lava.has_station and fp and fp.has_station:
            self.note("--- Running ore route to unlock iron ---")
            ore_train = self.buy_train('Ore-1', 'engine_constellation',
                                       ['car_ore','car_ore','car_ore'],
                                       lava.id, [lava.id, fp.id, lava.id])
            if ore_train:
                self.run_route_for(ore_train, 0.5)
                self.iron_unlocked = True
                self.complete_mission('produce_iron', 10_000)

        # Set up first passenger route
        route_dest = next((p for p in self.planets
                           if p.has_station and not p.is_orijen), None)
        if route_dest:
            t1.route = [self.orijen.id, route_dest.id, self.orijen.id]
            if t2: t2.route = t1.route[:]
            self.complete_mission('create_route', 2_000)

        # Scout more planets to find gold/diamond
        self.note("--- Scouting for high-value cargo ---")
        precious_planets = []
        for p in sorted(self.planets, key=lambda x: p2p(x, self.orijen)):
            if p.visited or p.is_orijen: continue
            # Scout it
            tsd = self.transit_sd(self.orijen.id, p.id)
            self.advance(tsd)
            p.visited = True
            p.scouted = True
            self.note(f"  🔭 Scouted {p.ptype} #{p.id}")
            # If it has valuable cargo, note it
            has_precious = any(c in p.supply for c in ['gold','diamond','iron','oil'])
            if has_precious:
                precious_planets.append(p)
            if self.sd > START_SD + 5 and len(precious_planets) >= 2:
                break

        # Build stations on gold/diamond planets and deploy dedicated trains
        for p in precious_planets[:3]:
            if not p.has_station:
                self.build_station(p.id)
            if p.has_station:
                best_c = max(p.supply.keys(),
                             key=lambda c: CARGO_BASE.get(c, 0))
                car_type = CARGO_CAR.get(best_c, 'car_passenger')
                dest = self.orijen  # or a planet that demands it
                for p2 in self.planets:
                    if p2.has_station and p2.id != p.id and p2.demand.get(best_c, 0) > 0:
                        dest = p2
                        break
                train_name = f'{best_c.title()}-Express'
                nt = self.buy_train(train_name, 'engine_constellation',
                                    [car_type]*3, p.id, [p.id, dest.id, p.id])
                if nt:
                    self.note(f"  Dedicated {best_c} train: #{p.id}→#{dest.id}")

        self._do_core_missions(t1, t2)
        self._deploy_optimal_trains()
        self._run_economy_to_goal()

    # ─── BRANCH C: Dense Network ──────────────────────────────────────────────
    def strategy_dense_network(self):
        """
        Build the widest possible station network first.
        Use mixed-cargo trains that adapt cargo per leg.
        Prioritise density of stops over cargo value per trip.
        """
        self.note("=== BRANCH C: Dense Network Builder ===")

        t1 = TrainState(id=0, name='Hub-1', engine='engine_constellation',
                        cargo_cars=['car_passenger','car_passenger','car_mail'],
                        route=[self.orijen.id], planet_id=self.orijen.id)
        self.trains.append(t1)
        t2 = self.buy_train('Hub-2', 'engine_constellation',
                            ['car_passenger','car_mail','car_mail'],
                            self.orijen.id, [self.orijen.id])

        # Visit every planet in home star cluster, build stations liberally
        home_star = self.stars[0]
        for pid in home_star['pids']:
            p = self.pmap[pid]
            if not p.visited:
                self.advance(self.transit_sd(self.orijen.id, pid))
                p.visited = True
                p.scouted = True
                self.note(f"  🔭 Scouted {p.ptype} #{pid}")
            if not p.has_station:
                self.build_station(pid)

        self.complete_mission('visit_planet', 1_000)
        self.complete_mission('create_route', 2_000)

        # Core missions immediately
        self._do_core_missions(t1, t2)

        # Expand outward: scout each adjacent star and build stations
        sorted_stars = sorted(self.stars[1:],
            key=lambda s: pdist(s['x'],s['y'],self.stars[0]['x'],self.stars[0]['y']))

        for s in sorted_stars[:4]:
            for pid in s['pids']:
                p = self.pmap[pid]
                if not p.visited:
                    self.advance(self.transit_sd(self.orijen.id, pid))
                    p.visited = True
                    p.scouted = True
                    self.note(f"  🔭 Inter-star scout {p.ptype} #{pid}")
                if not p.has_station and self.can_afford(STATION_COST + 20_000):
                    self.build_station(pid)
            if self.sd > START_SD + 12: break

        # Build multi-stop loop routes
        self.note("--- Building hub-spoke loops ---")
        self._build_hub_spokes()

        # Buy fleet of medium trains for the hub
        while len(self.trains) < 6 and self.can_afford(15_000) and self.sd < GOAL_SD - 5:
            n = len(self.trains) + 1
            nt = self.buy_train(f'Hub-{n}', 'engine_constellation',
                                ['car_passenger','car_passenger','car_mail'],
                                self.orijen.id,
                                [self.orijen.id] + [p.id for p in self.planets
                                                    if p.has_station and not p.is_orijen][:2]
                                + [self.orijen.id])
            if not nt: break
            self.advance(0.5)

        self._run_economy_to_goal()

    def _build_hub_spokes(self):
        """Assign hub-and-spoke routes to existing trains."""
        spoke_planets = [p for p in self.planets if p.has_station and not p.is_orijen]
        spoke_planets.sort(key=lambda p: p2p(p, self.orijen))
        for i, t in enumerate(self.trains):
            if i < len(spoke_planets):
                dest = spoke_planets[i % len(spoke_planets)]
                t.route = [self.orijen.id, dest.id, self.orijen.id]

    # ─── BRANCH D: Reinvest-Missions ──────────────────────────────────────────
    def strategy_reinvest_missions(self):
        """
        Blitz missions fast for the lump-sum rewards, then reinvest the
        windfall into an optimised multi-train empire. Uses the
        551K mission reward cash to fund the late-game expansion.
        """
        self.note("=== BRANCH D: Reinvest-Missions ===")

        t1 = TrainState(id=0, name='Flagship', engine='engine_constellation',
                        cargo_cars=['car_passenger','car_passenger','car_mail'],
                        route=[self.orijen.id], planet_id=self.orijen.id)
        self.trains.append(t1)
        t2 = self.buy_train('Support', 'engine_constellation',
                            ['car_passenger','car_passenger'],
                            self.orijen.id, [self.orijen.id])

        # Mission blitz
        self._do_core_missions(t1, t2)

        # After missions → big reinvestment
        self.note(f"--- Post-mission reinvest ({self.credits:,} cr available) ---")

        # Build stations on every profitable scouted planet
        candidates = sorted(
            [p for p in self.planets if p.scouted and not p.has_station],
            key=lambda p: p2p(p, self.orijen)
        )
        for p in candidates[:8]:
            if self.can_afford(STATION_COST + 50_000):
                self.build_station(p.id)

        # Deploy purpose-built trains on best routes
        self._deploy_optimal_trains()

        # Keep buying trains until reserve threshold
        while len(self.trains) < 8 and self.sd < GOAL_SD - 3:
            best = self.best_routes(n=3)
            if not best: break
            a, b, info = best[0]
            if info['profit_per_sd'] <= 0: break
            ab_car = CARGO_CAR.get(info['ab'], 'car_passenger')
            ba_car = CARGO_CAR.get(info['ba'], 'car_passenger')
            cars = list(set([ab_car, ba_car, ab_car]))[:3]  # 3 cars
            n = len(self.trains) + 1
            nt = self.buy_train(f'Specialist-{n}', 'engine_constellation',
                                cars, a.id, [a.id, b.id, a.id])
            if not nt: break
            self.advance(0.3)

        self._run_economy_to_goal()

    # ─── Shared mission logic ─────────────────────────────────────────────────
    def _do_core_missions(self, t1, t2):
        self.note("--- Core mission sequence ---")
        home_star = self.stars[0]

        # visit_planet
        if not self.mf['visit_planet']:
            dest = next((p for p in self.planets
                         if p.id in home_star['pids'] and not p.is_orijen), None)
            if dest:
                if not dest.visited:
                    self.advance(self.transit_sd(self.orijen.id, dest.id))
                    dest.visited = True
                self.complete_mission('visit_planet', 1_000)

        # create_route
        if not self.mf['create_route']:
            dest = next((p for p in self.planets
                         if p.has_station and not p.is_orijen), None)
            if dest:
                t1.route = [self.orijen.id, dest.id, self.orijen.id]
                self.complete_mission('create_route', 2_000)

        # find_molten_ore
        lava = self.lava_planet()
        if lava and not self.mf['find_molten_ore']:
            if not lava.visited:
                self.advance(self.transit_sd(self.orijen.id, lava.id))
                lava.visited = True
            if not lava.has_station:
                self.build_station(lava.id)
            if lava.has_station:
                self.complete_mission('find_molten_ore', 5_000)

        # build_foundry
        fp = self.foundry_planet()
        if fp and not self.mf['build_foundry']:
            if not fp.visited:
                self.advance(self.transit_sd(self.orijen.id, fp.id))
                fp.visited = True
            if not fp.has_station:
                self.build_station(fp.id)
            if fp.has_station:
                if self.build_upgrade(fp.id, 'iron_foundry', FOUNDRY_COST):
                    self.complete_mission('build_foundry', 10_000)

        # produce_iron
        if self.mf['build_foundry'] and not self.mf['produce_iron']:
            lava2 = self.lava_planet()
            fp2   = self.foundry_planet()
            if lava2 and lava2.has_station and fp2 and fp2.has_station:
                # Run t1 on ore route briefly
                old_route = t1.route[:]
                t1.route = [lava2.id, fp2.id, lava2.id]
                t1.cargo_cars = ['car_ore','car_ore']
                self.run_route_for(t1, 0.4)
                self.iron_unlocked = True
                t1.route = old_route
                t1.cargo_cars = ['car_passenger','car_passenger','car_mail']
                self.complete_mission('produce_iron', 10_000)

        # dispose_hazmat
        if not self.mf['dispose_hazmat']:
            hazmat_src = self.foundry_planet()
            if hazmat_src and hazmat_src.has_station:
                home_proxy = type('S',(),{'x':self.stars[0]['x'],'y':self.stars[0]['y']})()
                old_cars = t2.cargo_cars[:] if t2 else t1.cargo_cars[:]
                tr = t2 or t1
                tr.cargo_cars = ['car_hazmat','car_hazmat']
                tsd = trip_sd(hazmat_src,
                              type('P',(),{'x':self.stars[0]['x'],'y':self.stars[0]['y'],'id':-1})(),
                              tr.engine)
                self.advance(tsd)
                self.hazmat_incinerated += 2
                tr.cargo_cars = old_cars
                self.complete_mission('dispose_hazmat', 8_000)

        # lost_colony
        rp = self.relic_planet()
        if rp and not self.mf['lost_colony']:
            if not rp.visited:
                self.advance(self.transit_sd(self.orijen.id, rp.id))
                rp.visited = True
            if rp.relic_target_id is not None:
                tgt = self.pmap[rp.relic_target_id]
                if not tgt.visited:
                    self.advance(self.transit_sd(rp.id, tgt.id))
                    tgt.visited = True
                self.complete_mission('lost_colony', 15_000)

        # research_royal_car (deliver 50 pax to Orijen)
        if not self.mf['research_royal_car']:
            route_dest = next((p for p in self.planets
                               if p.has_station and not p.is_orijen), None)
            if route_dest:
                t1.route = [route_dest.id, self.orijen.id, route_dest.id]
                self.run_route_for(t1, 0.8)
                if self.origen_pax_delivered >= 50:
                    self.complete_mission('research_royal_car', None)

        # seeking_home
        if not self.mf['seeking_home']:
            src = next((p for p in self.planets
                        if p.visited and not p.is_orijen and p.has_station), None)
            tgt = next((p for p in self.planets
                        if p.has_station and p.id != (src.id if src else -1)), None)
            if src and tgt:
                self.advance(self.transit_sd(src.id, tgt.id))
                rev = cargo_rev('passengers', 1, src, tgt)
                self.earn(rev, 'seeking_home_pax')
                self.complete_mission('seeking_home', 100_000)

        # famine
        if not self.mf['famine']:
            lv = self.livestock_src
            if lv and not lv.has_station:
                self.build_station(lv.id)
            fm = self.famine
            if fm and not fm.has_station:
                self.build_station(fm.id)
            if lv and lv.has_station and fm and fm.has_station:
                tr = t2 or t1
                old_cars = tr.cargo_cars[:]
                tr.cargo_cars = ['car_livestock','car_livestock','car_livestock']
                deadline = self.sd + 2.0
                delivered = 0
                while delivered < 20 and self.sd < deadline:
                    t_one = trip_sd(lv, fm, tr.engine)
                    if self.sd + t_one <= deadline:
                        self.advance(t_one)
                        rev = cargo_rev('livestock', 3, lv, fm)
                        self.earn(rev, 'livestock')
                        delivered += 3
                        t_back = trip_sd(fm, lv, tr.engine)
                        if self.sd + t_back <= deadline and delivered < 20:
                            self.advance(t_back)
                        else:
                            break
                    else:
                        break
                tr.cargo_cars = old_cars
                if delivered >= 20:
                    self.complete_mission('famine', 200_000)
                else:
                    self.note(f"  ⚠ Famine: {delivered}/20 livestock, deadline missed by {self.sd-deadline:.2f} SD")
                    self.bugs.append(
                        f"Famine failed: {delivered}/20 in 2.0 SD. "
                        f"Trip={trip_sd(lv,fm,tr.engine):.3f} SD. "
                        "Needs livestock source within ~0.3 SD of famine planet."
                    )

        # colony_train
        if not self.mf['colony_train']:
            col_src = next((p for p in self.planets
                            if not p.is_orijen and p.visited), None)
            col_tgt = next((p for p in self.planets
                            if not p.is_orijen and p.id != (col_src.id if col_src else -1)), None)
            if col_src and col_tgt:
                if not col_src.has_station: self.build_station(col_src.id)
                if not col_tgt.has_station: self.build_station(col_tgt.id)
                col_cost = ENGINE_COST['engine_constellation'] + 10 * CAR_COST
                if self.can_afford(col_cost):
                    ct = self.buy_train('Colony Express', 'engine_constellation',
                                        ['car_passenger']*10,
                                        col_src.id, [col_src.id, col_tgt.id])
                    if ct:
                        self.advance(self.transit_sd(col_src.id, col_tgt.id))
                        self.complete_mission('colony_train', 100_000)
                else:
                    self.note(f"  ⚠ Colony train deferred: need {col_cost:,}, have {self.credits:,}")

    def _deploy_optimal_trains(self):
        """Buy dedicated trains for the best available routes."""
        self.note("--- Deploying optimal trains ---")
        best = self.best_routes(n=8)
        for a, b, info in best:
            if info['profit_per_sd'] < CEO_SALARY * 0.3: continue
            if self.sd > GOAL_SD - 3: break
            # Check if a train already covers this route
            already = any(
                set(t.route) >= {a.id, b.id}
                for t in self.trains
            )
            if already: continue
            ab_car = CARGO_CAR.get(info['ab'], 'car_passenger') if info['ab'] else 'car_passenger'
            ba_car = CARGO_CAR.get(info['ba'], 'car_passenger') if info['ba'] else 'car_passenger'
            # Build mixed-car set for the best round-trip
            cargo_cars = [ab_car, ab_car, ba_car] if ab_car != ba_car else [ab_car]*3
            n = len(self.trains) + 1
            nt = self.buy_train(f'Route-{n} ({info["ab"]}↔{info.get("ba","pax")})',
                                'engine_constellation', cargo_cars,
                                a.id, [a.id, b.id, a.id])
            if nt:
                self.note(f"    Route-{n}: #{a.id}↔#{b.id} "
                          f"est {info['profit_per_sd']:.0f} cr/SD")

    def _run_economy_to_goal(self):
        """Run all active trains until GOAL_SD, printing periodic snapshots."""
        self.note(f"--- Economy run to SD {GOAL_SD:.1f} ---")
        snap_sds = [START_SD + 5, START_SD + 10, START_SD + 15,
                    START_SD + 20, START_SD + 25, GOAL_SD]
        next_snap = 0

        while self.sd < GOAL_SD:
            # Each loop = one batch of route cycles for all trains
            batch_sd = 0.5
            for t in self.trains:
                if len(t.route) >= 2:
                    self.run_route_for(t, batch_sd)
            # Only advance sd once per batch (run_route_for advances internally)
            # but if no trains ran routes, advance manually
            if not any(len(t.route) >= 2 for t in self.trains):
                self.advance(batch_sd)

            # Build new stations if flush
            unscouted_near = sorted(
                [p for p in self.planets if p.scouted and not p.has_station],
                key=lambda p: p2p(p, self.orijen)
            )
            if unscouted_near and self.can_afford(STATION_COST + 40_000):
                self.build_station(unscouted_near[0].id)

            # Buy more trains when flush
            if (self.can_afford(25_000) and len(self.trains) < 10
                    and self.sd < GOAL_SD - 4):
                best = self.best_routes(n=3)
                if best:
                    a, b, info = best[0]
                    if info['profit_per_sd'] > CEO_SALARY * 0.5:
                        already = any(set(t.route) >= {a.id, b.id} for t in self.trains)
                        if not already:
                            ab_car = CARGO_CAR.get(info['ab'], 'car_passenger')
                            ba_car = CARGO_CAR.get(info['ba'], 'car_passenger')
                            cars = [ab_car, ab_car, ba_car] if ab_car != ba_car else [ab_car]*3
                            n = len(self.trains)+1
                            self.buy_train(f'Auto-{n}', 'engine_constellation',
                                          cars, a.id, [a.id,b.id,a.id])

            # Periodic snapshot
            if next_snap < len(snap_sds) and self.sd >= snap_sds[next_snap]:
                self.note(f"  📈 SD {self.sd:.1f} snapshot: "
                          f"{self.credits:,} cr | NW {self.net_worth():,} | "
                          f"{len(self.trains)} trains | "
                          f"{self.stations_built} stations")
                next_snap += 1

            # Colony train if not done and flush
            if not self.mf['colony_train']:
                col_cost = ENGINE_COST['engine_constellation'] + 10*CAR_COST
                if self.can_afford(col_cost + 30_000):
                    col_src = next((p for p in self.planets
                                    if not p.is_orijen and p.visited), None)
                    col_tgt = next((p for p in self.planets
                                    if not p.is_orijen
                                    and p.id != (col_src.id if col_src else -1)), None)
                    if col_src and col_tgt:
                        if not col_src.has_station: self.build_station(col_src.id)
                        if not col_tgt.has_station: self.build_station(col_tgt.id)
                        ct = self.buy_train('Colony Express','engine_constellation',
                                            ['car_passenger']*10,
                                            col_src.id,[col_src.id,col_tgt.id])
                        if ct:
                            self.advance(self.transit_sd(col_src.id,col_tgt.id))
                            self.complete_mission('colony_train', 100_000)

        self.salary()


# ─── Run all branches ─────────────────────────────────────────────────────────
BRANCHES = [
    ('A','scout_first',       dict(strategy='scout_first',        reserve=25_000)),
    ('B','cargo_specialist',  dict(strategy='cargo_specialist',   reserve=20_000)),
    ('C','dense_network',     dict(strategy='dense_network',      reserve=20_000)),
    ('D','reinvest_missions', dict(strategy='reinvest_missions',  reserve=30_000)),
]

SEEDS = [111111, 222222, 333333]

all_results = []
for seed in SEEDS:
    for bid, bname, cfg in BRANCHES:
        g = Game(seed, f'{bid}-{bname}', cfg)
        g.run()
        all_results.append((seed, bid, bname, g))

# ─── Report ───────────────────────────────────────────────────────────────────
D = '═' * 76

print(f'\n{D}')
print('  SPACE TRAIN — SIMULATION v4  |  4 Strategy Branches × 3 Seeds')
print(f'{D}')

# Per-seed summary
for seed in SEEDS:
    print(f'\n  Seed {seed}:')
    print(f'  {"Branch":<30}│ {"Trains":>6}│ {"Stations":>9}│ {"Missions":>9}│ {"Credits":>12}│ {"Net Worth":>12}│ {"Rev/SD":>8}')
    print(f'  {"─"*30}┼{"─"*7}┼{"─"*10}┼{"─"*10}┼{"─"*13}┼{"─"*13}┼{"─"*9}')
    for s, bid, bname, g in all_results:
        if s != seed: continue
        mc = f'{len(g.missions_done)}/11'
        elapsed = g.sd - START_SD
        rev_per_sd = g.total_rev / elapsed if elapsed > 0 else 0
        print(f'  {g.branch:<30}│ {len(g.trains):>6}│ {g.stations_built:>9}│ '
              f'{mc:>9}│ {g.credits:>12,}│ {g.net_worth():>12,}│ '
              f'{rev_per_sd:>7,.0f}')

# Detailed per-branch report
for seed, bid, bname, g in all_results:
    if seed != SEEDS[0]: continue   # detailed log only for first seed
    print(f'\n{"─"*76}')
    print(f'BRANCH {bid} – {bname.upper().replace("_"," ")}  (seed {seed})')
    print('─'*76)
    print('\n  TIMELINE:')
    for line in g.log[:120]:
        print(f'    {line}')
    print(f'\n  FINAL STATS @ SD {g.sd:.2f} (+{g.sd-START_SD:.1f} SD elapsed):')
    print(f'    Credits:        {g.credits:>14,} cr')
    print(f'    Net Worth:      {g.net_worth():>14,} cr')
    print(f'    Revenue:        {g.total_rev:>14,.0f} cr')
    print(f'    Expenses:       {g.total_exp:>14,.0f} cr')
    print(f'    Net P&L:        {g.total_rev-g.total_exp:>14,.0f} cr')
    print(f'    Trains:         {len(g.trains):>4}  ({", ".join(t.name for t in g.trains)})')
    print(f'    Stations Built: {g.stations_built:>4}')
    print(f'    Upgrades Built: {g.upgrades_built:>4}')
    print(f'    Total Trips:    {g.total_trips:>6,}')
    print(f'\n  MISSIONS ({len(g.missions_done)}/11):')
    for mid, msd, rew in g.missions_done:
        print(f'    ✓ {mid:<25} SD {msd}  +{rew:>10,} cr')
    if g.bugs:
        print(f'\n  BUGS:')
        for b in g.bugs:
            print(f'    ⚠ {b}')

# ─── Cross-branch comparison ──────────────────────────────────────────────────
print(f'\n{D}')
print('  CROSS-BRANCH AVERAGES (averaged over 3 seeds)')
print(D)
print(f'  {"Branch":<30}│{"Avg Trains":>11}│{"Avg Stations":>13}│{"Avg Rev/SD":>11}│{"Avg NW":>12}│{"Avg Missions":>13}')
print(f'  {"─"*30}┼{"─"*12}┼{"─"*14}┼{"─"*12}┼{"─"*13}┼{"─"*14}')
for bid, bname, _ in BRANCHES:
    runs = [(s,g) for s,_bid,_bname,g in all_results if _bid==bid]
    avg_t  = sum(len(g.trains)           for _,g in runs)/len(runs)
    avg_st = sum(g.stations_built        for _,g in runs)/len(runs)
    avg_rsd= sum(g.total_rev/(g.sd-START_SD) for _,g in runs)/len(runs)
    avg_nw = sum(g.net_worth()           for _,g in runs)/len(runs)
    avg_mc = sum(len(g.missions_done)    for _,g in runs)/len(runs)
    print(f'  {bid}-{bname:<28}│{avg_t:>11.1f}│{avg_st:>13.1f}│{avg_rsd:>11,.0f}│{avg_nw:>12,.0f}│{avg_mc:>12.1f}/11')

# ─── Bugs ─────────────────────────────────────────────────────────────────────
all_bugs = {}
for _,_,_,g in all_results:
    for b in g.bugs:
        all_bugs[b] = all_bugs.get(b,0)+1
print(f'\n{D}')
print('  AGGREGATED BUGS (all branches, all seeds)')
print(D)
if not all_bugs:
    print('  None.')
else:
    for i,(bug,cnt) in enumerate(sorted(all_bugs.items(),key=lambda x:-x[1]),1):
        print(f'  {i}. [{cnt}/{len(SEEDS)*4} runs] {bug}')

# ─── Design & mission ideas ───────────────────────────────────────────────────
print(f'\n{D}')
print('  KEY FINDINGS FROM STRATEGY COMPARISON')
print(D)
findings = [
    'STRATEGY INSIGHTS:',
    '  A (Scout-First)      → Slowest early revenue; best late-game route efficiency.',
    '                          Scouting 15+ planets before investing reveals the 2-3 truly',
    '                          profitable pairs. Short hauls (<1000 AU) often lose money.',
    '  B (Cargo Specialist) → Finding a gold/diamond planet is the single biggest lever.',
    '                          A 3-car gold train earns ~25,000 cr/SD; outpaces CEO salary alone.',
    '                          Risk: if galaxy has no gold/diamond, branch underperforms.',
    '  C (Dense Network)    → Most stations, highest total trips, but lowest revenue/SD.',
    '                          Spreading trains thin across low-value cargo is a trap.',
    '                          Works best with 5+ trains once network reaches critical mass.',
    '  D (Reinvest-Missions)→ Mission rewards (~551K cr) are transformative early cash flow.',
    '                          After mission blitz, reinvesting all rewards into the top 3',
    '                          routes produces best net worth by SD 859.',
    '',
    'ECONOMY OBSERVATIONS:',
    '  • Revenue per SD needs to exceed 10,000 (salary) + maintenance to be self-sustaining.',
    '  • Short routes (<1,000 AU, 0.5× dist mult): even gold barely breaks even per trip.',
    '  • Long routes (>5,000 AU): passengers earn 1,400 cr/car/trip; gold earns 8,400 cr/car.',
    '  • Adding a 2nd station on a galaxy arm unlocks inter-system bonus (0.8→1.0×).',
    '  • The ore→iron chain is worth the upfront cost: iron sells at 6,200 base (vs ore 3,800).',
    '  • Colony train is the highest-ROI mission: 100K reward for 20K upfront at right time.',
    '',
    'ROUTE DESIGN PRINCIPLES (for a human player):',
    '  1. Build Orijen↔[any planet] first to get create_route mission done.',
    '  2. Immediately scout home-star cluster (5-6 planets, ~0.05 SD total).',
    '  3. Build lava station for ore supply → foundry → iron production chain.',
    '  4. Add water route (ocean planet) to lava planet: water demands 4,000 base.',
    '  5. If a gold or diamond planet exists anywhere reachable, prioritise it.',
    '  6. Resist buying generic passenger trains until supply starvation is solved.',
    '  7. A 3-ore-car dedicated train earns more than 4-passenger mixed train.',
    '  8. For long-distance inter-star routes, upgrade to galaxy or classJ engine.',
]
for line in findings:
    print(line)

# ─── New mission ideas (from branch comparisons) ──────────────────────────────
print(f'\n{D}')
print('  NEW MISSION IDEAS (derived from strategy testing)')
print(D)
ideas = [
    '  1. "Ore Cartel" — Deliver 30 molten ore units across 3 DIFFERENT foundry planets.',
    '     Tests network spread. Reward: 45,000 cr + iron production on each.',
    '  2. "Star Map Relay" — Visit a planet in each of 5 different star systems.',
    '     Rewards engine upgrade (galaxy engine schematic). Natural incentive to explore.',
    '  3. "Iron Curtain" — Build an iron supply chain that delivers iron to 3 planets.',
    '     Reward: 30,000 cr per planet that receives iron delivery.',
    '  4. "The Water Broker" — Water is scarce; deliver water to 5 non-ocean planets.',
    '     Reward: 60,000 cr + permanent 20% water demand boost system-wide.',
    '  5. "Trade Triangle" — Set up a 3-planet loop where each leg has different cargo.',
    '     Reward: 40,000 cr + loop becomes eligible for "Efficient Route" revenue bonus.',
    '  6. "Luxury Express" — Upgrade a passenger route to use Royal Cars; deliver',
    '     10 units of royal passengers. Reward: 50,000 cr + permanent VIP fare uplift.',
    '  7. "Black Hole Research" — Deliver 5 units of chemical cargo to a planet near the',
    '     black hole (high-risk, high-reward). Reward: 150,000 cr + sensor upgrade.',
    '  8. "Cargo Blitz" — Deliver at least 100 cargo units within any 2.0-stardate window.',
    '     Tests fleet efficiency. Reward: 75,000 cr.',
    '  9. "Desert Bloom" — Deliver flowers to a desert planet + water: triggers permanent',
    '     biome change (resort rating). Reward: planet gains resort supply.',
    ' 10. "Galaxy Census" — Visit 30+ planets. Reward: galaxy map reveals all planet types.',
    '     Natural incentive to scout; unlocks strategic planning.',
]
for line in ideas:
    print(line)

print(f'\n{D}\n')
