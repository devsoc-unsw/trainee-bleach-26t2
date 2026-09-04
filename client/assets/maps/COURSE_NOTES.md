# UNSW Putt Party: course blockout notes

Original low-poly geometry for Godot 4.7. **Y-up, 1 unit = 1 metre**, transforms baked (identity rotation/scale on mesh nodes), **origin at the tee**, play direction **−Z**.

No Google Street View panoramas, Earth 3D tiles, or Map textures are in these files. Street View / Maps were used as visual reference only; meshes are original boxes, ramps, and cylinders.

Rebuild: `python3 unsw_putt_maps/build_courses.py`

---

## Shared conventions

| Node | Role |
|---|---|
| `Tee` | Empty at ground height on the putting surface |
| `HolePoint` | Empty at ground height at the cup centre |
| `Green` | Grass putting surface (hole punched; not a second overlapping slab) |
| `Pavement` | Concrete / mall / plaza |
| `Road` | Anzac Parade asphalt (main_walk only) |
| `Stairs` | Rainbow climb as **one continuous ramp** (7 coplanar colour strips, no lips) |
| `HoleCut` | 0.40 m diameter cup liner + floor, ~0.22 m deep |

Putting surfaces that meet (pavement → ramp → lawn, mall → law lawn) share the same surface Y at the joint.

Playable corridor width is about **12–14 m** on all three maps.

---

## 1. `rainbow_stairs.glb`: Basser Steps to Quad / library lawn

**Length:** 33.4 m tee→hole (target 25–40 m).  
**Tee:** `(0.0, 0.0, 0.0)`  
**HolePoint:** `(1.15, 1.40, -33.4)`  
**Ramp:** 18 m run, **1.40 m** rise (~7.8% grade). Looks like rainbow stairs; plays as a smooth ramp (strip joints use the same lerp so there is no stair lip). Side accessibility ramp is the same slope (`Pavement`).

