# Cogwild Frontier — module contracts (for parallel implementation)

This file is the interface agreement between the modules built in parallel. The integration owner
(main agent) writes the simulation, world generation, game view and HUD against these APIs.
Keep names, signatures and schemas exactly as written; if a contract is impossible, implement the
closest version and report the deviation.

## 0. Project facts

- Root: the repository root, Godot project in `game/` (run `godot --path game`).
- Godot **4.7.2**, GDScript only, **static typing** (`var hp: int`, return types), tabs for indent.
- Renderer: **Compatibility** (OpenGL 3.3 / WebGL 2, same as the Web build; target GPU: Intel Iris Xe and phones). No physics bodies are used for units/props. No instance uniforms (the WebGL2 buffer is tiny): per-object shader values are plain uniforms on a private material copy.
- Autoloads: `Settings` (player settings), `DB` (data registry), `App` (input, scene changes, UI scale), `Sfx` (audio), `Loc` (localization), `Quality` (graphics presets).
- Shared, read-only for sub-modules (ask the integrator in your report if a change is needed):
  `project.godot`, `src/core/*`, `src/visual/mesh_kit.gd`, `src/visual/look_dev.gd`,
  `src/visual/shaders/*`, `tests/test_case.gd`, `tests/run_tests.*`.
- Tests: `tests/test_<name>.gd` extending `TestCase` (see `tests/test_case.gd`), run with
  `godot --headless --path game res://tests/run_tests.tscn -- --filter=<name>`.
- After adding scripts with `class_name` or new assets run `godot --headless --path game --import`.
  Several agents share the project; if a class is "not found", re-run the import once.
- Windowed screenshots: `python3 ~/.omp/agent/skills/game-production/scripts/godot_probe.py game --scene res://tests/<scene>.tscn --shot 10 --frames 12 --resolution 1600x900 --out build/probe/<name>`.
  The machine has ~1 GB free RAM: run one Godot instance at a time (`flock /tmp/cogwild-godot.lock ...`), prefer headless, keep windowed runs short.
- Never run destructive git commands. Do not edit files owned by another module.

## 1. World conventions & art direction

- 1 unit = 1 m, +Y up, **model front = +Z**. One map tile = 1 × 1 m.
- Camera (LookDev): orthographic, pitch −30° (matches the painted 2:1 isometric art), yaw 45° by default with four 90°-step orientations. Screen-relative panning and picking use the live camera basis; building cards mirror at ±90° and compute per-pixel depth for the active yaw.
  Default zoom `size = 28` (≈38 px per metre at 1080p), close 12, far 64.
- Lighting: `LookDev.setup_preview(parent, target, size)` gives the in-game sun/environment/camera.
  Always judge art with it.
- Style: cozy low-poly diorama, flat-shaded vertex colours, chunky readable silhouettes, warm
  light; fantasy + light steampunk industry (brass, riveted plates, gears, pipes, glowing lamps).
  Visual reference: `docs/reference/visual_reference.png` (match mood, palette, density — not pixels).
- Readability at gameplay zoom: characters ≈ 1.1–1.3 m tall, **chibi proportions (head ≈ 35 %
  of height)**, no detail thinner than ~0.06 m, strong colour blocks. Robots/drones glow eyes.
- Faction styles and palettes (hex, sRGB):

| style | used by | primary | secondary | accents |
|---|---|---|---|---|
| `frontier` | player | blue `#3a5da8` | cream `#e9dcc0` | gold `#d9b04c`, wood `#8a5a34`, stone `#9a958c`, roof blue `#3f5fa0` |
| `bandit` | hostile people | red `#b33a2e` | dark leather `#4a3426` | rust `#8c4a2a`, patched cloth `#7a6a55` |
| `ancient` | rogue machines | bronze `#a07a4a` | slate `#5b6470` | glow orange-red `#ff6a2a` |
| `merchant` | traders | green `#4f8a4b` | cream `#efe3c2` | gold `#d9b04c` |
| `neutral` | wanderers | brown `#8a6a4a` | grey `#8d8f86` | teal `#3f8f8a` |

  `faction_color` in DNA overrides the primary for trims/banners (player may pick their colour).

## 2. MeshKit and the shared shader (already implemented)

