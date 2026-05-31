"""
Playwright script: run 10 Very Hard AI games to SD 880 with the player doing nothing.
Outputs a results table.
"""
from playwright.sync_api import sync_playwright
import json, time, os

GAME_FILE = "file:///C:/Users/jackh/Desktop/Claude/Train%20Game/index.html"
SCREENSHOT_DIR = "C:/Users/jackh/Desktop/Claude/Train Game/test_screenshots"
os.makedirs(SCREENSHOT_DIR, exist_ok=True)

def wait_for_stardate(page, target_sd=880, timeout_ms=600_000, check_interval_ms=2000):
    """Poll until stardate >= target. Returns final stardate or raises on timeout."""
    deadline = time.time() + timeout_ms / 1000
    while time.time() < deadline:
        try:
            sd = page.evaluate("typeof stardate !== 'undefined' ? stardate : -1")
            if sd >= target_sd:
                return sd
        except Exception:
            pass
        time.sleep(check_interval_ms / 1000)
    raise TimeoutError(f"Never reached SD {target_sd} within {timeout_ms/1000}s")

def extract_ai_stats(page):
    """Extract AI corp stats from game globals."""
    return page.evaluate("""
    (function() {
        if (typeof _aiCorp === 'undefined' || !_aiCorp) return null;
        const vals = {
            engine_constellation:10000,engine_galaxy:20000,engine_classJ:50000,
            engine_classR:70000,engine_N700:100000,car_passenger:5000,car_royal:12000,
            car_water_tank:8000,car_cargo:4000,car_livestock:6000,car_mail:4000,
            car_ice:9000,car_sand:5000,car_ore:8000,car_iron:10000,car_hazmat:7000,
            car_oil:9000,car_battery:11000,car_chemical:9000,car_gold:30000,
            car_diamond:45000,car_flowers:7000,car_medical:8000,caboose:3000
        };
        let trainAssetVal = 0;
        for (const ti of _aiCorp.trainIndices) {
            const t = trains[ti];
            if (t) trainAssetVal += t.cars.reduce((s,c) => s + (vals[c]||4000), 0);
        }
        // Count foundry planets
        const foundryCount = [..._aiCorp.ownedPlanetIds].filter(id => {
            const p = galaxy && galaxy.planets[id];
            return p && (p.upgrades||[]).includes('iron_foundry');
        }).length;
        return {
            name:            _aiCorp.name,
            skillLevel:      _aiCorp.skillLevel,
            credits:         Math.round(_aiCorp.credits),
            totalRevenue:    Math.round(_aiCorp.totalRevenue),
            totalCosts:      Math.round(_aiCorp.totalCosts),
            netProfit:       Math.round(_aiCorp.totalRevenue - _aiCorp.totalCosts),
            stationsBuilt:   _aiCorp.stationsBuilt,
            trainCount:      _aiCorp.trainIndices.length,
            trainAssetVal:   trainAssetVal,
            stationAssetVal: _aiCorp.stationsBuilt * 50000,
            foundries:       foundryCount,
            discoveredStars: _aiCorp.discoveredStarIds.size,
            netWorth:        Math.round(_aiCorp.credits + trainAssetVal + _aiCorp.stationsBuilt * 50000),
            stardate:        Math.round(stardate * 100) / 100,
            phase:           _aiCorp.phase,
        };
    })()
    """)

def run_one_game(page, run_num):
    """Navigate to game, start Very Hard, do nothing, wait for SD 880, return stats."""
    print(f"\n=== RUN {run_num} ===")

    # Load game
    page.goto(GAME_FILE)
    page.wait_for_timeout(2000)

    # Screenshot initial state
    page.screenshot(path=f"{SCREENSHOT_DIR}/run{run_num:02d}_01_loaded.png")
    print(f"  Game loaded. Taking initial screenshot.")

    # Confirm game globals are present
    has_globals = page.evaluate("typeof stardate !== 'undefined'")
    if not has_globals:
        print("  ERROR: game globals not found!")
        return None

    # ----------------------------------------------------------------
    # Set up the game: find and click through Very Hard new-game flow
    # We'll use JavaScript to directly manipulate the game state since
    # the UI is a canvas. We'll look for setup state variables.
    # ----------------------------------------------------------------

    # First, take a screenshot to see what's on screen
    page.screenshot(path=f"{SCREENSHOT_DIR}/run{run_num:02d}_02_before_setup.png")

    # Check what state the game is in
    state_info = page.evaluate("""
    (function() {
        return {
            activePopup: typeof activePopup !== 'undefined' ? activePopup : 'undef',
            stardate: typeof stardate !== 'undefined' ? stardate : 'undef',
            _aiDifficulty: typeof _aiDifficulty !== 'undefined' ? _aiDifficulty : 'undef',
            _gamePhase: typeof _gamePhase !== 'undefined' ? _gamePhase : 'undef',
            gameState: typeof gameState !== 'undefined' ? gameState : 'undef',
            _setupComplete: typeof _setupComplete !== 'undefined' ? _setupComplete : 'undef',
            pendingDifficulty: typeof pendingDifficulty !== 'undefined' ? pendingDifficulty : 'undef',
            keys: Object.keys(window).filter(k => k.startsWith('_ai') || k.startsWith('game')).slice(0,20),
        };
    })()
    """)
    print(f"  State: {json.dumps(state_info, indent=2)}")

    # Screenshot to see the canvas UI
    page.screenshot(path=f"{SCREENSHOT_DIR}/run{run_num:02d}_03_state.png")

    return state_info  # Return state for now, extend once we understand the UI

def main():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=["--allow-file-access-from-files", "--no-sandbox", "--disable-setuid-sandbox"])

        # Run just 1 game first to understand the UI
        page = browser.new_page(viewport={"width": 1400, "height": 900})
        result = run_one_game(page, 1)
        print(f"\nResult: {json.dumps(result, indent=2)}")

        # Keep window open for 5s so we can see it
        time.sleep(5)
        browser.close()

if __name__ == "__main__":
    main()
