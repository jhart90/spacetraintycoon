"""
Space Train Game - Very Hard AI Parameter Optimizer
Monte Carlo simulation to find the best parameter configuration for the AI
to reach 25+ trains AND 25+ stations by S.D. 880 (51 stardates from S.D. 829).
"""

import random
import itertools
from collections import defaultdict
import time

# ─── Constants ────────────────────────────────────────────────────────────────
GOAL_SD          = 880
START_SD         = 829
MAX_SD           = GOAL_SD - START_SD   # 51 ticks to simulate (1 tick = 1 SD)
TRAIN_GOAL       = 25
STATION_GOAL     = 25
NUM_RUNS         = 50

STATION_COST     = 50_000
TRAIN_COST       = 63_000              # very_hard engine package

# Revenue multiplier formula: 1.0 + min(stations, 30) * 0.04
def revenue_mult(stations):
    return 1.0 + min(stations, 30) * 0.04

# ─── Single Simulation Run ────────────────────────────────────────────────────
def run_sim(cfg, base_rev):
    """
    Returns (trains_final, stations_final, success:bool)
    """
    credits           = cfg["start_credits"]
    trains            = cfg["start_trains"]
    stations          = cfg["start_stations"]
    discovered_stars  = cfg["start_discovered_stars"]
    visited_planets   = cfg["start_visited_planets"]

    train_buffer      = cfg["train_buffer"]
    station_buffer    = cfg["station_buffer"]
    train_cooldown    = cfg["train_cooldown"]
    station_cooldown  = cfg["station_cooldown"]
    explore_target    = cfg["explore_target"]

    last_train_buy    = -999.0
    last_station_buy  = -999.0

    # Track pending exploration discoveries (list of SD when they arrive)
    pending_discoveries = []

    def assign_exploration():
        # exploring trains = min(ceil(trains/3), 1) when below explore_target
        # Actually re-reading the spec: min(ceil(trains/3), 1) — that's always 1
        # Interpret as: number of exploring trains = min(ceil(trains/3), max_exploring)
        # But the spec says "min(ceil(trains/3), 1)" which caps at 1.
        # We'll follow the spec literally.
        if discovered_stars < explore_target:
            return min((trains + 2) // 3, 1)   # ceil(trains/3) capped at 1
        return 0

    t = 0.0   # current stardate offset
    dt = 0.1  # simulation step (0.1 SD per tick for smoother decisions)

    while t < MAX_SD:
        # ── Resolve pending star discoveries ──
        newly_discovered = [d for d in pending_discoveries if d <= t]
        if newly_discovered:
            pending_discoveries = [d for d in pending_discoveries if d > t]
            for _ in newly_discovered:
                discovered_stars += 1
                visited_planets  += 4   # ~4 new planets per star

        # ── Revenue this step ──
        exploring = assign_exploration()
        routing   = max(0, trains - exploring)
        rev = (routing * base_rev + exploring * base_rev * 0.20) * revenue_mult(stations) * dt
        credits += rev

        # ── Schedule exploration if below target and no pending discovery ──
        if discovered_stars < explore_target and exploring > 0:
            # If we don't already have a pending discovery, queue one
            if not pending_discoveries:
                delay = random.uniform(2.0, 4.0)
                pending_discoveries.append(t + delay)

        unstationed = max(0, visited_planets - stations)

        # ── P2: Build station ──
        if (credits >= STATION_COST * station_buffer
                and (t - last_station_buy) >= station_cooldown
                and unstationed > 0):
            credits          -= STATION_COST
            stations         += 1
            last_station_buy  = t
            t += dt
            continue

        # ── P3: Buy train ──
        if (credits >= TRAIN_COST * train_buffer
                and (t - last_train_buy) >= train_cooldown):
            credits         -= TRAIN_COST
            trains          += 1
            last_train_buy   = t

        t += dt

    success = (trains >= TRAIN_GOAL) and (stations >= STATION_GOAL)
    return trains, stations, success

# ─── Run N trials for a config at a given base revenue ───────────────────────
def eval_config(cfg, base_rev, n=NUM_RUNS):
    successes = 0
    train_sum = 0
    station_sum = 0
    for _ in range(n):
        tr, st, ok = run_sim(cfg, base_rev)
        if ok:
            successes += 1
        train_sum   += tr
        station_sum += st
    return successes, train_sum / n, station_sum / n

# ─── Current "very_hard" baseline config ─────────────────────────────────────
BASELINE = dict(
    start_credits       = 220_000,
    start_trains        = 1,
    start_stations      = 2,
    start_discovered_stars = 1,
    start_visited_planets  = 4,
    train_buffer        = 1.5,
    station_buffer      = 1.3,
    train_cooldown      = 0.5,
    station_cooldown    = 0.2,
    explore_target      = 10,
)

# ─── Grid definition ─────────────────────────────────────────────────────────
GRID = dict(
    start_credits     = [220_000, 350_000, 500_000, 700_000],
    start_trains      = [1, 2, 3, 4],
    start_stations    = [2, 3, 4, 5],
    train_buffer      = [1.2, 1.5, 1.8],
    station_buffer    = [1.15, 1.3, 1.5],
    train_cooldown    = [0.3, 0.5, 1.0],
    station_cooldown  = [0.1, 0.2, 0.5],
    explore_target    = [10, 15],
)

FIXED = dict(
    start_discovered_stars = 1,
    start_visited_planets  = 4,
)

REVENUE_LEVELS = [40_000, 60_000, 80_000]

# ─── Main ─────────────────────────────────────────────────────────────────────
def main():
    random.seed(42)
    t0 = time.time()

    # ── Baseline ──────────────────────────────────────────────────────────────
    print("=" * 70)
    print("BASELINE (current very_hard parameters)")
    print("=" * 70)
    for rev in REVENUE_LEVELS:
        succ, avg_tr, avg_st = eval_config(BASELINE, rev)
        pct = succ / NUM_RUNS * 100
        print(f"  Rev={rev//1000:3d}K  success {succ:2d}/{NUM_RUNS} ({pct:5.1f}%)  "
              f"avg trains={avg_tr:.1f}  avg stations={avg_st:.1f}")
    print()

    # ── Grid search ──────────────────────────────────────────────────────────
    keys   = list(GRID.keys())
    values = list(GRID.values())
    combos = list(itertools.product(*values))
    total  = len(combos)
    print(f"Grid search: {total:,} configurations × {NUM_RUNS} runs × "
          f"{len(REVENUE_LEVELS)} revenue levels\n")

    # Store results as list of (succ_40, succ_60, succ_80, avg_trains_60, avg_stations_60, cfg)
    results = []
    report_every = max(1, total // 20)  # progress every ~5%

    for i, combo in enumerate(combos):
        cfg = dict(zip(keys, combo))
        cfg.update(FIXED)

        row = [cfg]
        for rev in REVENUE_LEVELS:
            succ, avg_tr, avg_st = eval_config(cfg, rev)
            row.append(succ)
            if rev == 60_000:
                row.append(avg_tr)
                row.append(avg_st)

        # row = [cfg, succ_40, succ_60, avg_tr_60, avg_st_60, succ_80]
        results.append(tuple(row))

        if (i + 1) % report_every == 0:
            elapsed = time.time() - t0
            pct_done = (i + 1) / total * 100
            eta = elapsed / (i + 1) * (total - i - 1)
            print(f"  Progress: {i+1:,}/{total:,} ({pct_done:.0f}%)  "
                  f"elapsed={elapsed:.0f}s  ETA={eta:.0f}s")

    print(f"\nGrid search complete in {time.time()-t0:.1f}s\n")

    # ── Sort and display top 5 per revenue level ──────────────────────────────
    REV_IDX = {40_000: 1, 60_000: 2, 80_000: 5}   # index in results tuple

    for rev in REVENUE_LEVELS:
        idx = REV_IDX[rev]
        ranked = sorted(results, key=lambda r: r[idx], reverse=True)[:5]
        print("=" * 70)
        print(f"TOP 5 CONFIGS  —  Revenue = {rev//1000}K cr/train/SD")
        print("=" * 70)
        for rank, row in enumerate(ranked, 1):
            cfg   = row[0]
            succ  = row[idx]
            pct   = succ / NUM_RUNS * 100
            # also show results at other rev levels
            s40 = row[1]; s60 = row[2]; s80 = row[5]
            p40 = s40/NUM_RUNS*100; p60 = s60/NUM_RUNS*100; p80 = s80/NUM_RUNS*100
            print(f"\n  #{rank}  success@{rev//1000}K = {succ}/{NUM_RUNS} ({pct:.0f}%)  "
                  f"[40K:{p40:.0f}%  60K:{p60:.0f}%  80K:{p80:.0f}%]")
            print(f"       start_credits={cfg['start_credits']:,}  "
                  f"trains={cfg['start_trains']}  stations={cfg['start_stations']}")
            print(f"       train_buf={cfg['train_buffer']}  stn_buf={cfg['station_buffer']}  "
                  f"train_cd={cfg['train_cooldown']}  stn_cd={cfg['station_cooldown']}")
            print(f"       explore_target={cfg['explore_target']}")
        print()

    # ── Overall best: highest sum of successes across all three rev levels ────
    ranked_all = sorted(results,
                        key=lambda r: r[1] + r[2] + r[5],
                        reverse=True)[:5]

    print("=" * 70)
    print("TOP 5 CONFIGS  —  Best OVERALL (sum of successes across 40K+60K+80K)")
    print("=" * 70)
    for rank, row in enumerate(ranked_all, 1):
        cfg  = row[0]
        s40, s60, s80 = row[1], row[2], row[5]
        avg_tr, avg_st = row[3], row[4]
        total_succ = s40 + s60 + s80
        print(f"\n  #{rank}  total_successes={total_succ}/{NUM_RUNS*3}  "
              f"[40K:{s40/NUM_RUNS*100:.0f}%  60K:{s60/NUM_RUNS*100:.0f}%  "
              f"80K:{s80/NUM_RUNS*100:.0f}%]")
        print(f"       start_credits={cfg['start_credits']:,}  "
              f"trains={cfg['start_trains']}  stations={cfg['start_stations']}")
        print(f"       train_buf={cfg['train_buffer']}  stn_buf={cfg['station_buffer']}  "
              f"train_cd={cfg['train_cooldown']}  stn_cd={cfg['station_cooldown']}")
        print(f"       explore_target={cfg['explore_target']}")
        print(f"       avg trains (60K rev)={avg_tr:.1f}  avg stations (60K rev)={avg_st:.1f}")

    # ── Detailed breakdown for best overall config ────────────────────────────
    best_cfg = ranked_all[0][0]
    print("\n" + "=" * 70)
    print("DETAILED BREAKDOWN — Best overall config (60K revenue, 200 runs)")
    print("=" * 70)
    random.seed(0)
    train_hist    = defaultdict(int)
    station_hist  = defaultdict(int)
    successes     = 0
    for _ in range(200):
        tr, st, ok = run_sim(best_cfg, 60_000)
        train_hist[tr]   += 1
        station_hist[st] += 1
        if ok:
            successes += 1

    print(f"  Success rate: {successes}/200 ({successes/2:.1f}%)")
    print(f"\n  Train distribution:")
    for v in sorted(train_hist):
        bar = "#" * train_hist[v]
        mark = " *GOAL*" if v >= TRAIN_GOAL else ""
        print(f"    {v:3d} trains: {train_hist[v]:3d}x  {bar}{mark}")
    print(f"\n  Station distribution:")
    for v in sorted(station_hist):
        bar = "#" * station_hist[v]
        mark = " *GOAL*" if v >= STATION_GOAL else ""
        print(f"    {v:3d} stations: {station_hist[v]:3d}x  {bar}{mark}")

    print("\n" + "=" * 70)
    print("RECOMMENDED very_hard CONFIG")
    print("=" * 70)
    c = best_cfg
    print(f"""
  start_credits    = {c['start_credits']:,}
  start_trains     = {c['start_trains']}
  start_stations   = {c['start_stations']}
  train_buffer     = {c['train_buffer']}
  station_buffer   = {c['station_buffer']}
  train_cooldown   = {c['train_cooldown']} SD
  station_cooldown = {c['station_cooldown']} SD
  explore_target   = {c['explore_target']} stars
""")

if __name__ == "__main__":
    main()