`src/visual/mesh_kit.gd` (`class_name MeshKit`): build geometry with `box`, `frustum`, `cylinder`,
`cone`, `ellipsoid`, `sphere`, `pyramid`, `gable`, `tube`, `torus`, `plate` (XY outline extruded
along Z), `prism_xz` (XZ outline extruded up), raw `tri`/`quad`, transform stack
`push`/`push_trs`/`pop`, `append(other_kit)`, then `build()` → `ArrayMesh` (one surface, shared
material, one draw call). Faces orient themselves; mirrored transforms are safe.
Colours are sRGB; `MeshKit.glow(color, strength)` marks emissive parts (vertex alpha). Emission is
boosted at night by the global `night_amount`. Fog of war is applied by the shader automatically.
`MeshKit.multimesh_material()` is the MultiMesh variant (tint via `INSTANCE_CUSTOM`).
Cache built meshes (static Dictionary keyed by id/variant/DNA hash); never rebuild per frame.

## 3. Appearance DNA (plain JSON-safe Dictionaries; colours are "#rrggbb" strings)

Same DNA ⇒ identical look (deterministic, no global RNG). Unknown/missing keys must fall back to
sensible defaults (never crash).

### 3.1 character
```
kind: "character", seed: int,
race: <playable race id from data/races, including "android">,
gender: "female" | "male" | "nonbinary",
body_type: "slim" | "average" | "stocky" | "tall",  height: float 0.9..1.1 (scale),
skin: hex, face: "round" | "long" | "square", eye_color: hex,
hair: "short" | "long" | "ponytail" | "bun" | "mohawk" | "bald" | "braids" | "wild",
hair_color: hex, facial_hair: "none" | "beard" | "mustache",
outfit: "tunic" | "robe" | "coat" | "overalls" | "leathers" | "dress" | "rags",
outfit_color: hex, outfit_accent: hex,
armor: "none" | "leather" | "chain" | "plate" | "coat",
headgear: "none" | "hood" | "cap" | "helmet" | "goggles" | "wide_hat" | "bandana" | "circlet",
weapon: "none" | "sword" | "axe" | "spear" | "bow" | "crossbow" | "hammer" | "mace" | "dagger" |
        "staff" | "rifle" | "pistol" | "wrench" | "pickaxe" | "hoe" | "torch",
offhand: "none" | "shield" | "lantern" | "book" | "buckler",
accessory: "none" | "scarf" | "backpack" | "cape" | "satchel" | "pauldron",
scar: "none" | "cheek" | "eye",
faction_style: "frontier" | "bandit" | "ancient" | "merchant" | "neutral", faction_color: hex
art_variant: int (optional, zero-based painted look; retained through equipment changes),
shell_color, joint_color, faceplate_color, brass_color: hex (android only)
```
Race features: sylvan = pointed ears, slimmer/taller; stoutkin = short and stocky, beards common;
vulpin = fox ears + bushy tail, fur-toned skin; human = baseline.
Androids are self-aware mechanical citizens with ivory shell armour, dark articulated joints,
amber eyes and brass accents. They remain `kind: "character"` and use the ordinary resident,
squad and diplomacy paths; they are not the hostile ancient machines in §3.2.

### 3.2 robot (ground machines)
```
kind: "robot", seed, archetype: "work_bot" | "walker" | "sentry" | "turret" | "hauler",
chassis: "boxy" | "round" | "tall" | "barrel",
legs: "biped" | "quad" | "treads" | "wheels" | "none",
armor: "light" | "medium" | "heavy",
sensor: "mono_eye" | "visor" | "twin_lens" | "dome",
weapon: "none" | "cannon" | "gatling" | "claw" | "lance" | "drill",
utility_module: "none" | "cargo_rack" | "crane_arm" | "antenna" | "smokestack" | "tool_arm",
paint: hex, paint_secondary: hex, eye_color: hex, wear: 0..1, scale: float,
faction_style, faction_color
```
Sizes: work_bot ≈ 0.9–1.1 m, hauler ≈ 1.2 m, walker ≈ 2.0–2.4 m (bipedal mech like the brass
mech in the reference), sentry ≈ 1.4 m, turret ≈ 1.6 m (static pedestal).

