import json
from collections import defaultdict

with open('Autosave_Pulsar_Bound (1).stt','r',encoding='utf-8') as f:
    s=json.load(f)
g=s['galaxy']
visited=set(s.get('visitedPlanetIds',[]))
discovered=set(s.get('discoveredPlanetIds',[]))
orbitCounts=s.get('planetOrbitCounts',{}) or {}
stars_by_id={st['id']:st for st in g['stars']}

BIOME_LABEL={
  'agri':'Agricultural','storm':'Storm','lava':'Volcanic','ocean':'Ocean','ice':'Ice',
  'desert':'Desert','jungle':'Jungle','rocky':'Rocky','resort':'Resort','oil':'Oil',
  'chemical':'Chemical','urban':'Urban','ancient':'Ancient',
}
SIZE_LABEL={'XS':'Extra Small','S':'Small','M':'Medium','L':'Large','XL':'Extra Large','XXL':'Massive'}

def export_planet(p):
    pid=p['id']
    star=stars_by_id.get(p['starId'],{})
    return {
      '_meta':{
        'export_schema_version':1,
        'source_save':'Autosave_Pulsar_Bound (1).stt',
        'export_stardate':s['stardate'],
        'corp':s['corpName'],
      },
      'identity':{
        'id':pid,
        'name':p['name'],
        'catchphrase':p.get('catchphrase'),
        'is_starter_world':p.get('isStarter',False),
        'is_alien_relic':p.get('isAlienRelic',False),
      },
      'location':{
        'host_star':{
          'id':star.get('id'),
          'name':star.get('name'),
          'color_class':star.get('colorName'),
          'size':star.get('size'),
          'radius':star.get('radius'),
          'x':star.get('x'),'y':star.get('y'),
        },
        'orbit_radius_su':p.get('orbitRadius'),
        'orbit_angle_rad':p.get('orbitAngle'),
        'orbit_speed_rad_per_sd':p.get('orbitSpeed'),
        'world_x':p.get('x'),'world_y':p.get('y'),
      },
      'physical':{
        'size_class':p.get('size'),
        'size_label':SIZE_LABEL.get(p.get('size'),p.get('size')),
        'radius_su':p.get('radius'),
        'biome_id':p.get('type',{}).get('id'),
        'biome_label':BIOME_LABEL.get(p.get('type',{}).get('id'),p.get('type',{}).get('id')),
        'biome_seed':p.get('biomeSeed'),
        'cloud_angle':p.get('cloudAngle'),
      },
      'geology':{
        'has_gold':p.get('hasGold',False),
        'gold_revealed':p.get('goldRevealed',False),
        'gold_patch':p.get('goldPatch'),
        'has_diamond':p.get('hasDiamond',False),
        'diamond_revealed':p.get('diamondRevealed',False),
        'diamond_patch':p.get('diamondPatch'),
        'ring':p.get('ring'),
        'moons':p.get('moons',[]),
      },
      'population':{
        'current':p.get('population'),
        'base_at_generation':p.get('populationBase'),
        'growth_multiplier': (p.get('population',0)/p.get('populationBase',1)) if p.get('populationBase') else None,
      },
      'economy':{
        'supply':p.get('supply',{}),
        'demand':p.get('demand',{}),
        'unlocks':{
          'flowers':p.get('flowerUnlocked',False),
          'flowers_origin':p.get('isFlowersOrigin',False),
          'fruit':p.get('fruitUnlocked',False),
          'grain':p.get('grainUnlocked',False),
          'livestock':p.get('livestockUnlocked',False),
        },
      },
      'development':{
        'level':p.get('devLevel',0),
        'base_level_at_generation':p.get('devLevelBase',0),
        'delivery_log':p.get('devLog',[]),
        'passenger_delivery_log':p.get('passengerDeliveries',[]),
        'iron_delivered_lifetime':p.get('ironDelivered',0),
        'steel_delivered_lifetime':p.get('steelDelivered',0),
        'glass_delivered_lifetime':p.get('glassDelivered',0),
      },
      'player_interaction':{
        'has_station':p.get('hasStation',False),
        'has_large_station':p.get('hasLargeStation',False),
        'has_terminal':p.get('hasTerminal',False),
        'station_built_by_player':p.get('playerBuiltStation',False),
        'station_orbit_angle':p.get('stationAngle'),
        'station_orbit_speed':p.get('stationSpeed'),
        'upgrades_present':p.get('upgrades',[]),
        'upgrades_built_by_player':p.get('playerBuiltUpgrades',[]),
        'upgrade_data':p.get('upgradeData',{}),
        'structure_angles':{
          'agri_struct':p.get('agriStructAngle'),
          'bakery':p.get('bakeryAngle'),
          'blast_furnace':p.get('blastFurnaceAngle'),
          'foundry':p.get('foundryAngle'),
          'glassworks':p.get('glassworksAngle'),
        },
      },
      'discovery':{
        'discovered':pid in discovered,
        'visited':pid in visited,
        'orbit_count_by_player_trains':orbitCounts.get(str(pid),0),
      },
    }

pool=[p for p in g['planets'] if (p.get('hasStation') and p.get('playerBuiltStation')) or p['id'] in visited]
player_st = sorted([p for p in pool if p.get('playerBuiltStation')], key=lambda x:-x.get('devLevel',0))
others    = [p for p in pool if not p.get('playerBuiltStation')]
by_biome=defaultdict(list)
for p in others: by_biome[p['type']['id']].append(p)
for k in by_biome: by_biome[k].sort(key=lambda x:-x.get('devLevel',0))

selected=list(player_st)
seen={p['id'] for p in selected}
biomes=list(by_biome.keys())
i=0
while len(selected)<20 and any(by_biome[b] for b in biomes):
    b=biomes[i%len(biomes)]
    if by_biome[b]:
        cand=by_biome[b].pop(0)
        if cand['id'] not in seen:
            selected.append(cand); seen.add(cand['id'])
    i+=1
    if i>500: break

selected=selected[:20]
export=[export_planet(p) for p in selected]

print('Exporting',len(export),'planets:')
for e in export:
    pi=e['identity']; ph=e['physical']; dv=e['development']
    sup=','.join(e['economy']['supply'].keys()) or '-'
    dem=','.join(e['economy']['demand'].keys()) or '-'
    flag='P' if e['player_interaction']['station_built_by_player'] else ('A' if e['player_interaction']['has_station'] else '.')
    print('  #{:>4} {:<22} {:<14} {:<3} dev={:<2} pop={:>12,}  station={}  sup=[{}] dem=[{}]'.format(
      pi['id'], pi['name'][:22], ph['biome_label'], ph['size_class'], dv['level'], e['population']['current'], flag, sup, dem))

with open('_planet_export_sample.json','w',encoding='utf-8') as f:
    json.dump(export,f,indent=2)
print()
print('Wrote _planet_export_sample.json, size:', len(json.dumps(export)),'bytes')
