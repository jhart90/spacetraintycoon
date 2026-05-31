import random
import statistics


def simulate(params, seed=42):
    random.seed(seed)
    credits = params['start_credits']
    trains = params['start_trains']
    stations = params['start_stations']
    last_train = -999.0
    last_station = -999.0
    discovered_stars = 1  # home star known at start
    visited_planets = params.get('home_star_planets', 5)
    exploring = 0  # count of trains currently on exploration trips
    explore_events = []  # list of (return_sd, new_planets_count)

    duration = 51.0  # SD 829 to SD 880
    dt = 0.05

    for i in range(int(duration / dt)):
        sd = i * dt

        # Process exploration returns
        new_explores = []
        for (ret_sd, n_planets) in explore_events:
            if sd >= ret_sd:
                exploring -= 1
                discovered_stars += 1
                visited_planets += n_planets
            else:
                new_explores.append((ret_sd, n_planets))
        explore_events = new_explores

        # Revenue: routing trains earn, explorers earn 0
        routing_trains = max(0, trains - exploring)
        net_mult = 1.0 + min(stations, 30) * 0.04
        base_rev = params['rev_per_train'] * (0.7 + 0.6 * random.random())
        credits += routing_trains * base_rev * net_mult * dt

        # P0: explore if below target AND exploration trains below limit
        explore_target = params.get('explore_target', 10)
        max_explorers = params.get('max_explorers', 1)
        if (discovered_stars < explore_target and
                exploring < max_explorers and
                trains > exploring + 1):  # keep at least 1 train on routes
            trip_sd = random.uniform(3.0, 6.0)  # round trip duration
            explore_events.append((sd + trip_sd, random.randint(3, 6)))
            exploring += 1
            continue

        unstationed = max(0, visited_planets - stations)

        # P1.5: trains-first (very_hard only, if enabled)
        if params.get('trains_first', False):
            t_cost = params['train_cost']
            t_thresh = t_cost * params.get('train_buf', 1.1)
            t_cool = params.get('train_cool', 0.4)
            if credits >= t_thresh and (sd - last_train) >= t_cool:
                credits -= t_cost
                trains += 1
                last_train = sd
                continue

        # P2: build station
        if unstationed > 0:
            s_cost = params['station_cost']
            s_thresh = s_cost * params.get('sta_buf', 1.5)
            s_cool = params.get('sta_cool', 0.5)
            if credits >= s_thresh and (sd - last_station) >= s_cool:
                credits -= s_cost
                stations += 1
                last_station = sd
                continue

        # P3: buy train (standard / fallback)
        if not params.get('trains_first', False):
            t_cost = params['train_cost']
            t_thresh = t_cost * params.get('train_buf', 1.8)
            t_cool = params.get('train_cool', 1.0)
            if credits >= t_thresh and (sd - last_station) >= t_cool:
                credits -= t_cost
                trains += 1
                last_train = sd

    return trains, stations


def run_test(params, n=50):
    results = [simulate(params, seed=i) for i in range(n)]
    both = sum(1 for tr, st in results if tr >= 25 and st >= 25)
    avg_tr = statistics.mean(tr for tr, st in results)
    avg_st = statistics.mean(st for tr, st in results)
    min_tr = min(tr for tr, st in results)
    min_st = min(st for tr, st in results)
    return {
        'success': both,
        'n': n,
        'rate': both / n,
        'avg_tr': avg_tr,
        'avg_st': avg_st,
        'min_tr': min_tr,
        'min_st': min_st,
    }


def print_result(label, res):
    print(f"  {label}")
    print(f"    Success: {res['success']}/{res['n']} ({res['rate']*100:.1f}%)")
    print(f"    Avg trains: {res['avg_tr']:.1f}  |  Min trains: {res['min_tr']}")
    print(f"    Avg stations: {res['avg_st']:.1f}  |  Min stations: {res['min_st']}")
    print()


COMMON = dict(
    station_cost=50_000,
    train_cost=63_000,
    home_star_planets=5,
)

baseline = dict(
    **COMMON,
    start_credits=220_000,
    start_trains=1,
    start_stations=2,
    train_buf=1.8,
    sta_buf=1.5,
    train_cool=1.0,
    sta_cool=0.5,
    explore_target=10,
    max_explorers=2,
    trains_first=False,
    rev_per_train=15_000,
)

