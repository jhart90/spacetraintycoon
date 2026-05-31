"""
ai_sim3.py  —  Enhanced worst-case / revenue-threshold simulation
Based on ai_sim2.py; adds exploration-bottleneck modelling, hard-galaxy
scenario, and a revenue-threshold sweep to find the 90% break point.

Success criterion: trains >= 25 AND stations >= 25 by SD 880.
Simulation window: SD 829 – SD 880  (51 SD of play after the early game).
"""

import random
import statistics


# ---------------------------------------------------------------------------
# Core simulator
# ---------------------------------------------------------------------------

def simulate(params, seed=42):
    rng = random.Random(seed)

    credits = params['start_credits']
    trains   = params['start_trains']
    stations = params['start_stations']

    last_train   = -999.0
    last_station = -999.0

    # ---- Exploration state ------------------------------------------------
    # 'discovered_stars' counts stars whose planets are *known* (can build on)
    # 'discovered_planets' is the total planet pool we may station
    discovered_stars   = 1
    discovered_planets = params.get('home_star_planets', 5)

    # Per-trip distributions (can be overridden by 'hard_galaxy' flag)
    planets_per_new_star_min = params.get('planets_per_star_min', 3)
    planets_per_new_star_max = params.get('planets_per_star_max', 6)
    trip_sd_min = params.get('trip_sd_min', 3.0)
    trip_sd_max = params.get('trip_sd_max', 6.0)

    exploring     = 0           # trains currently on an exploration trip
    explore_events = []         # list of (return_sd, new_planets_count)

    duration = 51.0   # SD 829 -> SD 880
    dt       = 0.05

    steps = int(duration / dt)

    for i in range(steps):
        sd = i * dt

        # ---- Process exploration returns ----------------------------------
        still_out = []
        for (ret_sd, n_pl) in explore_events:
            if sd >= ret_sd:
                exploring          -= 1
                discovered_stars   += 1
                discovered_planets += n_pl
            else:
                still_out.append((ret_sd, n_pl))
        explore_events = still_out

        # ---- Revenue ------------------------------------------------------
        routing_trains = max(0, trains - exploring)
        # Network multiplier: +4% per stationed planet, soft-cap at 30 planets
        net_mult  = 1.0 + min(stations, 30) * 0.04
        # Revenue variance: uniform over [0.7, 1.3] per SD
        base_rev  = params['rev_per_train'] * (0.7 + 0.6 * rng.random())
        credits  += routing_trains * base_rev * net_mult * dt

        # ---- P0: explore if below target ----------------------------------
        explore_target = params.get('explore_target', 15)
        max_explorers  = params.get('max_explorers', 1)

        if (discovered_stars < explore_target
                and exploring < max_explorers
                and trains > exploring + 1):          # keep ≥1 routing train
            trip_dur = rng.uniform(trip_sd_min, trip_sd_max)
            n_new    = rng.randint(planets_per_new_star_min,
                                   planets_per_new_star_max)
            explore_events.append((sd + trip_dur, n_new))
            exploring += 1
            continue

        unstationed = max(0, discovered_planets - stations)

        # ---- P1.5: trains-first (when trains_first=True) ------------------
        if params.get('trains_first', False):
            t_cost   = params['train_cost']
            t_thresh = t_cost * params.get('train_buf', 1.1)
            t_cool   = params.get('train_cool', 0.4)
            if credits >= t_thresh and (sd - last_train) >= t_cool:
                credits    -= t_cost
                trains     += 1
                last_train  = sd
                continue

        # ---- P2: build station --------------------------------------------
        if unstationed > 0:
            s_cost   = params['station_cost']
            s_thresh = s_cost * params.get('sta_buf', 1.1)
            s_cool   = params.get('sta_cool', 0.15)
            if credits >= s_thresh and (sd - last_station) >= s_cool:
                credits      -= s_cost
                stations     += 1
                last_station  = sd
                continue

        # ---- P3: buy train (fallback / no trains_first) -------------------
        if not params.get('trains_first', False):
            t_cost   = params['train_cost']
            t_thresh = t_cost * params.get('train_buf', 1.2)
            t_cool   = params.get('train_cool', 0.4)
            if credits >= t_thresh and (sd - last_train) >= t_cool:
                credits    -= t_cost
                trains     += 1
                last_train  = sd

    return trains, stations


# ---------------------------------------------------------------------------
# Batch runner
# ---------------------------------------------------------------------------