### 3.3 drone
```
kind: "drone", seed, archetype: "scout_drone" | "repair_drone" | "war_drone",
frame: "quad" | "disc" | "twin" | "orb", rotors: 2 | 4,
sensor: "mono_eye" | "twin_lens" | "dome", weapon: "none" | "blaster" | "repair_beam",
paint: hex, eye_color: hex, wear: 0..1, faction_style, faction_color
```
≈ 0.5–0.7 m wide; flies ~3.5 m above ground (the view handles altitude).

### 3.4 airship
```
kind: "airship", seed, archetype: "cargo_airship" | "trader_airship" | "raider_airship" | "explorer_airship",
hull: "skiff" | "barge" | "clipper", balloon: "cigar" | "twin" | "round" | "segmented",
balloon_pattern: "stripes" | "plain" | "panels" | "rings",
engine: "prop_pair" | "prop_rear" | "turbine", wing: "none" | "fins" | "sails" | "stubby",
gondola: "cabin" | "open_deck" | "tower", weapon: "none" | "cannons" | "harpoon",
cargo_module: "none" | "crates" | "hanging_container",
paint: hex, balloon_color: hex, balloon_color2: hex, banner: hex, wear: 0..1, scale: float,
faction_style, faction_color
```
≈ 9–12 m long; flies ~9 m above ground.

### 3.5 item (`item.appearance`, produced by ItemGen)
```
kind: "item", seed, shape: <icon shape id, §6.3>, primary: hex, secondary: hex, accent: hex,
glow: 0..1, variant: 0..3, engraved: bool, worn: 0..1
```

## 4. VisualUnits module (characters, machines, portraits)

Files: `src/visual/appearance_gen.gd`, `src/visual/unit_visual_factory.gd`,
`src/visual/unit_visual.gd`, `src/visual/portrait_renderer.gd`, helpers in `src/visual/units/`,
data `data/generation/appearance.json` (palettes/option weights per race, role, style),
`tests/gallery_units.tscn/.gd`, `tests/test_appearance.gd`.

```gdscript
class_name AppearanceGen
static func character(rng: RandomNumberGenerator, race: String, role: String, faction_style: String, faction_color: Color, gender: String = "") -> Dictionary
static func robot(rng: RandomNumberGenerator, archetype: String, faction_style: String, faction_color: Color) -> Dictionary
static func drone(rng: RandomNumberGenerator, archetype: String, faction_style: String, faction_color: Color) -> Dictionary
static func airship(rng: RandomNumberGenerator, archetype: String, faction_style: String, faction_color: Color) -> Dictionary
```
Role ids that may be passed (unknown → neutral default): playable `settler`, `mercenary`,
`commander`, `merchant`, `engineer`, `explorer`, `scholar`, `researcher`; NPC `farmer`,
`woodcutter`, `miner`, `builder`, `guard`, `archer`, `hunter`, `medic`, `cook`, `tinkerer`,
`trader`, `bandit`, `bandit_archer`, `bandit_captain`. The role picks outfit/headgear/accessory and
a default weapon/offhand (the sim later overwrites `weapon`/`offhand`/`armor` from equipped items).

```gdscript
class_name UnitVisualFactory
static func create(dna: Dictionary) -> UnitVisual   # any kind: character/robot/drone/airship

class_name UnitVisual extends Node3D
enum Anim { IDLE, WALK, WORK, DOWNED, DEAD }
var kind: String                                   # dna.kind
func set_anim(anim: int) -> void                   # looped state; flying kinds hover/fly
func set_move_speed(speed: float) -> void          # m/s, drives step / bob frequency
func trigger(action: StringName) -> void           # one-shot: &"attack_melee", &"attack_ranged",
                                                   # &"hit", &"work_chop", &"work_mine", &"work_build",
                                                   # &"work_farm", &"cheer", &"levelup"
func set_held(item_visual: String) -> void         # temporary held tool/weapon ("axe", "pickaxe",
                                                   # "hammer", "hoe", ... "" = DNA default)
func set_carry(resource: String) -> void           # "" | "wood" | "stone" | "ore" | "metal" | "food" | "gold" | "crate"
func get_visual_height() -> float                  # top of model (HP bar placement)
func get_head_position() -> Vector3                # local, portrait framing
func get_muzzle_position() -> Vector3              # local, projectile spawn
```
- Origin: ground units at feet centre; drones/airships at the craft's centre (the view sets the
  flying altitude and draws a ground shadow). Face +Z. The view rotates the root for facing and
  owns selection rings and HP bars — do not add those.
