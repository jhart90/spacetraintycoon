---
name: ai-snapshot
description: >
  Run a single headless Very Hard AI simulation and capture a rich diagnostic
  snapshot at a specific stardate offset from game start (+10 SD, +20 SD, +30 SD,
  or any N). Use this skill whenever the user wants to test how the AI is performing
  at an early/mid/late point in the game, diagnose why the AI isn't buying enough
  trains or stations, check AI credit flow and decision blockers, or benchmark AI
  net worth at a checkpoint. Triggers on phrases like "run a snapshot", "how's the
  AI at +10SD", "diagnose the AI", "why isn't the AI buying trains", "test AI at
  30 SD", "AI checkpoint", "AI performance at early game".
---

# AI Snapshot Skill

Run `test_ai_snapshot.py` to simulate one Very Hard AI game to a target stardate
and print a rich diagnostic breakdown.

## Usage

```
cd "C:\Users\jackh\Desktop\Claude\Train Game"
python test_ai_snapshot.py [--offset N] [--runs R]
```

- `--offset N`  — how many SDs past game start to simulate (default: 10)
- `--runs R`    — how many independent runs to average (default: 1)

Examples:
```
python test_ai_snapshot.py --offset 10
python test_ai_snapshot.py --offset 20 --runs 3
python test_ai_snapshot.py --offset 30
```

## What It Reports

Each run prints a diagnostic block covering:

1. **Fleet & Financials** — train count (free starters vs purchased), station count,
   net worth, credits, revenue, costs, and revenue-per-SD rate.

2. **Decision Blockers** — whether the AI can currently afford a new train
   (need credits ≥ 69,300), whether the 0.4-SD train cooldown has cleared,
   whether it can build a station (need ≥ 55,000), exploration progress vs the
   target of 15 discovered stars.

3. **Train Details** — for each AI train: route phase (orbit/transit/blocked/no_route),
   current cargo, idle timer, asset value, and route stops.

4. **Action Queue** — pending queued actions the AI is about to execute.

## How to Interpret Results

**Low train count at +10 SD?**
- Check `credits_vs_threshold`: if negative, the AI can't afford more trains.
- Check `stationsBuilt` vs `purchasedTrains`: if stations >> trains by more than
  ~2×, the 0.15-SD station cooldown is draining capital between the 0.4-SD train
  purchases. Each 0.4-SD window can fit ~2 station builds, costing 100k of the
  63k needed for a train.
- Check `activeExplorers` + `discoveredStars`: if still exploring aggressively
  (< 15 stars), exploration route assignments may be consuming decision ticks
  without buying trains — though this only blocks one tick per explorer trip.

**Revenue too low?**
- `revenuePerSd` < 5,000 at +20 SD suggests trains are stuck in orbit, exploring,
  or on short/low-demand routes with no viable stations to service.

**All trains blocked?**
- `routePhase: blocked` on most trains means fog or star-range issues are
  preventing route execution. Check `discoveredStars` — if low, trains can't
  find valid routes.

## Key Game Constants (for reference)

| Constant | Value |
|---|---|
| VH starting trains | 3 free (at init) |
| VH starting credits | 500,000 |
| VH starting stations | 3 free |
| New train cost (VH) | 63,000 (galaxy engine + 5 cars + caboose) |
| Train buy threshold (1.1×) | 69,300 |
| Train buy cooldown | 0.4 SD |
| Station cost | 50,000 |
| Station buy threshold (1.1×) | 55,000 |
| Station cooldown (VH) | 0.15 SD |
| AI decision tick interval | 1.8 game-minutes |
| Exploration target (VH) | 15 discovered stars |
| Phase → late threshold | age > 8 SD (≈ SD 837) |
