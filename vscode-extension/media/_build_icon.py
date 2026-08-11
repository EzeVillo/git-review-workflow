"""Build activity-bar (mono) and icon (color) from the product logo geometry.

Pixel-perfect rules:
- Left bars hard-stop before the spine gutter.
- Spine is an odd-width column; node centers share the same integer cx.
- Color mark matches the stashed logo palette.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
ASSETS = REPO / "assets"
DOCS = REPO / "docs"  # GitHub Pages publishes /docs only, so the site needs its own copy
INTELLIJ_RESOURCES = REPO / "intellij-plugin" / "src" / "main" / "resources"
FACE = ROOT / "_face.png"  # optional; only needed to re-extract the glyph
CODE_GLYPH_PNG = ROOT / "code-glyph.png"  # checked-in white </> from the logo

# Face-space geometry (512×512 crop of docs/logo.png app face)
SPINE_X = 245
GUTTER = 18
LEFT_LIMIT = SPINE_X - GUTTER  # 227

LEFT = [
    (59, 115, 137, 24),
    (59, 166, 157, 24),
    (59, 217, 158, 24),
    (93, 267, 124, 25),
    (59, 318, 138, 25),
    (116, 369, 100, 24),
]
LEFT = [(x, y, min(w, LEFT_LIMIT - x), h) for x, y, w, h in LEFT]

GREEN = [
    (281, 95, 88, 24),
    (282, 146, 150, 24),
    (281, 197, 116, 24),
    (281, 248, 173, 24),
]

# Logo palette
COL_TILE_TOP = (26, 32, 48, 255)
COL_TILE_BOT = (16, 21, 31, 255)
COL_TILE_EDGE = (42, 51, 68, 255)
# Diff palette: left = removals (red), right = additions (green)
COL_LEFT = (224, 102, 107, 255)  # #E0666B — same family as the landing --del
COL_SPINE = (107, 115, 128, 255)
COL_NODE = (213, 218, 226, 255)
COL_GREEN = (61, 220, 132, 255)  # #3DDC84 — additions
COL_CODE = (243, 244, 246, 255)
COL_MONO = (255, 255, 255, 255)

# Fit mark content into the icon view (include full </> glyph + margin)
X_MIN, X_MAX = 59, 490
Y_MIN, Y_MAX = 70, 448
PAD = 24
BOX_X0, BOX_Y0 = X_MIN - PAD, Y_MIN - PAD
BOX_X1, BOX_Y1 = X_MAX + PAD, Y_MAX + PAD
ORIGIN_CX = (BOX_X0 + BOX_X1) / 2
ORIGIN_CY = (BOX_Y0 + BOX_Y1) / 2
SIDE = max(BOX_X1 - BOX_X0, BOX_Y1 - BOX_Y0)

# Output size and tile padding (color icon has rounded app-tile chrome)
SIZE = 128
TILE_INSET = 6  # px of tile margin around the mark in the color icon
MARK_SIZE = SIZE - 2 * TILE_INSET  # 116 — mark lives here in color mode

# Code glyph </> in face space — PNG and SVG share these strokes.
#   <>  identical mirrored chevrons (same width & open height)
#   /   steeper (more vertical) and taller than the chevrons; tight gaps
#   Whole group sits just under the green bars (raised vs earlier drafts).
#
# Built from one chevron size so < and > cannot drift apart.
_CHEV_W = 40  # apex → open (horizontal) — same for < and >
_CHEV_HH = 20  # half of open height — same for < and >
# Between the earlier low (~386) and the too-high (~328) placements.
_CY = 358
# Enough air so the thick / stroke does not melt into > (or <).
_GAP = 22
_LAX = 298  # < apex x
_LOX = _LAX + _CHEV_W  # < open x
_SX0 = _LOX + _GAP  # / bottom x
_SDX = 18  # / horizontal run (small → more vertical)
_SX1 = _SX0 + _SDX  # / top x
_ROX = _SX1 + _GAP  # > open x
_RAX = _ROX + _CHEV_W  # > apex x
# / taller than <>; room above without kissing the green bars (end ~272).
_SLASH_UP = 22
_SLASH_DN = 30

CODE_ARMS: tuple[tuple[tuple[float, float], tuple[float, float]], ...] = (
    # <  (mirror of >)
    ((_LOX, _CY - _CHEV_HH), (_LAX, _CY)),  # upper
    ((_LOX, _CY + _CHEV_HH), (_LAX, _CY)),  # lower
    # /  more vertical + taller than <>
    ((_SX0, _CY + _CHEV_HH + _SLASH_DN), (_SX1, _CY - _CHEV_HH - _SLASH_UP)),
    # >  (mirror of <)
    ((_ROX, _CY - _CHEV_HH), (_RAX, _CY)),  # upper
    ((_ROX, _CY + _CHEV_HH), (_RAX, _CY)),  # lower
)
CODE_JOINTS: tuple[tuple[float, float], ...] = (
    (_LAX, _CY),  # < apex
    (_RAX, _CY),  # > apex
)
CODE_WIDTH_FACE = 17
SPINE_W = 3  # odd; geometric center == spine_cx in both PIL and SVG


def to_mark(fx: float, fy: float, mark_size: int) -> tuple[float, float]:
    """Map face-space → mark canvas (mark_size × mark_size)."""
    ix = (fx - (ORIGIN_CX - SIDE / 2)) / SIDE * mark_size
    iy = (fy - (ORIGIN_CY - SIDE / 2)) / SIDE * mark_size
    return ix, iy


def to_mark_i(fx: float, fy: float, mark_size: int) -> tuple[int, int]:
    ix, iy = to_mark(fx, fy, mark_size)
    return int(round(ix)), int(round(iy))


def _code_stroke_width(mark_size: int) -> int:
    w = max(3, int(round(CODE_WIDTH_FACE / SIDE * mark_size)))
    return w if w % 2 == 1 else w + 1


def _draw_code(
    d: ImageDraw.ImageDraw,
    mark_size: int,
    fill: tuple[int, int, int, int],
) -> None:
    """Draw </> with round caps and solid chevron joints (no hollow pixels)."""
    stroke_w = _code_stroke_width(mark_size)
    cap_r = stroke_w / 2

    def stroke(p0: tuple[float, float], p1: tuple[float, float]) -> None:
        a = to_mark(p0[0], p0[1], mark_size)
        b = to_mark(p1[0], p1[1], mark_size)
        d.line([a, b], fill=fill, width=stroke_w)
        for px, py in (a, b):
            d.ellipse([px - cap_r, py - cap_r, px + cap_r, py + cap_r], fill=fill)

    for p0, p1 in CODE_ARMS:
        stroke(p0, p1)
    # solid apex discs — kills the hollow pixel at < / > corners
    for jx, jy in CODE_JOINTS:
        px, py = to_mark(jx, jy, mark_size)
        d.ellipse([px - cap_r, py - cap_r, px + cap_r, py + cap_r], fill=fill)


def draw_mark(mark_size: int, color: bool) -> Image.Image:
    """Draw the logo mark on a transparent mark_size×mark_size canvas."""
    img = Image.new("RGBA", (mark_size, mark_size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    left_c = COL_LEFT if color else COL_MONO
    green_c = COL_GREEN if color else COL_MONO
    spine_c = COL_SPINE if color else COL_MONO
    node_c = COL_NODE if color else COL_MONO
    code_c = COL_CODE if color else COL_MONO

    def pill(fx: int, fy: int, fw: int, fh: int, fill: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
        ax, ay = to_mark_i(fx, fy, mark_size)
        bx, by = to_mark_i(fx + fw, fy + fh, mark_size)
        if bx <= ax:
            bx = ax + 2
        if by <= ay:
            by = ay + 2
        rad = max(1, (by - ay) // 2)
        d.rounded_rectangle([ax, ay, bx, by], radius=rad, fill=fill)
        return ax, ay, bx, by

    # --- bars ---
    for rect in LEFT:
        box = pill(*rect, left_c)
        # left bars must stop before spine
        assert box[2] < to_mark_i(SPINE_X, 0, mark_size)[0] - 2, box

    for rect in GREEN:
        pill(*rect, green_c)

    # --- spine: odd width, geometric center == spine_cx ---
    spine_cx = to_mark_i(SPINE_X, 0, mark_size)[0]
    sy0 = to_mark_i(SPINE_X, 70, mark_size)[1]
    sy1 = to_mark_i(SPINE_X, 448, mark_size)[1]
    half_w = SPINE_W // 2  # 1 for width 3
    # PIL rect is inclusive on both corners → [cx-1, …, cx+1] centers on cx
    d.rounded_rectangle(
        [spine_cx - half_w, sy0, spine_cx + half_w, sy1],
        radius=half_w,
        fill=spine_c,
    )

    # --- nodes: exact same cx as spine ---
    nodes: list[tuple[int, int, int]] = []
    for fcy in (156, 402):
        ncy = to_mark_i(SPINE_X, fcy, mark_size)[1]
        ncx = spine_cx
        y_top = to_mark_i(SPINE_X, fcy - 15, mark_size)[1]
        y_bot = to_mark_i(SPINE_X, fcy + 15, mark_size)[1]
        rad = max(2, (y_bot - y_top) // 2)
        # inclusive bbox, odd diameter 2*rad+1 → true center at ncx
        d.ellipse([ncx - rad, ncy - rad, ncx + rad, ncy + rad], fill=node_c)
        nodes.append((ncx, ncy, rad))

    # --- code glyph </> (shared geometry with SVG) ---
    _draw_code(d, mark_size, code_c)

    # --- hard-clear gutters (keep nodes) ---
    left_limit_ix = to_mark_i(LEFT_LIMIT, 0, mark_size)[0]
    green_start_ix = to_mark_i(SPINE_X + GUTTER, 0, mark_size)[0]
    ipx = img.load()

    def near_node(ix: int, iy: int) -> bool:
        for ncx, ncy, rad in nodes:
            if (ix - ncx) ** 2 + (iy - ncy) ** 2 <= (rad + 1) ** 2:
                return True
        return False

    for iy in range(mark_size):
        for ix in range(left_limit_ix, spine_cx):
            if not near_node(ix, iy):
                ipx[ix, iy] = (0, 0, 0, 0)
        for ix in range(spine_cx + 2, green_start_ix):
            if not near_node(ix, iy):
                ipx[ix, iy] = (0, 0, 0, 0)

    # re-draw spine + nodes after clear (guarantees center alignment)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(
        [spine_cx - half_w, sy0, spine_cx + half_w, sy1],
        radius=half_w,
        fill=spine_c,
    )
    for ncx, ncy, rad in nodes:
        d.ellipse([ncx - rad, ncy - rad, ncx + rad, ncy + rad], fill=node_c)
        assert ncx == spine_cx

    # verify gutter
    spine_cols = {spine_cx - 1, spine_cx, spine_cx + 1}
    bad = 0
    for iy in range(mark_size):
        left_xs = [
            ix
            for ix in range(0, spine_cx - 1)
            if ipx[ix, iy][3] > 200 and not near_node(ix, iy) and ix not in spine_cols
        ]
        if not left_xs:
            continue
        if max(left_xs) >= left_limit_ix:
            bad += 1
        for ix in range(left_limit_ix, spine_cx - 1):
            if ipx[ix, iy][3] > 200 and not near_node(ix, iy):
                bad += 1
    assert bad == 0, f"gutter violations: {bad}"

    # expose layout for SVG export
    img.info["spine_cx"] = spine_cx
    img.info["sy0"] = sy0
    img.info["sy1"] = sy1
    img.info["nodes"] = nodes
    img.info["left_limit_ix"] = left_limit_ix
    return img


def draw_color_tile(size: int = SIZE) -> Image.Image:
    """Full app-icon: dark rounded tile + color mark.

    The grey border is the *outermost* ring of the shape. The blue fill sits
    strictly inside it — no 1px fill halo past the border on the bottom/right.
    """
    from PIL import ImageChops

    radius = int(size * 0.22)

    # Outer silhouette (full tile) and inner area (fill only, 1px inset).
    outer = Image.new("L", (size, size), 0)
    ImageDraw.Draw(outer).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=radius, fill=255
    )
    inner = Image.new("L", (size, size), 0)
    ImageDraw.Draw(inner).rounded_rectangle(
        [1, 1, size - 2, size - 2],
        radius=max(1, radius - 1),
        fill=255,
    )

    # Vertical gradient, clipped to the *inner* mask (never under the border).
    grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / max(1, size - 1)
        r = int(COL_TILE_TOP[0] * (1 - t) + COL_TILE_BOT[0] * t)
        g = int(COL_TILE_TOP[1] * (1 - t) + COL_TILE_BOT[1] * t)
        b = int(COL_TILE_TOP[2] * (1 - t) + COL_TILE_BOT[2] * t)
        gd.line([(0, y), (size - 1, y)], fill=(r, g, b, 255))
    grad.putalpha(inner)

    # Border ring = outer − inner, painted with the edge colour.
    ring = ImageChops.subtract(outer, inner)
    border = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bp, rp = border.load(), ring.load()
    er, eg, eb, _ = COL_TILE_EDGE
    for y in range(size):
        for x in range(size):
            a = rp[x, y]
            if a:
                bp[x, y] = (er, eg, eb, a)

    tile = Image.alpha_composite(grad, border)

    # Mark: center by *content* bbox (the geometry is left-heavy, so a
    # fixed TILE_INSET leaves it shifted left inside the tile).
    mark = draw_mark(MARK_SIZE, color=True)
    bbox = mark.getbbox()
    if bbox is None:
        raise RuntimeError("empty mark")
    content_cx = (bbox[0] + bbox[2] - 1) / 2
    content_cy = (bbox[1] + bbox[3] - 1) / 2
    tile_cx = (size - 1) / 2
    tile_cy = (size - 1) / 2
    paste_x = int(round(tile_cx - content_cx))
    paste_y = int(round(tile_cy - content_cy))
    tile.paste(mark, (paste_x, paste_y), mark)
    return tile


def write_svg(
    path: Path,
    color: bool,
    *,
    width: int | None = None,
    height: int | None = None,
    gradient_id: str = "tile",
    border: str = "#2A3344",
    mono: str = "#C5C5C5",
) -> None:
    """Vector companion matching the raster geometry."""
    mark_size = SIZE  # SVG mono fills the viewBox; color SVG includes tile
    spine_cx = to_mark_i(SPINE_X, 0, mark_size)[0]
    sy0 = to_mark_i(SPINE_X, 70, mark_size)[1]
    sy1 = to_mark_i(SPINE_X, 448, mark_size)[1]
    nodes = []
    for fcy in (156, 402):
        ncy = to_mark_i(SPINE_X, fcy, mark_size)[1]
        y_top = to_mark_i(SPINE_X, fcy - 15, mark_size)[1]
        y_bot = to_mark_i(SPINE_X, fcy + 15, mark_size)[1]
        rad = max(2, (y_bot - y_top) // 2)
        nodes.append((spine_cx, ncy, rad))

    def fill(name: str) -> str:
        if not color:
            return mono
        return {
            "left": "#E0666B",  # diff removals
            "green": "#3DDC84",  # diff additions
            "spine": "#6B7380",
            "node": "#D5DAE2",
            "code": "#F3F4F6",
        }[name]

    size_attrs = ""
    if width is not None:
        size_attrs += f' width="{width}"'
    if height is not None:
        size_attrs += f' height="{height}"'
    lines: list[str] = [
        f'<svg{size_attrs} xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" fill="none">',
    ]

    if color:
        rx = SIZE * 0.22
        # Mark geometry at MARK_SIZE, then translate so content center
        # lands on the tile center (same as the PNG path).
        ms = MARK_SIZE
        spine_cx = to_mark_i(SPINE_X, 0, ms)[0]
        sy0 = to_mark_i(SPINE_X, 70, ms)[1]
        sy1 = to_mark_i(SPINE_X, 448, ms)[1]
        nodes = []
        for fcy in (156, 402):
            ncy = to_mark_i(SPINE_X, fcy, ms)[1]
            y_top = to_mark_i(SPINE_X, fcy - 15, ms)[1]
            y_bot = to_mark_i(SPINE_X, fcy + 15, ms)[1]
            rad = max(2, (y_bot - y_top) // 2)
            nodes.append((spine_cx, ncy, rad))
        mark_size = ms

        xs: list[float] = []
        ys: list[float] = []
        for x, y, w, h in (*LEFT, *GREEN):
            ax, ay = to_mark(x, y, ms)
            bx, by = to_mark(x + w, y + h, ms)
            xs.extend((ax, bx))
            ys.extend((ay, by))
        xs.extend((spine_cx - SPINE_W / 2, spine_cx + SPINE_W / 2))
        ys.extend((float(sy0), float(sy1)))
        for ncx, ncy, rad in nodes:
            xs.extend((ncx - rad, ncx + rad))
            ys.extend((ncy - rad, ncy + rad))
        for p0, p1 in CODE_ARMS:
            for px, py in (p0, p1):
                mx, my = to_mark(px, py, ms)
                xs.append(mx)
                ys.append(my)
        content_cx = (min(xs) + max(xs)) / 2
        content_cy = (min(ys) + max(ys)) / 2
        tx = (SIZE - 1) / 2 - content_cx
        ty = (SIZE - 1) / 2 - content_cy

        lines += [
            "  <defs>",
            f'    <linearGradient id="{gradient_id}" x1="64" y1="0" x2="64" y2="128" gradientUnits="userSpaceOnUse">',
            '      <stop stop-color="#1A2030"/>',
            '      <stop offset="1" stop-color="#10151F"/>',
            "    </linearGradient>",
            "  </defs>",
            # Fill inset 1px; stroke on the outer edge (no fill halo past the border).
            f'  <rect x="1" y="1" width="{SIZE - 2}" height="{SIZE - 2}" rx="{max(1, rx - 1):.1f}" fill="url(#{gradient_id})"/>',
            f'  <rect x="0.5" y="0.5" width="{SIZE - 1}" height="{SIZE - 1}" rx="{rx:.1f}" '
            f'fill="none" stroke="{border}" stroke-width="1"/>',
            f'  <g transform="translate({tx:.2f} {ty:.2f})">',
        ]

    # bars
    lines.append(f'  <g fill="{fill("left")}">')
    for x, y, w, h in LEFT:
        ax, ay = to_mark(x, y, mark_size)
        bx, by = to_mark(x + w, y + h, mark_size)
        lines.append(
            f'    <rect x="{ax:.2f}" y="{ay:.2f}" width="{bx - ax:.2f}" '
            f'height="{by - ay:.2f}" rx="{(by - ay) / 2:.2f}"/>'
        )
    lines.append("  </g>")
    lines.append(f'  <g fill="{fill("green")}">')
    for x, y, w, h in GREEN:
        ax, ay = to_mark(x, y, mark_size)
        bx, by = to_mark(x + w, y + h, mark_size)
        lines.append(
            f'    <rect x="{ax:.2f}" y="{ay:.2f}" width="{bx - ax:.2f}" '
            f'height="{by - ay:.2f}" rx="{(by - ay) / 2:.2f}"/>'
        )
    lines.append("  </g>")

    # spine + nodes — SVG rect center = x + width/2 must equal spine_cx
    # (unlike PIL, SVG width is exclusive of the right edge)
    spine_x = spine_cx - SPINE_W / 2
    lines.append(
        f'  <rect x="{spine_x}" y="{sy0}" width="{SPINE_W}" height="{sy1 - sy0}" '
        f'rx="{SPINE_W / 2}" fill="{fill("spine")}"/>'
    )
    for ncx, ncy, rad in nodes:
        # same cx as spine geometric center
        lines.append(
            f'  <circle cx="{spine_cx}" cy="{ncy}" r="{rad}" fill="{fill("node")}"/>'
        )

    # code — same arms as the PNG
    stroke_w = _code_stroke_width(mark_size)
    lines.append(
        f'  <g fill="none" stroke="{fill("code")}" stroke-width="{stroke_w}" '
        'stroke-linecap="round" stroke-linejoin="round">'
    )
    for p0, p1 in CODE_ARMS:
        x0, y0 = to_mark(p0[0], p0[1], mark_size)
        x1, y1 = to_mark(p1[0], p1[1], mark_size)
        lines.append(
            f'    <line x1="{x0:.2f}" y1="{y0:.2f}" x2="{x1:.2f}" y2="{y1:.2f}"/>'
        )
    lines.append("  </g>")

    if color:
        lines.append("  </g>")  # close translate

    lines += ["</svg>", ""]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    # Mono activity-bar (full 128, transparent bg — VS Code tints it)
    mono = draw_mark(SIZE, color=False)
    mono_path = ROOT / "activity-bar.png"
    mono.save(mono_path, optimize=True)
    print("saved", mono_path)

    # Color package icon (rounded tile)
    color = draw_color_tile(SIZE)
    color_path = ROOT / "icon.png"
    color.save(color_path, optimize=True)
    print("saved", color_path)

    # Also a color mark without tile (useful for previews)
    color_mark = draw_mark(SIZE, color=True)
    color_mark_path = ROOT / "activity-bar-color.png"
    color_mark.save(color_mark_path, optimize=True)
    print("saved", color_mark_path)

    write_svg(ROOT / "activity-bar.svg", color=False)
    write_svg(ROOT / "icon.svg", color=True)
    write_svg(ASSETS / "logo.svg", color=True)
    write_svg(DOCS / "logo.svg", color=True)  # favicon for the landing page
    write_svg(
        INTELLIJ_RESOURCES / "META-INF" / "pluginIcon.svg",
        color=True,
        width=40,
        height=40,
        gradient_id="grwTile",
    )
    write_svg(
        INTELLIJ_RESOURCES / "META-INF" / "pluginIcon_dark.svg",
        color=True,
        width=40,
        height=40,
        gradient_id="grwTileDark",
        border="#3D4759",
    )
    write_svg(
        INTELLIJ_RESOURCES / "icons" / "gitReviewToolWindow.svg",
        color=False,
        width=16,
        height=16,
        mono="#6C707E",
    )
    write_svg(
        INTELLIJ_RESOURCES / "icons" / "gitReviewToolWindow_dark.svg",
        color=False,
        width=16,
        height=16,
        mono="#CED0D6",
    )
    print("saved SVGs")

    # Center check: for each node row, the opaque run around the node must
    # be symmetric about spine_cx.
    px = mono.load()
    spine_cx = mono.info["spine_cx"]
    for ncx, ncy, rad in mono.info["nodes"]:
        assert ncx == spine_cx
        # horizontal diameter through the node center
        xs = [x for x in range(SIZE) if px[x, ncy][3] > 200]
        # keep only the node blob (contiguous around ncx)
        blob = [x for x in xs if abs(x - ncx) <= rad + 1]
        if blob:
            mid = (min(blob) + max(blob)) / 2
            print(f"node y={ncy}: blob {min(blob)}..{max(blob)} mid={mid:.1f} spine={spine_cx}")
            assert abs(mid - spine_cx) <= 0.5, (mid, spine_cx)

    # previews on dark
    for name, im in (
        ("activity-bar", mono),
        ("activity-bar-color", color_mark),
        ("icon", color),
    ):
        bg = Image.new("RGBA", (SIZE + 48, SIZE + 48), (22, 22, 22, 255))
        bg.paste(im, (24, 24), im)
        bg.save(ROOT / f"_preview-{name}.png")
    print("previews written")


if __name__ == "__main__":
    main()