iter1_base = dict(
    **COMMON,
    start_credits=500_000,
    start_trains=3,
    start_stations=3,
    train_buf=1.1,
    sta_buf=1.1,
    train_cool=0.4,
    sta_cool=0.15,
    explore_target=15,
    max_explorers=1,
    trains_first=True,
    rev_per_train=15_000,
)

print("=" * 60)
print("VERY HARD AI PARAMETER SIMULATION")
print("Success criterion: trains >= 25 AND stations >= 25 at SD 880")
print("=" * 60)
print()

# --- Tests 1-4 ---
print("--- Named Configurations ---")
print()

res_baseline = run_test(baseline)
print_result("1. Baseline (current VH, broken)", res_baseline)

res_iter1 = run_test(iter1_base)
print_result("2. Iter 1 (proposed, 15K rev)", res_iter1)

res_pess = run_test({**iter1_base, 'rev_per_train': 10_000})
print_result("3. Iter 1 pessimistic (10K rev)", res_pess)

res_opt = run_test({**iter1_base, 'rev_per_train': 20_000})
print_result("4. Iter 1 optimistic (20K rev)", res_opt)

# --- Test 5: parameter sweep ---
print("--- Parameter Sensitivity Sweep (one at a time from Iter 1 base) ---")
print()

sweep_params = {
    'start_credits':  [200_000, 300_000, 400_000, 500_000, 600_000, 700_000],
    'start_trains':   [1, 2, 3, 4, 5],
    'start_stations': [1, 2, 3, 4, 5],
    'train_buf':      [1.0, 1.1, 1.2, 1.5, 1.8],
    'sta_buf':        [1.0, 1.1, 1.2, 1.5, 1.8],
    'train_cool':     [0.2, 0.4, 0.6, 0.8, 1.0],
    'sta_cool':       [0.05, 0.15, 0.3, 0.5, 0.8],
    'max_explorers':  [0, 1, 2, 3],
    'explore_target': [5, 10, 15, 20, 25],
}

sensitivity = {}

for param, values in sweep_params.items():
    rates = []
    print(f"  Sweeping {param}:")
    for v in values:
        cfg = {**iter1_base, param: v}
        r = run_test(cfg, n=50)
        rates.append(r['rate'])
        print(f"    {param}={v:>10} -> {r['rate']*100:5.1f}%  (avg tr={r['avg_tr']:.1f}, avg st={r['avg_st']:.1f})")
    spread = max(rates) - min(rates)
    sensitivity[param] = spread
    print(f"    Sensitivity (max-min rate): {spread*100:.1f}pp")
    print()

print("  Sensitivity ranking (most sensitive first):")
for param, spread in sorted(sensitivity.items(), key=lambda x: -x[1]):
    print(f"    {param:<20} {spread*100:.1f}pp")
print()

# --- Test 6: Minimum start_credits for 90% success ---
print("--- Minimum start_credits for >= 90% success (15K rev, Iter 1 params) ---")
print()

target_rate = 0.90
found_min = None
for sc in range(50_000, 800_001, 25_000):
    cfg = {**iter1_base, 'start_credits': sc}
    r = run_test(cfg, n=100)
    print(f"  start_credits={sc:>8,}  -> {r['rate']*100:5.1f}%")
    if r['rate'] >= target_rate and found_min is None:
        found_min = sc

if found_min:
    print(f"\n  MINIMUM start_credits for 90% success: {found_min:,}")
else:
    print("\n  Did not find 90% threshold up to 800,000")
print()

# --- Summary ---
print("=" * 60)
print("SUMMARY")
print("=" * 60)
print()
print("Named configs success rates:")
print(f"  Baseline (broken):        {res_baseline['rate']*100:.1f}%")
print(f"  Iter 1 (15K rev):         {res_iter1['rate']*100:.1f}%")
print(f"  Iter 1 pessimistic (10K): {res_pess['rate']*100:.1f}%")
print(f"  Iter 1 optimistic (20K):  {res_opt['rate']*100:.1f}%")
print()
if found_min:
    print(f"Minimum start_credits for >=90%: {found_min:,}")
print()
print("Top 3 most sensitive parameters:")
for param, spread in sorted(sensitivity.items(), key=lambda x: -x[1])[:3]:
    print(f"  {param:<20} {spread*100:.1f}pp swing")