- Draw-call budget: ≤ 4 MeshInstance3D per character/robot (e.g. body, leg L, leg R, held item),
  ≤ 3 per drone/airship (body + spinning rotors/props). Merge everything else with MeshKit. Small
  moving parts should not cast shadows. Cache meshes by DNA content.
- Animation is procedural (node transforms in `_process`): walk step/bob, work swings synced to
  work triggers, melee lunge, recoil for ranged, hit flash/knock, downed = lying, dead = fall +
  sink. Drones hover-bob and spin rotors; airships bob gently and spin props.
- Must look good at gameplay zoom (size 28) *and* in close portraits.

```gdscript
class_name PortraitRenderer extends Node
func get_portrait(key: String, dna: Dictionary, size: int = 128) -> Texture2D
## Returns immediately an ImageTexture (initially transparent) that is filled asynchronously
## (own SubViewport + own World3D, one render per frame, cached by key). Head-and-shoulders framing
## for characters, full body for machines. Transparent background.
func invalidate(key: String) -> void
```

## 5. VisualWorld module (buildings, props, VFX, icons)

Files: `src/visual/building_visuals.gd`, `src/visual/building_visual.gd`,
`src/visual/prop_meshes.gd`, `src/visual/vfx.gd`, `src/visual/icons.gd`, helpers in
`src/visual/world/`, `assets/icons/*.svg`, `tests/gallery_world.tscn/.gd`,
`tests/test_world_visuals.gd`.

```gdscript
class_name BuildingVisuals
static func create(type_id: String, style: String, variant_seed: int, level: int = 1) -> BuildingVisual

class_name BuildingVisual extends Node3D
var footprint: Vector2i                  # tiles (x, z); the model fits inside, origin = footprint centre on the ground
func set_construction(progress: float) -> void   # 0..1: foundation → scaffold → frame → finished (1.0)
func set_active(active: bool) -> void    # working: chimney smoke, furnace glow, windmill blades turn, sparks
func get_top_height() -> float
func get_anchor(name: StringName) -> Vector3   # local points: &"door" (front, +Z side), &"mooring" (sky_dock/trade_mast: airship park point), &"banner"
```
Building ids and footprints (x × z tiles):

| id | size | notes |
|---|---|---|
| `hearth` | 4×4 | town hall + central hearth/bonfire, stone base, timber, blue roof, crest banner; level 1–3 grows (2: side wing/tower, 3: bell tower + more banners) |
| `house` | 3×3 | cottage, blue roof, chimney, glowing windows |
| `storehouse` | 3×4 | barn/warehouse, crates & barrels, open front |
| `workshop` | 4×4 | robot workshop: gears, crane arm, pipes, glowing furnace |
| `smelter` | 3×3 | stone furnace + tall chimney, glow when active |
| `windmill` | 3×3 | ~7 m tower, 4 sail blades on a separate spinning node (energy) |
| `sky_dock` | 4×4 | wooden scaffold tower with mooring mast & lanterns; `mooring` anchor ~8 m up |
| `watchtower` | 2×2 | ~6 m defensive tower with banner and small ballista |
| `wall` | 1×1 | 1.8 m stone wall block with crenellation (reads well in lines) |
| `outpost` | 3×3 | frontier outpost: stockade ring, tent, crates, banner |
| `bandit_tent` | 2×2 | red/brown patched tent |
| `bandit_hut` | 3×3 | ramshackle hut, red cloth, skull-less (keep cozy) |
| `bandit_tower` | 2×2 | lookout tower, red banner |
| `palisade` | 1×1 | sharpened stake wall segment |
| `campfire` | 1×1 | stone ring + glowing fire |
| `machine_spire` | 2×2 | ancient pylon with glowing core |
| `machine_block` | 2×2 | ruined machine block with glow lines |
| `machine_foundry` | 4×4 | enemy machine factory, smokestacks, orange glow |
| `trade_hall` | 4×4 | market hall with striped awnings |
| `trade_stall` | 2×2 | stall with goods |
| `trade_mast` | 2×2 | mooring mast for trader airships (`mooring` anchor) |
| `wanderer_tent` | 2×2 | neutral camp tent |
| `ruin_arch` | 3×1 | broken stone arch, moss |
| `ruin_pillar` | 1×1 | broken pillar |
| `ruin_wall` | 3×1 | broken wall |
| `ruin_statue` | 2×2 | weathered statue |
| `ruin_vault` | 3×3 | sealed vault door with faint glow (loot site) |
| `wreck_airship` | 6×3 | crashed airship: torn balloon, broken hull |

