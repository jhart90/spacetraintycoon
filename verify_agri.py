"""
Targeted verification: agri planet structures (orchard size + multi-struct spacing).
Finds an agri planet, force-builds all 3 structures, navigates to star view,
takes screenshots of both galaxy view, star view, and planet detail popup.
"""
import asyncio, json, os
from playwright.async_api import async_playwright

GAME = r"C:\Users\jackh\Desktop\Claude\Train Game\index.html"
OUT = r"C:\Users\jackh\Desktop\Claude\Train Game"

SAVE_JS = """
async (path, dataUrl) => {
    // Not needed — we use page.screenshot(path=...)
}
"""

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            headless=True,
            args=["--allow-file-access-from-files", "--no-sandbox"]
        )
        ctx = await browser.new_context(viewport={"width": 1400, "height": 900})
        page = await ctx.new_page()
        await page.goto(f"file:///{GAME}")
        await page.wait_for_timeout(2000)

        # Click "Easy" or start game
        try:
            await page.click("button:has-text('Easy')", timeout=3000)
        except:
            try:
                await page.click("button:has-text('New Game')", timeout=2000)
                await page.wait_for_timeout(500)
                await page.click("button:has-text('Easy')", timeout=2000)
            except:
                pass
        await page.wait_for_timeout(2500)

        # Force-inject: find an agri planet and give it all 3 structures
        result = await page.evaluate("""
        () => {
            let agriPlanet = null, agriStar = null;
            for(let s of (window.stars||[])) {
                for(let pl of (s.planets||[])) {
                    if(pl.type === 'agri') {
                        agriPlanet = pl;
                        agriStar = s;
                        break;
                    }
                }
                if(agriPlanet) break;
            }
            if(!agriPlanet) return {error: 'no agri planet found'};

            // Give it all 3 structures: granary(0), farm(1), orchard(2)
            agriPlanet.structures = [0, 1, 2];

            // Give it a station
            if(!agriPlanet.station) {
                agriPlanet.station = { owner: 'player', level: 1, name: agriPlanet.name + ' Station' };
            }

            // Make it discovered/visited so it shows properly
            agriPlanet.discovered = true;
            agriPlanet.visited = true;
            agriStar.discovered = true;
            agriStar.visited = true;

            return {
                starName: agriStar.name,
                planetName: agriPlanet.name,
                structures: agriPlanet.structures
            };
        }
        """)
        print("Agri planet setup:", json.dumps(result, indent=2))

        if 'error' in result:
            print("ERROR:", result['error'])
            # List all planets
            planets = await page.evaluate("""
            () => {
                let out = [];
                for(let s of (window.stars||[])) {
                    for(let pl of (s.planets||[])) {
                        out.push({star: s.name, planet: pl.name, type: pl.type});
                    }
                }
                return out.slice(0, 20);
            }
            """)
            print("Available planets:", json.dumps(planets, indent=2))
            await browser.close()
            return

        star_name = result['starName']

        # Navigate to the agri star in star view
        await page.evaluate(f"""
        () => {{
            let s = (window.stars||[]).find(s => s.name === {json.dumps(star_name)});
            if(!s) return;
            window.selectedStar = s;
            window.viewMode = 'star';
            if(window.camX !== undefined) {{ window.camX = s.x; window.camY = s.y; }}
        }}
        """)
        await page.wait_for_timeout(1500)

        # Screenshot 1: star view with agri planet (shows structures on planet surface)
        await page.screenshot(path=os.path.join(OUT, "agri_starview.png"))
        print("Saved agri_starview.png")

        # Screenshot 2: zoom into the planet in star view
        await page.evaluate(f"""
        () => {{
            // Try to open planet detail popup
            let agriPlanet = null, agriStar = null;
            for(let s of (window.stars||[])) {{
                for(let pl of (s.planets||[])) {{
                    if(pl.type === 'agri') {{ agriPlanet = pl; agriStar = s; break; }}
                }}
                if(agriPlanet) break;
            }}
            if(!agriPlanet) return;
            window.selectedPlanet = agriPlanet;
            // Also try calling popup opener if it exists
            if(typeof openPlanetPopup === 'function') openPlanetPopup(agriPlanet, agriStar);
            else if(typeof showPlanetDetail === 'function') showPlanetDetail(agriPlanet);
        }}
        """)
        await page.wait_for_timeout(1200)
        await page.screenshot(path=os.path.join(OUT, "agri_planet_detail.png"))
        print("Saved agri_planet_detail.png")

        # Screenshot 3: galaxy view
        await page.evaluate("() => { window.viewMode = 'galaxy'; }")
        await page.wait_for_timeout(1000)
        await page.screenshot(path=os.path.join(OUT, "agri_galaxyview.png"))
        print("Saved agri_galaxyview.png")

        await browser.close()
        print("Done.")

asyncio.run(main())