### Reference used
- Google Maps / Street View search: [Basser Steps, UNSW Kensington](https://www.google.com/maps/search/?api=1&query=Basser+Steps+UNSW+Kensington) (rainbow-painted steps by the Quadrangle; opened as rainbow Basser Steps, 2016).
- [StudentVIP: Basser Steps](https://studentvip.com.au/unsw/kensington/maps/133105) (upper/lower campus connector; ramp access).
- [Library Lawn](https://studentvip.com.au/unsw/kensington/maps/136628) (lawn opposite the main library / Matthews / Morven Brown).
- Campus orientation notes from the Kensington map (Quad / library lawn at the top of the climb).

### Real-world observations (compressed into a 34 m hole)
- **Basser Steps** are a wide pedestrian stair between lower campus and the Quad / library lawn, with an accessibility ramp beside the flight.
- Treads are rainbow-striped (pride colours). In-game the **putting surface** is a single ramp with `mat_rainbow_1`…`mat_rainbow_7` bands (red → violet).
- Bottom: paved landing, bins, trees, hedges against building edges.
- Top: open lawn in front of cream Quad masses; taller brick library-like tower to the side.
- Stair width on campus is on the order of **10–12 m**; playable width here is **12 m** (`x = -6 … +6`).

### Left / right while playing (−Z, up the ramp)
| Side | What you hit |
|---|---|
| Left (−X) | Hedge, cream wing (`QuadBuildings`), side ramp, trees on the lawn |
| Right (+X) | Hedge, cream wing, brick library tower, trees |
| Ahead | Lawn cup; Quad backdrop |

### Playable vs decoration
- **Playable:** `Pavement` plaza, `Stairs` ramp, side ramp, `Green` lawn, `HoleCut`.
- **Decoration / bumpers:** `QuadBuildings`, `Hedge_*`, `Tree_*`, `Bin_*`, `Kerb_*`, metal handrails on `Stairs`.

---

## 2. `main_walk.glb`: Anzac Parade LR to University Mall to Law lawn

**Length:** 58.5 m tee→hole (target 50–70 m). Real mall is much longer; this is a compressed blockout.  
**Tee:** `(0.0, 0.0, 0.0)` on the mall pavers, just inside campus from Anzac Parade.  
**HolePoint:** `(1.8, 0.0, -58.5)` on the Law lawn.

### Reference used
- Start pano (as specified), looking ~203.7° into campus:  
  `https://www.google.com/maps/@-33.9170015,151.227303,2a,75y,203.7h,79.1t/data=!3m7!1e1!3m5!1sDI7aqN2RK0zPhTyg6sFGxA!2e0!6shttps:%2F%2Fstreetviewpixels-pa.googleapis.com%2Fv1%2Fthumbnail%3Fcb_client%3Dmaps_sv.tactile%26w%3D900%26h%3D600%26pitch%3D10.900092576608884%26panoid%3DDI7aqN2RK0zPhTyg6sFGxA%26yaw%3D203.70258104804086!7i13312!8i6656`
- Same panoid, other yaws (0 / 90 / 180 / 270) for left/right buildings. **Not stored in this repo**.
- [UNSW Anzac Parade stop guide](https://transportnsw.info/document/4894/unsw-anzac-parade-stop-guide.pdf) (L3 Kingsford Line; mall entrance off Anzac Parade).
- [Public transport: L3 near University Mall](https://www.unsw.edu.au/estate/getting-here/public-transport)
- Wikimedia (modelling reference only, not shipped): *UNSW Main Walk*, *Main Walkway, Lower campus UNSW*, *UNSW Gate Two 001*.

### Real-world observations from the start pano
Standing on the mall looking into campus (~203°):
- **Corridor:** ~6–10 m of actual path in that pinch; modelled playable mall is **14.4 m** (`x = -7.2 … +7.2`) to sit in the 8–16 m brief, matching the wider University Mall pavers further in (~12–16 m in mall photos).
- **Surface:** light tan / grey pavers, flat, continuous. Side lawns flush with the pavers.
- **Left (−X, Law side):** cream / off-white modern facade with **angled vertical fins** and dark glass; tropical planters at the base. Brick **clock-tower** mass behind. Modelled as `LawLibrary`.
- **Right (+X):** brown brick hall with a **tall hedge / ivy wall** on a low kerb. Modelled as `BrickHall` + `Hedge_Mall`.
- **Ahead:** mall opens to lawn and trees. The hole sits on that lawn (`Green`).
- **Behind the tee (+Z):** Anzac Parade `Road`, L3 `Tram` in the reservation, and `Platform` (UNSW Anzac Parade stop). Kerb separates road from mall so the ball stays on campus pavement.

### Left / right while playing (−Z down the mall)
| Side | What you hit |
|---|---|
| Left (−X) | Planters / fins of `LawLibrary`, trees, side lawn (`Green`), bins |
| Right (+X) | Hedge, brick hall, trees, side lawn |
| Behind (+Z) | Platform, tram, Anzac Parade (not the intended line) |
| Ahead | Law lawn cup |

### Playable vs decoration
- **Playable:** `Pavement` mall, side strips of `Green`, end `Green` with `HoleCut`.
- **Decoration / bumpers:** `Road`, `Tram`, `Platform`, `LawLibrary`, `BrickHall`, `Hedge_Mall`, `Tree_*`, `Bin_*`, `Kerb_*`.

---

## 3. `village_green.glb`: Village Green, bouldering wall, soccer field

**Length:** 37.6 m tee→hole (target 30–45 m).  
**Tee:** `(0.0, 0.0, 0.0)` on the perimeter pavement.  
**HolePoint:** `(-1.4, 0.0, -37.6)` on the lawn **outside** the fenced pitch.

### Reference used
- Maps search: [UNSW Village Green Kensington](https://www.google.com/maps/search/?api=1&query=UNSW+Village+Green+Kensington)
- [Village Green redevelopment](https://www.unsw.edu.au/estate/campus-development/projects/village-green-redevelopment): synthetic FIFA/rugby pitch, 500 m walking track, fig-tree edge to University Mall, social / **bouldering** / casual terraces, Moya Dodd Stand, Sam Cracknell Pavilion.
- [Bouldering Beauty: IBN Legend+](https://www.outdoordesign.com.au/news-info/exemplary-projects/bouldering-beauty/9510.htm): two units + bridge, **~8 m long × ~4 m wide × ~3 m high**, ~70 m² climbing surface. Geometry here is original boxes at that scale, not a scan.
- Wikimedia *UNSW Village Green 2025-01-05*: rectangular fenced synthetic pitch, white goals, perimeter concrete walk, palms, brick halls, grandstand canopy on one long side.

### Real-world observations (compressed)
- Pitch is a full field (~8000 m² cited in estate docs). The **golf line does not cross the fenced pitch**; it runs the lawn/walk beside it (~14 m corridor).
- Bouldering wall sits on the **active terrace** (model: left / −X of the corridor).
- Goals, fence, grandstand, and far brick hall are beside the hole, not stacked as a second ground.
- Perimeter walk is concrete; lawn is flush with it at `z = -10`.

### Left / right while playing (−Z)
| Side | What you hit |
|---|---|
| Left (−X) | `BoulderWall` (two masses + bridge), trees, bins |
| Right (+X) | Track strip (`Pavement`), `PitchFence`, `SoccerPitch`, `SoccerGoal_A` / `_B`, `Grandstand` |
| Ahead | Cup on lawn; `VillageHall` behind |

### Playable vs decoration
- **Playable:** start `Pavement`, `Green` lawn corridor, `HoleCut`. The track strip is putt-able but off-line.
- **Decoration / bumpers:** `BoulderWall`, `SoccerPitch`, goals, fence, grandstand, `VillageHall`, `Tree_*`, `Bin_*`, `Kerb_*`.

---

## Import notes (Godot 4.7)

1. Import each `.glb` as its own scene.  
2. Map `mat_*` to your golf materials (base colours only in the file). Extra names used: `mat_foliage`, `mat_hedge`, `mat_trunk`, `mat_metal`, `mat_glass`, `mat_white`, `mat_cup`.  
3. Use `Tee` / `HolePoint` global positions for spawn and cup logic.  
4. Treat `Green`, `Pavement`, `Stairs`, `Road` as physics surfaces; everything else as static colliders.  
5. `HoleCut` is the cup liner; `Green` already has a ~0.40 m circular hole so the ball can drop (do not layer another ground plane on the cup).

## What is not in the files
- Google Street View / Maps / Earth imagery or 3D tiles  
- Photogrammetry  
- High-poly scans  
- Overlapping putting slabs at the cup  