`style` is one of the faction styles (only frontier buildings need restyling support; others
have a fixed style). Construction visuals apply to every id.

```gdscript
class_name PropMeshes
static func get_mesh(prop_id: String, variant: int = 0) -> ArrayMesh   # cached, one surface, MeshKit material
static func variant_count(prop_id: String) -> int
```
Props (origin at the base centre; sizes approximate; must tile within 1×1 m unless noted):
`tree_pine` (3 variants, 3.5–5 m), `tree_oak` (3, 3–4 m, round canopy), `tree_birch` (2),
`tree_dead` (2), `stump`, `bush` (2), `berry_bush` (2, red berries), `berry_bush_empty`,
`rock_small` (3), `rock_large` (3, ~1.4 m, fills its tile), `ore_iron` (2, rock with rusty-orange
veins), `ore_crystal` (2, cyan glowing aether crystals), `grass_tuft` (3), `flowers` (3),
`reeds` (2), `crop_wheat_0..3` and `crop_veg_0..3` (growth stages, stage 3 = ripe golden wheat /
full cabbages; one mesh covers a 1×1 tile), `tilled_soil` (1×1 dark furrowed soil, 0.08 m),
`bridge_plank` (1×1 deck, planks run along X, low rails on ±Z edges), `fence` (1 m segment along X),
`crate`, `barrel`, `lantern_post` (glow), `log_pile`, `stone_pile`, `ore_pile`, `loot_bag`,
`loot_chest`, `sign_post`, `banner_pole` (neutral cloth, tint via instance), projectiles
`arrow`, `bolt`, `bullet`, `cannon_shell`, `blaster_bolt` (glow) — projectiles point along +Z.
Trees and props receive per-instance tint and scale from the world view (MultiMesh), so keep
colours natural and let the tint vary them.

```gdscript
class_name Vfx
static func spawn(parent: Node, kind: StringName, pos: Vector3, color: Color = Color.WHITE, dir: Vector3 = Vector3.ZERO) -> void
```
Kinds: `hit_spark`, `dust_puff`, `chop_chips`, `rock_chips`, `smoke_puff`, `level_up`,
`loot_beam` (vertical beam in `color`, ~4 s, for rare+ loot), `heal`, `discover_ping`,
`build_dust`, `muzzle_flash`, `explosion_small`, `death_poof`. One-shot, self-freeing, cheap
(CPUParticles3D or pooled meshes, ≤ ~40 particles), readable at gameplay zoom.

```gdscript
class_name Icons
static func get_icon(id: String) -> Texture2D          # res://assets/icons/<id>.svg (cached); missing id -> a visible fallback + push_warning once
static func item_icon(item: Dictionary, size: int = 64) -> Texture2D   # procedural from item.appearance (+ quality frame)
static func quality_color(quality: String) -> Color     # reads DB "items/qualities" color, fallback grey
```
Icon style: 64×64 viewBox SVG, cream/gold glyph (`#f1e3bd` / `#d9b04c`) with dark outline
(`#1a1f2b`), transparent background, consistent stroke, readable at 24–32 px.
Required ids:
- resources: `res_wood res_stone res_metal res_ore res_gold res_food res_energy res_pop`
- commands: `cmd_move cmd_attack cmd_defend cmd_explore cmd_build cmd_gather cmd_patrol cmd_auto cmd_retreat cmd_escort cmd_stop cmd_farm cmd_trade cmd_cancel`
- ui: `ui_home ui_buildings ui_people ui_target ui_search ui_pause ui_play ui_fast ui_faster ui_sun ui_moon ui_save ui_load ui_menu ui_close ui_squad ui_bell ui_crest ui_skull ui_star ui_heart ui_bolt ui_chest ui_scroll ui_gear`
- unit classes: `class_shield class_spear class_archer class_scout class_engineer class_commander class_worker class_robot class_drone class_airship class_medic class_merchant`
- zones: `zone_logging zone_mining zone_forage zone_farm zone_clear`
- buildings: `bld_hearth bld_house bld_storehouse bld_workshop bld_smelter bld_windmill bld_sky_dock bld_watchtower bld_wall bld_outpost bld_farm_plot bld_road`
- points of interest: `poi_ruins poi_bandit poi_machine poi_trade poi_wanderer poi_wreck poi_crystal poi_ore`