def run_test(params, n=50):
    results = [simulate(params, seed=i) for i in range(n)]
    success  = sum(1 for tr, st in results if tr >= 25 and st >= 25)
    avg_tr   = statistics.mean(tr for tr, st in results)
    avg_st   = statistics.mean(st for tr, st in results)
    min_tr   = min(tr for tr, st in results)
    min_st   = min(st for tr, st in results)
    return dict(success=success, n=n, rate=success/n,
                avg_tr=avg_tr, avg_st=avg_st,
                min_tr=min_tr, min_st=min_st)


def print_result(label, res):
    tick = "PASS" if res['rate'] >= 0.90 else ("MARGINAL" if res['rate'] >= 0.70 else "FAIL")
    print(f"  [{tick}] {label}")
    print(f"    Success : {res['success']}/{res['n']}  ({res['rate']*100:.1f}%)")
    print(f"    Avg  tr : {res['avg_tr']:.1f}   Min tr : {res['min_tr']}")
    print(f"    Avg  st : {res['avg_st']:.1f}   Min st : {res['min_st']}")
    print()


# ---------------------------------------------------------------------------
# Parameter sets
# ---------------------------------------------------------------------------

COMMON = dict(
    station_cost      = 50_000,
    train_cost        = 63_000,
    home_star_planets = 5,
    # Exploration trip defaults (normal galaxy)
    planets_per_star_min = 3,
    planets_per_star_max = 6,
    trip_sd_min          = 3.0,
    trip_sd_max          = 6.0,
)

# Old baseline (pre-iteration-1 defaults, for comparison)
old_baseline = dict(
    **COMMON,
    start_credits  = 220_000,
    start_trains   = 1,
    start_stations = 2,
    train_buf      = 1.8,
    sta_buf        = 1.5,
    train_cool     = 1.0,
    sta_cool       = 0.5,
    explore_target = 10,
    max_explorers  = 2,
    trains_first   = False,
    rev_per_train  = 15_000,
)

# Iteration-1 parameters (as implemented in build_game.py)
iter1 = dict(
    **COMMON,
    start_credits  = 500_000,
    start_trains   = 3,
    start_stations = 3,
    train_buf      = 1.1,   # P1.5
    sta_buf        = 1.1,   # P2
    train_cool     = 0.4,   # P1.5 and P3
    sta_cool       = 0.15,  # P2
    explore_target = 15,
    max_explorers  = 1,
    trains_first   = True,
    rev_per_train  = 15_000,
)

# Hard-galaxy overrides (minimum planet yield, slowest trips, tiny home star)
HARD_GALAXY = dict(
    home_star_planets    = 3,   # only 3 planets on home star
    planets_per_star_min = 3,   # every new star gives exactly 3 planets
    planets_per_star_max = 3,
    trip_sd_min          = 6.0, # all trips take 6 SD (max)
    trip_sd_max          = 6.0,
)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

print("=" * 65)
print("ITER-1 WORST-CASE / REVENUE-THRESHOLD SIMULATION  (ai_sim3.py)")
print("Success: trains >= 25 AND stations >= 25 at SD 880")
print("n = 50 runs per scenario")
print("=" * 65)
print()

# ===========================================================================
# SECTION 1: Revenue sensitivity with Iteration-1 parameters
# ===========================================================================
print("-" * 65)
print("SECTION 1 -- Revenue sensitivity (Iter-1 params, normal galaxy)")
print("-" * 65)
print()

rev_scenarios = [
    ("Iter-1  @ 15K rev/train/SD  [baseline realistic]", 15_000),
    ("Iter-1  @ 10K rev/train/SD  [very pessimistic]",   10_000),
    ("Iter-1  @  8K rev/train/SD  [worst case]",          8_000),
    ("Iter-1  @  5K rev/train/SD  [extreme worst case]",  5_000),
]

rev_results = {}
for label, rev in rev_scenarios:
    res = run_test({**iter1, 'rev_per_train': rev})
    rev_results[rev] = res
    print_result(label, res)

# Old baseline comparison
res_old = run_test(old_baseline)
print_result("Old baseline @ 15K rev/train/SD  [comparison]", res_old)

# ===========================================================================
# SECTION 2: Hard-galaxy scenario
# ===========================================================================
print("-" * 65)
print("SECTION 2 -- Hard-galaxy scenario")
print("  * Only 3 planets on home star")
print("  * Every new star yields exactly 3 planets")
print("  * Exploration trips take exactly 6 SD")
print("-" * 65)
print()

hard_revs = [15_000, 10_000, 8_000, 5_000]
hard_results = {}
for rev in hard_revs:
    cfg = {**iter1, **HARD_GALAXY, 'rev_per_train': rev}
    res = run_test(cfg)
    hard_results[rev] = res
    print_result(f"Hard galaxy @ {rev//1000}K rev/train/SD", res)

