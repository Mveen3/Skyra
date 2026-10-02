#!/usr/bin/env python3
"""Adds fine realistic detail parts ("detail": true -> drawn without the thick outline)
to data/art/weapons_art.json. Idempotent: earlier detail parts are replaced."""
import json, os
P = os.path.join(os.path.dirname(__file__), "..", "data", "art", "weapons_art.json")

def R(x, y, w, h, fill, r=0, alpha=1.0, tag=None):
    d = {"type": "rect", "x": x, "y": y, "w": w, "h": h, "fill": fill, "detail": True}
    if r: d["r"] = r
    if alpha != 1.0: d["alpha"] = alpha
    if tag: d["tag"] = tag
    return d
def L(a, b, w, stroke, alpha=1.0, tag=None):
    d = {"type": "line", "a": a, "b": b, "w": w, "stroke": stroke, "detail": True}
    if alpha != 1.0: d["alpha"] = alpha
    if tag: d["tag"] = tag
    return d
def C(c, r, fill, alpha=1.0, tag=None):
    d = {"type": "circle", "c": c, "r": r, "fill": fill, "detail": True}
    if alpha != 1.0: d["alpha"] = alpha
    if tag: d["tag"] = tag
    return d
def PL(pts, w, stroke, alpha=1.0):
    d = {"type": "polyline", "pts": pts, "w": w, "stroke": stroke, "detail": True}
    if alpha != 1.0: d["alpha"] = alpha
    return d
def PG(pts, fill, alpha=1.0, tag=None):
    d = {"type": "poly", "pts": pts, "fill": fill, "detail": True}
    if alpha != 1.0: d["alpha"] = alpha
    if tag: d["tag"] = tag
    return d