Item icon shapes (`item.appearance.shape`): `sword dagger axe spear bow crossbow hammer mace staff
rifle pistol wrench pickaxe shield vest coat plate helmet boots gloves scope lantern compass
goggles gear servo sensor core plating propeller envelope engine orb idol relic amulet ring tonic
ration repair_kit shard ingot timber pelt book map`. Use `primary` for the main material,
`secondary` for grip/trim, `accent` for gems/glow (`glow` > 0 adds a halo), quality colour for
the frame (junk/crude plain; rare+ coloured frame; legendary/anomalous ornate).

## 6. Lorewright module (content data + generators)

Files: `data/races/`, `data/roles/`, `data/traits/`, `data/skills/`, `data/items/`,
`data/factions/`, `data/generation/{names,quirks,bios,titles,abilities,named,places}.json`,
`src/gen/*.gd`, `tests/test_generators.gd`. (`data/generation/appearance.json` belongs to
VisualUnits; `data/units|robots|airships|buildings` belong to the integrator.)

### 6.1 Stat modifier keys (the simulation understands exactly these)
Fractions for `_pct` (0.1 = +10 %), flat otherwise:
`max_hp, max_hp_pct, armor, move_speed_pct, work_speed_pct, gather_speed_pct, build_speed_pct,
farm_speed_pct, carry, melee_damage_pct, ranged_damage_pct, attack_speed_pct, accuracy,
crit_chance, vision, night_vision, retreat_bias, loot_luck, energy_max, energy_regen_pct,
hp_regen_pct, xp_rate_pct, trade_pct, food_use_pct`.

### 6.2 Skills (ids)
`melee, archery, scouting, woodcutting, mining, farming, construction, engineering, medicine,
trade, cooking` — values 0–100 (archery covers all ranged weapons).

### 6.3 Tables
- `races`: `{id, name, plural, description, name_set, playable, base: {max_hp, move_speed (m/s ≈ 2.0–2.6), vision (m ≈ 8–11), carry (≈ 16–26), energy (≈ 100)}, skill_bias: {skill: int}, trait_weights: {trait: mult}, age_range: [min, max]}` — ids `human, sylvan, stoutkin, vulpin`.
- `roles`: `{id, name, description, playable, combat_role: "melee"|"ranged"|"support"|"none", class_icon: "class_*", skill_bonus: {skill: int}, starting_items: [item base ids], work_pref: [job ids: "gather","farm","build","haul","operate","explore","fight","trade"]}` — ids as listed in §4.
- `traits`: `{id, name, description, mods: {stat_key: value}, weight, tags: [], conflicts: [trait ids], polarity: "good"|"bad"|"mixed"|"flavor"}` — ≥ 30, mix of good/bad/odd (e.g. Cautious, Brave, Night Sight, Lucky, Curious, Nature Lover, Lazy, Clumsy, Glutton, Tireless, Sharpshooter, Iron Stomach, Absent-minded genius…).
- `skills`: `{id, name, description, category}`.
- `items` (bases): `{id, name, category: weapon|armor|tool|gadget|robot_part|airship_part|artifact|consumable|resource, slot: weapon|armor|gadget|robot_part|airship_part|none, visual: <character weapon/offhand/armor enum or "">, icon: <shape id>, base_stats: {...}, mods: {stat_key: value}, materials: [material ids], value: int, weight: float (drop weight), level_min: int, tags: [], name_nouns: [...]}`.
  Weapon `base_stats`: `damage, cooldown (s), range (m), kind: "melee"|"ranged", projectile: "arrow"|"bolt"|"bullet"|"none", accuracy (0..1)`.
  Armor: `armor, max_hp`. Others: mods only (robot_part/airship_part mods apply to machines/airships).
  ≥ 30 bases across all categories; sensible numbers (villager dagger ≈ 6 dmg / 1.0 s, sword ≈ 11 / 1.1 s, bow ≈ 9 / 1.5 s / 9 m).
