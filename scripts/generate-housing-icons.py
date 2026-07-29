#!/usr/bin/env python3
"""Generate BFInfinite's original Housing Catalog icon family.

The artwork is constructed from simple geometric primitives on a 64-unit
design grid, rasterized at 8x, and downsampled for clean in-game edges.
No third-party artwork or source data is embedded; external icon collections
were used only as broad visual references for a flat, modern direction.
Pillow is required only when regenerating the checked-in TGA assets. The
checked-in output is known to reproduce byte-for-byte with Pillow 11.3.0.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw


SOURCE_SIZE = 512
OUTPUT_SIZE = 64
SCALE = SOURCE_SIZE / OUTPUT_SIZE
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "Media" / "Icons"


class IconCanvas:
    def __init__(self) -> None:
        self.image = Image.new("RGBA", (SOURCE_SIZE, SOURCE_SIZE), CLEAR)
        self.draw = ImageDraw.Draw(self.image)

    @staticmethod
    def _n(value: float) -> int:
        return round(value * SCALE)

    def line(
        self,
        points: list[tuple[float, float]],
        width: float = 4.5,
        fill: tuple[int, int, int, int] = WHITE,
        rounded: bool = True,
    ) -> None:
        scaled = [(self._n(x), self._n(y)) for x, y in points]
        line_width = self._n(width)
        self.draw.line(scaled, fill=fill, width=line_width, joint="curve")
        if rounded:
            radius = line_width / 2
            for x, y in (scaled[0], scaled[-1]):
                self.draw.ellipse(
                    (round(x - radius), round(y - radius), round(x + radius), round(y + radius)),
                    fill=fill,
                )

    def rect(
        self,
        box: tuple[float, float, float, float],
        *,
        radius: float = 0,
        fill: tuple[int, int, int, int] | None = None,
        outline: tuple[int, int, int, int] | None = WHITE,
        width: float = 4.5,
    ) -> None:
        scaled = tuple(self._n(value) for value in box)
        if radius:
            self.draw.rounded_rectangle(
                scaled,
                radius=self._n(radius),
                fill=fill,
                outline=outline,
                width=self._n(width),
            )
        else:
            self.draw.rectangle(scaled, fill=fill, outline=outline, width=self._n(width))

    def ellipse(
        self,
        box: tuple[float, float, float, float],
        *,
        fill: tuple[int, int, int, int] | None = None,
        outline: tuple[int, int, int, int] | None = WHITE,
        width: float = 4.5,
    ) -> None:
        self.draw.ellipse(
            tuple(self._n(value) for value in box),
            fill=fill,
            outline=outline,
            width=self._n(width),
        )

    def polygon(
        self,
        points: list[tuple[float, float]],
        fill: tuple[int, int, int, int] = WHITE,
    ) -> None:
        self.draw.polygon([(self._n(x), self._n(y)) for x, y in points], fill=fill)

    def arc(
        self,
        box: tuple[float, float, float, float],
        start: float,
        end: float,
        *,
        width: float = 4.5,
        fill: tuple[int, int, int, int] = WHITE,
    ) -> None:
        self.draw.arc(
            tuple(self._n(value) for value in box),
            start=start,
            end=end,
            fill=fill,
            width=self._n(width),
        )

    def save(self, name: str) -> None:
        output = self.image.resize(
            (OUTPUT_SIZE, OUTPUT_SIZE),
            resample=Image.Resampling.LANCZOS,
        )
        output.save(OUTPUT_DIR / f"{name}.tga", compression="tga_rle")


def star_points(cx: float, cy: float, outer: float, inner: float, count: int = 5) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for index in range(count * 2):
        angle = -math.pi / 2 + index * math.pi / count
        radius = outer if index % 2 == 0 else inner
        points.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    return points


def draw_all(c: IconCanvas) -> None:
    for x in (10, 34):
        for y in (10, 34):
            c.rect((x, y, x + 20, y + 20), radius=3, width=4)


def draw_featured(c: IconCanvas) -> None:
    c.polygon(star_points(32, 32, 24, 10.5))


def draw_rooms(c: IconCanvas) -> None:
    c.line([(12, 12), (52, 12), (52, 52), (38, 52)], width=5)
    c.line([(26, 52), (12, 52), (12, 12)], width=5)
    c.line([(32, 12), (32, 34), (52, 34)], width=5)
    c.line([(27, 46), (27, 52)], width=4)


def draw_furnishings(c: IconCanvas) -> None:
    c.rect((13, 20, 51, 42), radius=7, fill=WHITE, outline=None)
    c.rect((8, 29, 18, 49), radius=4, fill=WHITE, outline=None)
    c.rect((46, 29, 56, 49), radius=4, fill=WHITE, outline=None)
    c.rect((14, 38, 50, 51), radius=3, fill=WHITE, outline=None)
    c.rect((14, 48, 19, 55), radius=1, fill=WHITE, outline=None)
    c.rect((45, 48, 50, 55), radius=1, fill=WHITE, outline=None)
    c.line([(32, 22), (32, 38)], width=3, fill=CLEAR, rounded=False)


def draw_seating(c: IconCanvas) -> None:
    c.rect((14, 14, 50, 40), radius=10, width=5)
    c.rect((9, 30, 18, 51), radius=4, fill=WHITE, outline=None)
    c.rect((46, 30, 55, 51), radius=4, fill=WHITE, outline=None)
    c.line([(16, 44), (48, 44)], width=5)
    c.line([(18, 49), (16, 55)], width=4)
    c.line([(46, 49), (48, 55)], width=4)


def draw_beds(c: IconCanvas) -> None:
    c.rect((9, 17, 16, 54), radius=2, fill=WHITE, outline=None)
    c.rect((14, 29, 55, 47), radius=4, width=5)
    c.rect((18, 32, 30, 41), radius=3, fill=WHITE, outline=None)
    c.line([(15, 47), (55, 47)], width=5)
    c.line([(51, 47), (51, 54)], width=4)


def draw_tables(c: IconCanvas) -> None:
    c.rect((8, 19, 56, 29), radius=3, fill=WHITE, outline=None)
    c.line([(16, 28), (14, 54)], width=5)
    c.line([(48, 28), (50, 54)], width=5)
    c.rect((24, 31, 40, 41), radius=2, width=3.5)


def draw_storage(c: IconCanvas) -> None:
    c.rect((15, 9, 49, 55), radius=3, width=5)
    c.line([(16, 31), (48, 31)], width=4)
    c.ellipse((29, 22, 35, 28), fill=WHITE, outline=None)
    c.ellipse((29, 38, 35, 44), fill=WHITE, outline=None)
    c.line([(22, 54), (20, 58)], width=4)
    c.line([(42, 54), (44, 58)], width=4)


def draw_structural(c: IconCanvas) -> None:
    c.rect((10, 9, 54, 18), radius=2, fill=WHITE, outline=None)
    c.rect((13, 17, 22, 55), radius=1, fill=WHITE, outline=None)
    c.rect((42, 17, 51, 55), radius=1, fill=WHITE, outline=None)
    c.arc((20, 18, 44, 48), 180, 360, width=6)
    c.line([(22, 33), (22, 54)], width=5)
    c.line([(42, 33), (42, 54)], width=5)


def draw_doors(c: IconCanvas) -> None:
    c.rect((15, 8, 49, 56), radius=2, width=5)
    c.rect((22, 14, 45, 56), radius=1, width=4)
    c.ellipse((37, 33, 43, 39), fill=WHITE, outline=None)


def draw_construction(c: IconCanvas) -> None:
    c.rect((8, 13, 56, 53), radius=2, width=4)
    for y in (26, 39):
        c.line([(10, y), (54, y)], width=3.5)
    c.line([(24, 14), (24, 26)], width=3.5)
    c.line([(42, 14), (42, 26)], width=3.5)
    c.line([(17, 27), (17, 39)], width=3.5)
    c.line([(34, 27), (34, 39)], width=3.5)
    c.line([(26, 40), (26, 52)], width=3.5)
    c.line([(45, 40), (45, 52)], width=3.5)


def draw_windows(c: IconCanvas) -> None:
    c.rect((11, 9, 53, 55), radius=3, width=5)
    c.line([(32, 11), (32, 53)], width=4)
    c.line([(13, 32), (51, 32)], width=4)


def draw_large_structures(c: IconCanvas) -> None:
    c.polygon([(7, 24), (32, 8), (57, 24), (52, 29), (12, 29)])
    c.rect((12, 27, 18, 55), fill=WHITE, outline=None)
    c.rect((29, 27, 35, 55), fill=WHITE, outline=None)
    c.rect((46, 27, 52, 55), fill=WHITE, outline=None)
    c.rect((8, 52, 56, 57), radius=2, fill=WHITE, outline=None)


def draw_accents(c: IconCanvas) -> None:
    # A decorative cushion keeps Accents distinct from Featured's star.
    c.rect((11, 13, 53, 51), radius=10, width=5)
    c.polygon([(32, 22), (42, 32), (32, 42), (22, 32)])
    c.ellipse((29, 29, 35, 35), fill=CLEAR, outline=None)


def draw_ornamental(c: IconCanvas) -> None:
    # Broad handles and shoulders make this read as an amphora at small sizes.
    c.rect((25, 8, 39, 16), radius=2, fill=WHITE, outline=None)
    c.polygon([(25, 14), (39, 14), (39, 23), (47, 31), (48, 43), (42, 54), (22, 54), (16, 43), (17, 31), (25, 23)])
    c.ellipse((10, 24, 25, 45), width=4)
    c.ellipse((39, 24, 54, 45), width=4)
    c.ellipse((25, 31, 39, 48), fill=CLEAR, outline=None)


def draw_wall_hangings(c: IconCanvas) -> None:
    c.rect((9, 11, 55, 53), radius=3, width=5)
    c.ellipse((17, 19, 27, 29), fill=WHITE, outline=None)
    c.line([(14, 46), (26, 34), (34, 41), (43, 31), (51, 46)], width=4)


def draw_food_drink(c: IconCanvas) -> None:
    c.rect((12, 18, 39, 45), radius=5, width=5)
    c.arc((32, 22, 52, 41), 270, 90, width=5)
    c.line([(16, 51), (48, 51)], width=5)
    c.line([(19, 12), (23, 17)], width=3.5)
    c.line([(31, 10), (31, 16)], width=3.5)


def draw_floor(c: IconCanvas) -> None:
    c.polygon([(14, 16), (50, 16), (57, 48), (7, 48)])
    c.polygon([(18, 22), (46, 22), (51, 42), (13, 42)], fill=CLEAR)
    for x in (13, 22, 32, 42, 51):
        c.line([(x, 49), (x, 55)], width=3)


def draw_lighting(c: IconCanvas) -> None:
    c.ellipse((18, 11, 46, 39), width=5)
    c.line([(24, 35), (28, 44), (36, 44), (40, 35)], width=5)
    c.line([(27, 51), (37, 51)], width=5)
    for start, end in (
        ((32, 10), (32, 7)),
        ((12, 15), (8, 12)),
        ((52, 15), (56, 12)),
    ):
        c.line([start, end], width=4)


def draw_large_lights(c: IconCanvas) -> None:
    c.line([(32, 26), (32, 54)], width=5)
    c.polygon([(18, 10), (46, 10), (52, 29), (12, 29)])
    c.line([(18, 55), (46, 55)], width=5)


def draw_wall_lights(c: IconCanvas) -> None:
    c.rect((10, 17, 17, 47), radius=2, fill=WHITE, outline=None)
    c.line([(16, 33), (27, 33), (33, 27)], width=5)
    c.ellipse((31, 16, 49, 34), fill=WHITE, outline=None)
    c.line([(51, 19), (55, 15)], width=3.5)
    c.line([(52, 30), (57, 32)], width=3.5)


def draw_ceiling_lights(c: IconCanvas) -> None:
    c.line([(10, 9), (54, 9)], width=5)
    c.line([(32, 10), (32, 26)], width=4)
    c.polygon([(19, 25), (45, 25), (52, 43), (12, 43)])
    c.line([(18, 49), (46, 49)], width=4)


def draw_small_lights(c: IconCanvas) -> None:
    c.arc((21, 8, 43, 29), 180, 360, width=4)
    c.rect((17, 21, 47, 55), radius=4, width=5)
    c.line([(19, 29), (45, 29)], width=4)
    c.polygon([(32, 35), (38, 45), (32, 51), (26, 45)])


def draw_functional(c: IconCanvas) -> None:
    points: list[tuple[float, float]] = []
    for tooth in range(8):
        center_angle = -math.pi / 2 + tooth * math.pi / 4
        for offset, radius in ((-0.19, 18), (-0.13, 24), (0.13, 24), (0.19, 18)):
            angle = center_angle + offset
            points.append((32 + math.cos(angle) * radius, 32 + math.sin(angle) * radius))
    c.polygon(points)
    c.ellipse((24, 24, 40, 40), fill=CLEAR, outline=None)


def draw_utility(c: IconCanvas) -> None:
    c.line([(15, 14), (50, 51)], width=7)
    c.polygon([(9, 8), (20, 11), (22, 20), (16, 25), (8, 20)])
    c.line([(49, 11), (16, 52)], width=6)
    c.rect((43, 7, 54, 17), radius=3, fill=WHITE, outline=None)


def draw_nature(c: IconCanvas) -> None:
    c.polygon([(9, 34), (18, 17), (35, 8), (55, 10), (52, 30), (43, 47), (24, 55)])
    c.line([(17, 50), (45, 18)], width=4, fill=CLEAR)
    c.line([(28, 39), (20, 31)], width=3, fill=CLEAR)
    c.line([(36, 30), (45, 30)], width=3, fill=CLEAR)


def draw_large_foliage(c: IconCanvas) -> None:
    c.ellipse((17, 7, 47, 34), fill=WHITE, outline=None)
    c.ellipse((8, 19, 36, 45), fill=WHITE, outline=None)
    c.ellipse((29, 18, 56, 44), fill=WHITE, outline=None)
    c.rect((28, 34, 36, 56), radius=2, fill=WHITE, outline=None)
    c.line([(32, 41), (20, 31)], width=4)
    c.line([(32, 39), (44, 29)], width=4)


def draw_small_foliage(c: IconCanvas) -> None:
    c.polygon([(31, 37), (19, 25), (13, 13), (27, 16), (34, 31)])
    c.polygon([(33, 35), (40, 16), (53, 10), (50, 27), (38, 39)])
    c.line([(32, 16), (32, 43)], width=4)
    c.polygon([(17, 40), (47, 40), (42, 56), (22, 56)])


def draw_bushes(c: IconCanvas) -> None:
    c.ellipse((9, 27, 28, 46), fill=WHITE, outline=None)
    c.ellipse((17, 17, 38, 42), fill=WHITE, outline=None)
    c.ellipse((31, 20, 51, 43), fill=WHITE, outline=None)
    c.ellipse((40, 30, 57, 47), fill=WHITE, outline=None)
    c.rect((29, 39, 35, 53), radius=2, fill=WHITE, outline=None)
    c.line([(11, 54), (53, 54)], width=4)


def draw_ground_cover(c: IconCanvas) -> None:
    c.arc((9, 25, 33, 57), 278, 356, width=6)
    c.arc((16, 12, 42, 58), 275, 350, width=6)
    c.arc((29, 20, 53, 57), 188, 265, width=6)
    c.arc((37, 31, 57, 57), 188, 260, width=6)
    c.line([(10, 55), (54, 55)], width=5)


def draw_vines(c: IconCanvas) -> None:
    c.line([(20, 8), (20, 50)], width=4)
    c.line([(44, 8), (44, 45)], width=4)
    c.line([(20, 50), (27, 56)], width=4)
    c.line([(44, 45), (38, 53)], width=4)
    for box in ((9, 17, 21, 28), (19, 31, 31, 42), (33, 14, 45, 25), (42, 28, 54, 39)):
        c.ellipse(box, fill=WHITE, outline=None)


def draw_pet_beds(c: IconCanvas) -> None:
    c.ellipse((8, 31, 56, 55), fill=WHITE, outline=None)
    c.ellipse((14, 35, 50, 48), fill=CLEAR, outline=None)
    c.ellipse((27, 17, 37, 29), fill=WHITE, outline=None)
    c.ellipse((17, 19, 25, 27), fill=WHITE, outline=None)
    c.ellipse((39, 19, 47, 27), fill=WHITE, outline=None)
    c.ellipse((21, 10, 29, 19), fill=WHITE, outline=None)
    c.ellipse((35, 10, 43, 19), fill=WHITE, outline=None)


def draw_misc(c: IconCanvas) -> None:
    c.ellipse((8, 29, 26, 47), fill=WHITE, outline=None)
    c.rect((24, 10, 42, 28), radius=4, fill=WHITE, outline=None)
    c.polygon([(38, 53), (49, 31), (59, 53)])


ICONS = {
    "Housing_Accents": draw_accents,
    "Housing_All": draw_all,
    "Housing_Beds": draw_beds,
    "Housing_Bushes": draw_bushes,
    "Housing_CeilingLights": draw_ceiling_lights,
    "Housing_Construction": draw_construction,
    "Housing_Doors": draw_doors,
    "Housing_Featured": draw_featured,
    "Housing_Floor": draw_floor,
    "Housing_FoodDrink": draw_food_drink,
    "Housing_Functional": draw_functional,
    "Housing_Furnishings": draw_furnishings,
    "Housing_GroundCover": draw_ground_cover,
    "Housing_LargeFoliage": draw_large_foliage,
    "Housing_LargeLights": draw_large_lights,
    "Housing_LargeStructures": draw_large_structures,
    "Housing_Lighting": draw_lighting,
    "Housing_Misc": draw_misc,
    "Housing_Nature": draw_nature,
    "Housing_Ornamental": draw_ornamental,
    "Housing_PetBeds": draw_pet_beds,
    "Housing_Rooms": draw_rooms,
    "Housing_Seating": draw_seating,
    "Housing_SmallFoliage": draw_small_foliage,
    "Housing_SmallLights": draw_small_lights,
    "Housing_Storage": draw_storage,
    "Housing_Structural": draw_structural,
    "Housing_Tables": draw_tables,
    "Housing_Utility": draw_utility,
    "Housing_Vines": draw_vines,
    "Housing_WallHangings": draw_wall_hangings,
    "Housing_WallLights": draw_wall_lights,
    "Housing_Windows": draw_windows,
}


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, draw_icon in ICONS.items():
        canvas = IconCanvas()
        draw_icon(canvas)
        canvas.save(name)
    print(f"Generated {len(ICONS)} Housing icons in {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
