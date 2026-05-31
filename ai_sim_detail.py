"""
Detailed breakdown for the best config found by ai_sim.py
"""
import random
from collections import defaultdict

GOAL_SD      = 880
START_SD     = 829
MAX_SD       = GOAL_SD - START_SD
TRAIN_GOAL   = 25
STATION_GOAL = 25
STATION_COST = 50_000
TRAIN_COST   = 63_000

def revenue_mult(stations):
    return 1.0 + min(stations, 30) * 0.04

def run_sim(cfg, base_rev):
    credits          = cfg["start_credits"]
    trains           = cfg["start_trains"]
    stations         = cfg["start_stations"]
    discovered_stars = cfg["start_discovered_stars"]
    visited_planets  = cfg["start_visited_planets"]

    train_buffer     = cfg["train_buffer"]
    station_buffer   = cfg["station_buffer"]
    train_cooldown   = cfg["train_cooldown"]
    station_cooldown = cfg["station_cooldown"]
    explore_target   = cfg["explore_target"]

    last_train_buy   = -999.0
    last_station_buy = -999.0
    pending_discoveries = []

    t = 0.0
    dt = 0.1

    while t < MAX_SD:
        newly_discovered = [d for d in pending_discoveries if d <= t]
        if newly_discovered:
            pending_discoveries = [d for d in pending_discoveries if d > t]
            for _ in newly_discovered:
                discovered_stars += 1
                visited_planets  += 4

        exploring = min((trains + 2) // 3, 1) if discovered_stars < explore_target else 0
        routing   = max(0, trains - exploring)
        rev = (routing * base_rev + exploring * base_rev * 0.20) * revenue_mult(stations) * dt
        credits += rev

        if discovered_stars < explore_target and exploring > 0 and not pending_discoveries:
            pending_discoveries.append(t + random.uniform(2.0, 4.0))

        unstationed = max(0, visited_planets - stations)

        if (credits >= STATION_COST * station_buffer
                and (t - last_station_buy) >= station_cooldown
                and unstationed > 0):
            credits          -= STATION_COST
            stations         += 1
            last_station_buy  = t
            t += dt
            continue

        if (credits >= TRAIN_COST * train_buffer
                and (t - last_train_buy) >= train_cooldown):
            credits        -= TRAIN_COST
            trains         += 1
            last_train_buy  = t

        t += dt

    return trains, stations, (trains >= TRAIN_GOAL) and (stations >= STATION_GOAL)

# Best config from grid search
BEST = dict(
    start_credits          = 220_000,
    start_trains           = 1,
    start_stations         = 2,
    start_discovered_stars = 1,
    start_visited_planets  = 4,
    train_buffer           = 1.2,
    station_buffer         = 1.15,
    train_cooldown         = 0.3,
    station_cooldown       = 0.1,
    explore_target         = 10,
)

BASELINE = dict(
    start_credits          = 220_000,
    start_trains           = 1,
    start_stations         = 2,
    start_discovered_stars = 1,
    start_visited_planets  = 4,
    train_buffer           = 1.5,
    station_buffer         = 1.3,
    train_cooldown         = 0.5,
    station_cooldown       = 0.2,
    explore_target         = 10,
)

print("=" * 65)
print("BEST CONFIG — detailed breakdown (60K rev, 200 runs)")
print("=" * 65)
random.seed(0)
train_hist   = defaultdict(int)
station_hist = defaultdict(int)
successes    = 0
for _ in range(200):
    tr, st, ok = run_sim(BEST, 60_000)
    train_hist[tr]   += 1
    station_hist[st] += 1
    if ok:
        successes += 1

print(f"  Success rate: {successes}/200 ({successes/2:.1f}%)")
print(f"\n  Train distribution (goal >= {TRAIN_GOAL}):")
for v in sorted(train_hist):
    bar  = "#" * train_hist[v]
    mark = " <-- GOAL" if v == TRAIN_GOAL else (" (above goal)" if v > TRAIN_GOAL else "")
    print(f"    {v:4d} trains: {train_hist[v]:4d}x  {bar}{mark}")

print(f"\n  Station distribution (goal >= {STATION_GOAL}):")
for v in sorted(station_hist):
    bar  = "#" * station_hist[v]
    mark = " <-- GOAL" if v == STATION_GOAL else (" (above goal)" if v > STATION_GOAL else "")
    print(f"    {v:4d} stations: {station_hist[v]:4d}x  {bar}{mark}")

# Cross-revenue check
print("\n" + "=" * 65)
print("CROSS-REVENUE SUCCESS RATES (200 runs each)")
print("=" * 65)
for rev in [40_000, 60_000, 80_000]:
    random.seed(1)
    s = sum(run_sim(BEST, rev)[2] for _ in range(200))
    print(f"  Rev={rev//1000:3d}K  success {s}/200 ({s/2:.1f}%)")

# Vs baseline
print("\n" + "=" * 65)
print("BASELINE vs BEST comparison (200 runs, 60K rev)")
print("=" * 65)
for label, cfg in [("Baseline (current)", BASELINE), ("Best found", BEST)]:
    random.seed(2)
    s = sum(run_sim(cfg, 60_000)[2] for _ in range(200))
    print(f"  {label:22s}  success {s}/200 ({s/2:.1f}%)")

print("\n" + "=" * 65)
print("RECOMMENDED very_hard CONFIG")
print("=" * 65)
c = BEST
print(f"""
  start_credits    = {c['start_credits']:,}
  start_trains     = {c['start_trains']}
  start_stations   = {c['start_stations']}
  train_buffer     = {c['train_buffer']}    (was 1.5)
  station_buffer   = {c['station_buffer']}   (was 1.3)
  train_cooldown   = {c['train_cooldown']} SD  (was 0.5)
  station_cooldown = {c['station_cooldown']} SD  (was 0.2)
  explore_target   = {c['explore_target']} stars   (unchanged)
""")