- `items/materials` (`{"table": "materials", "entries": [...]}`): `{id, name, color, secondary, stat_mult, value_mult, level_min, categories: [...]}` (e.g. scrap, wood, bronze, iron, steel, brass, crystal, obsidian, ancient_alloy).
- `items/qualities`: `{id, name, tier: 0..7, weight, stat_mult, value_mult, affix_count: [min, max], color, glow}` — exactly `junk, crude, common, fine, rare, epic, legendary, anomalous` with weights so that roughly junk 28 %, crude 26 %, common 25 %, fine 12 %, rare 6 %, epic 2.3 %, legendary 0.6 %, anomalous 0.1 %.
- `items/affixes`: `{id, kind: "prefix"|"suffix", name, mods, categories: [...], weight, level_min}` — ≥ 30; anomalous items get a unique hand-written-feeling name + a weird strong mod combo (possibly with a drawback).
- `factions`: `{id, type: "player"|"bandit"|"machine"|"merchant"|"wanderer", style, color, secondary, hostile_to_player: bool, name_patterns: [...], description}`.
- `generation/names` (raw doc): `{"sets": {"<name_set>": {"female": [...], "male": [...], "neutral": [...], "family": [...]}}, "nicknames": [...], "squads": [...], "machines": {...}, "airships": [...]}`.
- `generation/quirks`: `{"quirks": [≥ 80 short sentences]}`; `generation/bios`: quote + backstory templates with placeholders; `generation/titles`: `{"titles": [{"id", "name", "stat", "min"}]}` where stat ∈ `kills, tiles_explored, built, harvested, chopped, mined, days_survived, loot_found, downed_survived`; `generation/abilities`: `{"table": "abilities", "entries": [{id, name, kind: "buff_allies"|"buff_self"|"heal_self"|"multi_shot", radius, duration, cooldown, mods, amount_pct, trigger_hp, shots}]}`; `generation/named`: name parts for named enemies per faction type; `generation/places`: place-name parts per POI kind.

### 6.4 Generators (deterministic: only the passed rng)
```gdscript
class_name NameGen
static func person(rng, race: String, gender: String) -> Dictionary   # {given, family, full}
static func place(rng, kind: String) -> String   # kind: ruins, bandit_camp, machine_outpost, trade_post, wanderer_camp, wreck, crystal, ore_field, region, settlement
static func faction(rng, type: String) -> String
static func squad(index: int) -> String          # 0 -> "Alpha", 1 -> "Bravo", ...
static func machine(rng, archetype: String) -> String   # e.g. "KX-7 \"Rivet\""
static func airship(rng) -> String               # e.g. "The Wandering Gull"

class_name NpcGen
static func generate(rng, opts: Dictionary) -> Dictionary
# opts: race, role ("" = pick), gender (""), level (1), talent ("" = roll | "prodigy"|"skilled"|"average"|"mediocre"|"poor"), faction_type ("player")
# NOT responsible for appearance (the integrator adds it with AppearanceGen).

class_name ItemGen
static func generate(rng, opts: Dictionary) -> Dictionary
# opts: base (""), category (""), level (1), quality ("" = roll), luck (0.0), source ("loot"|"start"|"shop"|"boss")
static func roll_quality(rng, luck: float) -> String
static func loot(rng, level: int, luck: float, count: int) -> Array
static func relic(rng, theme: String, level: int, difficulty: int) -> Dictionary
static func trophy(base: String, level: int) -> Dictionary
static func describe(item: Dictionary) -> PackedStringArray   # tooltip lines: quality/level, stats, mods, flavor

class_name NamedEnemyGen
static func generate(rng, opts: Dictionary) -> Dictionary
# opts: base ("bandit_captain"|"machine_warden"|...), faction_type, level, tier (1..3)
# -> {name, epithet, full_name, base, level, tier, traits: [], abilities: [ids], equipment: {slot: item}, loot: [items], stat_mult: {max_hp, damage}, bio}
```
Character dictionary (NpcGen output; JSON-safe):
```
{name, given, family, nickname, race, role, gender, age, level, xp,
 skills: {skill: int}, aptitude: {skill: float 0.5..2.0}, traits: [ids], quirk, bio (one-line quote),
 backstory (1–2 sentences), equipment: {weapon: item|null, armor: item|null, gadget: item|null},
 titles: [], rank: "", talent: "prodigy"|"skilled"|"average"|"mediocre"|"poor"}
```
Talent spread matters: some NPCs are brilliant in one skill (70–95), many are ordinary (10–40),
some are bad at almost everything, some strong fighters have terrible work skills, etc.
Item dictionary (ItemGen output; `uid` is assigned later by the simulation, use 0):
```
{uid: 0, base, name, category, slot, quality, level, material, stats: {...}, mods: {...},
 value, flavor, unique: bool, visual, appearance: {§3.5}}
```
Most loot must be junk/crude/common; the joy is the rare find among ordinary items.