SCREW = "#2C3036"
HI = "#FFFFFF"
DETAILS = {
  "magnum": [  # .44 revolver: vent rib, sights, hammer, cylinder pin, grip checkering + medallion
    R(12, -15, 26, 2, "#C3CCD6"), L([13, -14.5], [37, -14.5], 0.6, HI, 0.6),
    *[R(15 + i * 5, -15, 2, 1.2, "#6B7682") for i in range(5)],
    PG([[35, -16], [39, -16], [39, -18.5], [37, -18.5]], "#5A636D"),
    R(-6, -16, 4, 3, "#4A525C", 1), PG([[-8, -15], [-4, -16], [-6, -19]], "#3F464E"),
    C([10.5, -8], 1.3, "#5A636D"), L([12, -9.5], [36, -9.5], 0.5, "#8C97A3", 0.8),
    PL([[-4, 1], [0.5, 9]], 0.7, "#4A2E1C", 0.8), PL([[-2, 0], [1.5, 8]], 0.7, "#4A2E1C", 0.8),
    PL([[-5, 4], [1, 2]], 0.7, "#4A2E1C", 0.8), PL([[-6, 7], [1, 5]], 0.7, "#4A2E1C", 0.8),
    C([-1.5, 3.5], 1.4, "#D9B44A"), C([-1.5, 3.5], 0.6, "#8C6A1E"),
    R(2, -2, 1.6, 4, "#3A4048"),
  ],
  "ak47": [  # AKM: slant brake, gas block, rivets, rear sight, selector, guard, mag ribs, wood grain
    PG([[70, -12], [76, -12.5], [76, -6.5], [72, -6.5]], "#1E2025"),
    R(56, -17, 7, 4, "#2A2D33", 1), R(26.5, -18.5, 3, 2, "#4A4F57"),
    *[C([x, -6.5], 0.8, "#6E747C") for x in (-2, 6, 20, 27)],
    PL([[4, -12], [14, -12], [16, -9], [22, -9]], 0.9, "#1E2126"),
    C([2, -9], 1.0, "#5C6168"),
    PL([[-2, -4], [-1, 2], [6, 2], [7, -4]], 1.6, "#2A2D33"),
    L([3, -4], [2.5, 0.5], 1.2, "#1B1D21"),
    L([10, -1], [16, -2], 0.8, "#8E3A10", 1.0, "mag"), L([12, 4], [19, 3], 0.8, "#8E3A10", 1.0, "mag"),
    L([15, 9], [22, 8], 0.8, "#8E3A10", 1.0, "mag"),
    PL([[-29, -8], [-20, -9], [-10, -10]], 0.6, "#D98A4E", 0.7), PL([[-28, -1], [-18, -3], [-9, -6]], 0.6, "#D98A4E", 0.7),
    L([33, -11], [47, -11.5], 0.6, "#D98A4E", 0.7),
    R(-30, -10, 3, 12, "#5E3214", 0, 0.9),
  ],
  "mp5": [  # MP5: hooded front sight, drum rear sight, cocking handle, trigger group, mag ribs
    C([43.5, -19], 2.4, "#2B2F36"), C([43.5, -19], 1.0, "#0E0F12"),
    C([-4, -17], 1.4, "#0E0F12"),
    L([28, -12], [36, -16], 1.6, "#3A3F47"), C([36, -16], 1.3, "#555B64"),
    PL([[-2, -5], [-1, 1], [7, 1], [7, -5]], 1.5, "#1E2126"), L([3, -5], [2.5, -1], 1.1, "#0E0F12"),
    *[L([11 + i * 1.6, -2 + i * 4.2], [17 + i * 1.6, -2.6 + i * 4.2], 0.7, "#0E0F12", 1.0, "mag") for i in range(3)],
    *[C([x, -10], 0.7, "#5A6069") for x in (-4, 8, 20)],
    L([-6, -13], [28, -13], 0.6, "#5A6069", 0.8),
  ],
  "shotgun": [  # pump-action: vent rib, bead, loading gate, guard, receiver pins, grain, butt pad line
    R(22, -14.5, 52, 1.5, "#3F434A"), *[R(25 + i * 6, -14.5, 2, 1.5, "#1B1D21") for i in range(8)],
    C([74, -14], 0.8, "#FFF4B0"),
    R(-1, -4, 12, 1.5, "#22252A"), C([0, -8], 0.9, "#7A8088"), C([16, -8], 0.9, "#7A8088"),
    PL([[-3, -2], [-2, 4], [5, 4], [6, -2]], 1.5, "#2A2D33"), L([1, -2], [0.5, 2], 1.1, "#141518"),
    PL([[-32, -6], [-20, -8], [-8, -10]], 0.6, "#C98352", 0.75), PL([[-31, 0], [-19, -2], [-8, -5]], 0.6, "#C98352", 0.75),
    L([-34, -9], [-34, 4], 1.2, "#3A3A3A"),
    L([37, -8.5], [57, -8.5], 0.6, "#C98352", 0.8, "pump"),
  ],
  "m93ba": [  # anti-materiel rifle: scope turrets + lens, brake ports, bolt knob, rail teeth, cheek rest
    R(14, -27.5, 4, 3, "#2B3036", 1), R(14, -18, 4, 1.5, "#2B3036"), C([3, -21.5], 2.0, "#0B0C0E"),
    C([42, -21], 2.2, "#B8F6FF", 0.9, "glow"), C([41, -22.5], 0.9, HI, 0.9, "glow"),
    *[R(x, -14, 1.2, 1.5, "#141716") for x in range(-6, 32, 3)],
    R(97, -13.5, 1, 9, "#3A433A"), C([5, -10], 1.6, "#9AA39A"),
    L([-34, -10], [-10, -10], 0.6, "#5E6E58", 0.8), R(-29, -17.5, 13, 1, "#4A5946"),
    *[C([x, -9], 0.7, "#5E6A5A") for x in (-4, 12, 28)],
    L([34, -10], [96, -10], 0.5, "#3A433A", 0.9),
  ],
  "flamethrower": [  # fuel tank straps + gauge, hose, nozzle cage
    PL([[30, 8], [36, 12], [48, 12], [56, 4]], 2.0, "#2A2D33"),
    C([24, 4], 3.0, "#E8E8E8"), C([24, 4], 2.2, "#1A1A1A"), L([24, 4], [25.5, 2.5], 0.6, "#FF5555"),
    *[R(x, -14, 1.2, 9, "#2A2D33", 0, 0.9) for x in (62, 65, 68)],
  ],
  "phasr": [  # emitter rings, vent fins, energy readout ticks
    *[R(x, -15, 1.2, 2.5, "#9AA6B2") for x in (2, 6, 10, 14)],
    C([70, -9], 2.0, "#E8FFFF", 0.9), L([-18, -10], [40, -10], 0.6, "#FFFFFF", 0.5),
  ],
  "rocket_launcher": [  # tube bands, sight frame, warning text block, grip texture
    *[R(x, -18, 2, 15, "#2F3A22", 0, 0.9) for x in (-30, 10, 38)],
    R(-6, -27, 10, 2, "#2B2F2A"), L([-6, -27], [-6, -23], 0.8, "#2B2F2A"),
    R(16, -15, 12, 3, "#D9C24A", 0, 0.85), L([17, -13.5], [27, -13.5], 0.6, "#3A3A20"),
    L([-48, -12], [60, -12], 0.6, "#C9D4A8", 0.45),
  ],
  "saw_gun": [  # motor vents + bolts on the housing
    *[R(x, -14, 1.2, 7, "#2A2D33", 0, 0.85) for x in (-12, -9, -6)],
    C([0, -15], 0.9, "#7A8088"), C([12, -15], 0.9, "#7A8088"),
  ],
}

def main():
    data = json.load(open(P))
    for wid, extra in DETAILS.items():
        w = data["weapons"][wid]
        w["primitives"] = [p for p in w["primitives"] if not p.get("detail")] + extra
    with open(P, "w") as f:
        json.dump(data, f, indent=1)
        f.write("\n")
    print("details added to", len(DETAILS), "weapons")

if __name__ == "__main__":
    main()