# ===========================================================================
# SECTION 3: Revenue threshold sweep (find 90% break point)
# ===========================================================================
print("-" * 65)
print("SECTION 3 -- Revenue threshold sweep (normal galaxy, n=50 each)")
print("  Finding the revenue per-train/SD where success rate crosses 90%")
print("-" * 65)
print()

sweep_revs   = list(range(5_000, 20_001, 1_000))
threshold_90_normal = None
threshold_90_hard   = None

print("  Normal galaxy:")
print(f"  {'Rev/tr/SD':>12}   {'Success%':>8}   {'AvgTr':>6}   {'AvgSt':>6}   {'MinTr':>5}   {'MinSt':>5}")
print(f"  {'--'*6}   {'--'*4}   {'--'*3}   {'--'*3}   {'--'*2}   {'--'*2}")

sweep_normal = {}
for rev in sweep_revs:
    res = run_test({**iter1, 'rev_per_train': rev}, n=50)
    sweep_normal[rev] = res
    flag = " <-- 90% threshold" if (threshold_90_normal is None and res['rate'] >= 0.90) else ""
    if threshold_90_normal is None and res['rate'] >= 0.90:
        threshold_90_normal = rev
    print(f"  {rev:>12,}   {res['rate']*100:>7.1f}%   "
          f"{res['avg_tr']:>6.1f}   {res['avg_st']:>6.1f}   "
          f"{res['min_tr']:>5}   {res['min_st']:>5}{flag}")
print()

print("  Hard galaxy:")
print(f"  {'Rev/tr/SD':>12}   {'Success%':>8}   {'AvgTr':>6}   {'AvgSt':>6}   {'MinTr':>5}   {'MinSt':>5}")
print(f"  {'--'*6}   {'--'*4}   {'--'*3}   {'--'*3}   {'--'*2}   {'--'*2}")

sweep_hard = {}
for rev in sweep_revs:
    cfg = {**iter1, **HARD_GALAXY, 'rev_per_train': rev}
    res = run_test(cfg, n=50)
    sweep_hard[rev] = res
    flag = " <-- 90% threshold" if (threshold_90_hard is None and res['rate'] >= 0.90) else ""
    if threshold_90_hard is None and res['rate'] >= 0.90:
        threshold_90_hard = rev
    print(f"  {rev:>12,}   {res['rate']*100:>7.1f}%   "
          f"{res['avg_tr']:>6.1f}   {res['avg_st']:>6.1f}   "
          f"{res['min_tr']:>5}   {res['min_st']:>5}{flag}")
print()

# ===========================================================================
# SUMMARY
# ===========================================================================
print("=" * 65)
print("SUMMARY")
print("=" * 65)
print()
print("Revenue sensitivity (normal galaxy, Iter-1):")
for rev, label_short in [(15_000, "15K"), (10_000, "10K"), (8_000, "8K"), (5_000, "5K")]:
    r = rev_results[rev]
    tick = "PASS" if r['rate'] >= 0.90 else ("MARGINAL" if r['rate'] >= 0.70 else "FAIL")
    print(f"  {label_short:>4} rev/tr/SD  ->  {r['rate']*100:5.1f}%  [{tick}]")
print()
print("Hard-galaxy results (Iter-1):")
for rev, label_short in [(15_000, "15K"), (10_000, "10K"), (8_000, "8K"), (5_000, "5K")]:
    r = hard_results[rev]
    tick = "PASS" if r['rate'] >= 0.90 else ("MARGINAL" if r['rate'] >= 0.70 else "FAIL")
    print(f"  {label_short:>4} rev/tr/SD  ->  {r['rate']*100:5.1f}%  [{tick}]")
print()

if threshold_90_normal is not None:
    print(f"Normal galaxy 90% threshold : {threshold_90_normal:,} rev/train/SD")
else:
    print("Normal galaxy 90% threshold : not reached within sweep range")

if threshold_90_hard is not None:
    print(f"Hard galaxy   90% threshold : {threshold_90_hard:,} rev/train/SD")
else:
    print("Hard galaxy   90% threshold : not reached within sweep range")

print()
r_old  = res_old
r_new  = rev_results[15_000]
print(f"Old baseline @ 15K  ->  {r_old['rate']*100:.1f}%  "
      f"(avg {r_old['avg_tr']:.0f} tr / {r_old['avg_st']:.0f} st)")
print(f"Iter-1       @ 15K  ->  {r_new['rate']*100:.1f}%  "
      f"(avg {r_new['avg_tr']:.0f} tr / {r_new['avg_st']:.0f} st)")