Power scaling applies only to damage, armor, max_hp, carry and power. Weapon range, cooldown and
accuracy stay at their base values; quality must not slow a weapon or make accuracy exceed 1.
Relics merge theme modifiers with generated base/affix modifiers, never replace them. Optional
item fields: `relic_theme`, `upgrade` (0..3), `condition` (0..100, missing means pristine).
Durability affects effective weapon damage/armor; the saved item's nominal stats remain intact.

## 7. Dungeons, giants and gearwork

- `World.setup(seed, generation_races = [], with_dungeons = false)` preserves the old map by
  default. `NewGame` enables dungeons; saves persist this flag and restore runtime site records
  before rebuilding chunks. Old saves without the flag do not reserve a dungeon zone.
- `DungeonZone` reserves a 160×416 block at the far world edge: 4 slots × up to 10 floors,
  36×36 tiles per floor, pitch 40. Pure floor generation uses seed + entrance ID + floor index.
  Navigation treats rock walls as solid. Surface flight detours around the whole block.
- `Dungeons` owns `World.sites` entries of kind `dungeon` / `dungeon_floor`. IDs start at
  2,000,000 in blocks of 16. Entrance fields: difficulty, floors, slot, theme, spawn_day, state,
  floor_sids. Floor fields: dungeon, floor, boss_id, cleared. `after_load()` restores integer
  fields and `WorldGen.sites` records. Collapse removes owned units, loot and visuals, evacuates
  occupants and frees the slot.
- Travel: `enter(units, eid)`, `leave(units, eid)`, `use_stairs(units, eid, floor_index, direction)`.
  Squad orders `enter` / `stairs` walk to the feature before transfer; indoor `auto` / `explore`
  clear, loot and descend; `retreat` climbs out. `locate(pos)` / `squad_location(squad)` return
  `{eid, floor}` or `{}` for the surface. `same_map(a, b)` compares slot and floor, not tile
  coordinates. Ordinary movement cannot transfer between maps.
- Signals: `relocated(pos, eid, floor_index)` moves the camera; `floor_created(eid, floor_index)`
  builds discovered stair markers; `World.site_removed(id)` releases site visuals.
- `Giants.make_master(theme, difficulty, level, pos)` and `spawn_beast(pos, level = 5)` create
  named large units. `Unit.body_radius()` drives giant-specific local navigation, attack reach,
  selection rings and HP-bar width. `Giants.fits` / `path` prevent squeezing through narrow doors.
- Persistent giant state lives in `Unit.named`: giant, roaming, theme, phase, mood, abilities,
  summoner, next_wander, and cast. `Combat` owns telegraph/summon execution. Cast contains id,
  pos `[x,z]`, left, duration, radius, damage; death cancels it and loading resumes its remaining
  windup exactly once. Half health enters phase 2. A roaming beast's paths and targets exclude
  player buildings' 42m safety radius; the beast releases distant targets and returns home.
- `Gearwork.available(sid = -1)` checks a built workshop or the existing town service gate.
  `owned(uid)` resolves armory/equipped ownership. `forge(theme, sid = -1)` and
  `act(uid, action, sid = -1)` return `""` on success or an i18n error key. Actions: repair,
  upgrade, dismantle. Validate before spending; preserve uid when repairing/upgrading;
  dismantle only unequipped owned items; recompute the wearer's stats immediately.
- `GearworkPanel.build(body, game, hud, sid = -1)` is shared by workshop and town smith.
  Buttons capture item uid, never mutable list indices.
- Loot over an obstacle lands on nearby ground on the same map. Auto collection chooses a
  reachable picker/bag; a partial route outside pickup distance is not progress.
