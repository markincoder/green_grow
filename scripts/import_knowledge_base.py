# -*- coding: utf-8 -*-
"""Import Excel knowledge base into Flutter plants_data.dart + plant images."""

from __future__ import annotations

import re
from pathlib import Path

import xlrd
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
KB_DIR = ROOT / "базазнаний20260829"
XLS = KB_DIR / "База знаний 20260903.xls"
IMG_SRC = KB_DIR / "jpg_final"
OUT_DART = ROOT / "apps" / "microgreens" / "lib" / "data" / "plants_data.dart"
OUT_ASSETS = ROOT / "apps" / "microgreens" / "assets" / "plants"

# Legacy slug ids → Excel numeric ids (existing garden trays keep working).
LEGACY_ID_BY_NAME = {
    "Амарант": "amaranth",
    "Базилик": "basil_mg",
    "Бораго": "borage",
    "Брокколи": "broccoli",
    "Горох": "pea",
    "Горчица": "mustard",
    "Кинза": "cilantro",
    "Клевер": "clover",
    "Кресс-салат": "cress",
    "Кукуруза": "corn",
    "Мангольд": "chard",
    "Мизуна": "mizuna",
    "Пажитник": "fenugreek",
    "Подсолнечник": "sunflower",
    "Редис": "radish",
    "Репа": "turnip",
    "Рукола": "arugula_mg",
    "Щавель": "sorrel",
}

EMOJI = {
    "Амарант": "🌸",
    "Базилик": "🍃",
    "Бораго": "💧",
    "Брокколи": "🥦",
    "Горох": "🫛",
    "Горчица": "🌿",
    "Дайкон": "🌱",
    "Кейл": "🥬",
    "Кервель": "🌿",
    "Кинза": "🌿",
    "Клевер": "☘️",
    "Кольраби": "🥦",
    "Комацуна": "🥬",
    "Кресс-салат": "✨",
    "Кукуруза": "🌽",
    "Лук": "🧅",
    "Мангольд": "🩸",
    "Мелисса": "🍃",
    "Мизуна": "🥬",
    "Пажитник": "🌿",
    "Пак-чой": "🥬",
    "Перилла/шисо": "🌿",
    "Подсолнечник": "🌻",
    "Редис": "🌱",
    "Редька": "🌱",
    "Репа": "🌱",
    "Рукола": "🥬",
    "Салат": "🥬",
    "Свекла": "🩸",
    "Тат-сой": "🥬",
    "Шпинат": "🥬",
    "Щавель": "🍃",
}


def dart_str(s: str) -> str:
    s = (s or "").strip().replace("\r\n", "\n").replace("\r", "\n")
    s = s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")
    return "'" + s + "'"


def cell(row: list, headers: list[str], *names: str, default=""):
    for name in names:
        try:
            return row[headers.index(name)]
        except ValueError:
            continue
    return default


def parse_range(val):
    if val is None or val == "":
        return None
    if isinstance(val, (int, float)):
        v = float(val)
        return (v, v)
    s = str(val).strip().replace(",", ".").replace("–", "-").replace("—", "-")
    s = re.sub(r"\s+", "", s)
    m = re.match(r"^(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)$", s)
    if m:
        return float(m.group(1)), float(m.group(2))
    m = re.match(r"^(\d+(?:\.\d+)?)$", s)
    if m:
        v = float(m.group(1))
        return v, v
    raise ValueError(f"bad range: {val!r}")


def hours_from_soak(val):
    r = parse_range(val)
    if r is None:
        return None, None
    a, b = int(r[0]), int(r[1])
    if a == 0 and b == 0:
        return None, None
    return a, b


def days_to_hours(val):
    r = parse_range(val)
    if r is None:
        return 0, 0
    return int(r[0]) * 24, int(r[1]) * 24


def days_range(val):
    r = parse_range(val)
    if r is None:
        return None, 0
    return int(r[0]), int(r[1])


def parse_press(val):
    if val is None or val == "":
        return "PressKind.none", None, None
    if isinstance(val, (int, float)):
        v = float(val)
        if v == 0:
            return "PressKind.none", None, None
        return "PressKind.weight", v, v
    s = str(val).strip()
    sl = s.lower()
    if "без" in sl:
        return "PressKind.none", None, None
    if "верхн" in sl or "лотк" in sl:
        return "PressKind.upperTray", None, None
    s_norm = s.replace(",", ".").replace("–", "-").replace("—", "-")
    m = re.search(r"(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)", s_norm)
    if m:
        return "PressKind.weight", float(m.group(1)), float(m.group(2))
    m = re.search(r"(\d+(?:\.\d+)?)", s_norm)
    if m:
        v = float(m.group(1))
        return "PressKind.weight", v, v
    return "PressKind.none", None, None


def join_dot(*parts) -> str:
    bits = []
    for p in parts:
        t = str(p or "").strip()
        if not t:
            continue
        t = t.replace("\r\n", "\n").replace("\r", "\n").strip().rstrip(".")
        bits.append(t)
    return ". ".join(bits)


def tags_from(val):
    if not val:
        return []
    parts = re.split(r"[,;\n]+", str(val))
    out = []
    for p in parts:
        t = p.strip().lower()
        if t and t != "польза" and t not in out:
            out.append(t)
    return out


def fmt_num(v):
    if v is None:
        return "null"
    if float(v).is_integer():
        return str(int(v))
    return str(v)


def format_temperature(val) -> str:
    s = str(val or "").strip()
    if not s:
        return "18–22 °C"
    s = s.replace(",", ".").replace("–", "-").replace("—", "-")
    s = re.sub(r"\s+", "", s)
    s = s.replace("-", "–")
    if "°" not in s and "C" not in s.upper():
        s = f"{s} °C"
    return s


def resize_save(src: Path, dest: Path, max_w: int, max_h: int, quality=82):
    im = Image.open(src).convert("RGB")
    im.thumbnail((max_w, max_h), Image.Resampling.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest, "JPEG", quality=quality, optimize=True)


def find_source(prefix: str, n: int) -> Path | None:
    for folder in (IMG_SRC, OUT_ASSETS):
        for ext in (".png", ".jpg", ".jpeg", ".PNG", ".JPG"):
            cand = folder / f"{prefix}{n}{ext}"
            if cand.exists():
                return cand
    return None


def collect_plant_images(prefix: str) -> list[str]:
    """Copy/compress prefix1, prefix2, … into assets/plants as JPEG."""
    images: list[str] = []
    for n in range(1, 21):
        dest = OUT_ASSETS / f"{prefix}{n}.jpg"
        src = find_source(prefix, n)
        if src is not None and src.parent == IMG_SRC:
            resize_save(src, dest, 900, 900)
            images.append(f"assets/plants/{prefix}{n}.jpg")
            continue
        if dest.exists() and dest.stat().st_size > 0:
            images.append(f"assets/plants/{prefix}{n}.jpg")
            continue
        if src is None:
            break
        if src.resolve() == dest.resolve():
            images.append(f"assets/plants/{prefix}{n}.jpg")
            continue
        # Phone/tablet: 900px covers ~3x phone and ~2x tablet for card width.
        resize_save(src, dest, 900, 900)
        if src.suffix.lower() == ".png" and src.parent == OUT_ASSETS:
            src.unlink(missing_ok=True)
        images.append(f"assets/plants/{prefix}{n}.jpg")
    return images


def main() -> None:
    OUT_ASSETS.mkdir(parents=True, exist_ok=True)
    wb = xlrd.open_workbook(str(XLS))
    sh = wb.sheet_by_index(0)
    headers = [str(sh.cell_value(0, c)).strip() for c in range(sh.ncols)]

    plants = []
    aliases: dict[str, str] = {}
    copied = []
    for r in range(1, sh.nrows):
        row = [sh.cell_value(r, c) for c in range(sh.ncols)]
        name = str(cell(row, headers, "Название")).strip()
        if not name:
            continue
        excel_id = str(int(float(cell(row, headers, "id"))))
        prefix = str(cell(row, headers, "Префикс для фото")).strip()
        plant_id = excel_id
        legacy = LEGACY_ID_BY_NAME.get(name)
        if legacy and legacy != plant_id:
            aliases[legacy] = plant_id

        images = collect_plant_images(prefix)
        copied.extend(Path(p).name for p in images)

        seed = parse_range(
            cell(
                row,
                headers,
                "Вес семян на лоток 18*13 см",
                "Вес семян на лоток 19*11 или 18*13 см",
                "Семена вес на лоток 13см*18см",
                "Вес семян на лоток 13*18 см",
            )
        )
        if seed is None:
            raise ValueError(f"{name}: missing seed weight")

        soak_min, soak_max = hours_from_soak(cell(row, headers, "Замачивание, ч"))
        g_min, g_max = days_to_hours(cell(row, headers, "Проращивание, дней"))
        grow_min, grow_max = days_range(cell(row, headers, "Рост, дней"))
        cycle_min, cycle_max = days_range(cell(row, headers, "Полный цикл, дней"))
        press_kind, pmin, pmax = parse_press(
            cell(row, headers, "Проращивание, прижим", "Прижим, кг")
        )
        germinate_note = join_dot(
            cell(row, headers, "Проращивание, свет"),
            cell(row, headers, "Проращивание, прижим"),
        )
        grow_note = join_dot(
            cell(row, headers, "Рост, свет"),
            cell(row, headers, "Рост, полив"),
        )

        tags = tags_from(cell(row, headers, "Для фильтров"))
        desc = str(cell(row, headers, "Описание") or "").strip()
        taste = str(cell(row, headers, "Вкус") or "").strip() or None
        feature = (
            str(cell(row, headers, "Особенности выращивания") or "").strip() or None
        )
        tray = str(cell(row, headers, "Лоток") or "").strip() or None
        soil = str(cell(row, headers, "Субстрат") or "").strip() or "Кокос"
        light = str(cell(row, headers, "Свет") or "").strip() or "Стандартный свет"
        storage = str(cell(row, headers, "Хранение") or "").strip() or None
        temperature = join_dot(
            format_temperature(cell(row, headers, "Температура")),
            cell(row, headers, "Влажность воздуха", "Влажность"),
        )

        tips = []
        if soak_min is None:
            tips.append("Замачивание не нужно.")
        else:
            if soak_min == soak_max:
                tips.append(f"Замочите на {soak_min} ч.")
            else:
                tips.append(f"Замочите на {soak_min}–{soak_max} ч.")
        if g_max == 0:
            tips.append("Тёмная фаза не нужна.")
        else:
            d1, d2 = g_min // 24, g_max // 24
            span = f"{d1}–{d2}" if d1 != d2 else str(d1)
            if press_kind == "PressKind.none":
                tips.append(
                    f"Проращивание под плёнкой/крышкой {span} дн., без прижима."
                )
            elif press_kind == "PressKind.upperTray":
                tips.append(
                    f"Проращивание в темноте {span} дн., прижим верхним лотком."
                )
            else:
                kg = (
                    fmt_num(pmin)
                    if pmin == pmax
                    else f"{fmt_num(pmin)}–{fmt_num(pmax)}"
                )
                tips.append(
                    f"Проращивание в темноте {span} дн. с прижимом {kg} кг."
                )
        if grow_max and grow_max > 0:
            if grow_min != grow_max:
                tips.append(f"На свету {grow_min}–{grow_max} дн.")
            else:
                tips.append(f"На свету {grow_max} дн.")
        if feature:
            tips.append(feature)

        plants.append(
            {
                "id": plant_id,
                "name": name,
                "description": desc,
                "icon": EMOJI.get(name, "🌱"),
                "images": images,
                "seed_min": seed[0],
                "seed_max": seed[1],
                "soak_min": soak_min,
                "soak_max": soak_max,
                "g_min": g_min,
                "g_max": g_max,
                "press_kind": press_kind,
                "pmin": pmin,
                "pmax": pmax,
                "grow_min": grow_min,
                "grow_max": grow_max,
                "cycle_min": cycle_min,
                "cycle_max": cycle_max,
                "light": light,
                "temperature": temperature,
                "soil": soil,
                "tips": tips,
                "tags": tags,
                "taste": taste,
                "storage": storage,
                "tray": tray,
                "feature": feature,
                "germinate_note": germinate_note,
                "grow_note": grow_note,
            }
        )

    tag_set: set[str] = set()
    for p in plants:
        tag_set.update(p["tags"])
    tag_order = ["быстро", "быстрый", "яркий вкус", "эффектно", "эффектный"]
    filter_tags = [t for t in tag_order if t in tag_set]
    filter_tags.extend(sorted(tag_set - set(filter_tags)))

    lines = [
        "import '../models/plant.dart';",
        "",
        "/// Hours for a dark-germination range given in days.",
        "int _d(int days) => days * 24;",
        "",
        "/// Filter chips for the knowledge base (from Excel «Для фильтров»).",
        "const catalogFilterTags = <String>[",
    ]
    for tag in filter_tags:
        lines.append(f"  {dart_str(tag)},")
    lines.extend(
        [
            "];",
            "",
            "/// Old slug ids → Excel numeric ids (saved garden trays).",
            "const _plantIdAliases = <String, String>{",
        ]
    )
    for legacy, numeric in sorted(aliases.items(), key=lambda x: x[1]):
        lines.append(f"  {dart_str(legacy)}: {dart_str(numeric)},")
    lines.extend(
        [
            "};",
            "",
            "final plantsCatalog = <Plant>[",
        ]
    )

    for p in plants:
        lines.append("  Plant(")
        lines.append(f"    id: {dart_str(p['id'])},")
        lines.append(f"    name: {dart_str(p['name'])},")
        lines.append(f"    description: {dart_str(p['description'])},")
        lines.append(f"    icon: {dart_str(p['icon'])},")
        if p["images"]:
            imgs = ", ".join(dart_str(i) for i in p["images"])
            lines.append(f"    images: [{imgs}],")
        lines.append(f"    seedGramsMin: {fmt_num(p['seed_min'])},")
        lines.append(f"    seedGramsMax: {fmt_num(p['seed_max'])},")
        if p["soak_min"] is not None:
            lines.append(f"    soakHoursMin: {p['soak_min']},")
            lines.append(f"    soakHoursMax: {p['soak_max']},")
        d1, d2 = p["g_min"] // 24, p["g_max"] // 24
        lines.append(f"    germinateHoursMin: _d({d1}),")
        lines.append(f"    germinateHoursMax: _d({d2}),")
        if p["press_kind"] != "PressKind.none":
            lines.append(f"    pressKind: {p['press_kind']},")
        if p["press_kind"] == "PressKind.weight":
            lines.append(f"    pressKgMin: {fmt_num(p['pmin'])},")
            lines.append(f"    pressKgMax: {fmt_num(p['pmax'])},")
        if p["grow_max"] and p["grow_min"] != p["grow_max"]:
            lines.append(f"    growDaysMin: {p['grow_min']},")
        lines.append(f"    growDays: {p['grow_max'] or 0},")
        if p["cycle_max"]:
            if p["cycle_min"] != p["cycle_max"]:
                lines.append(f"    fullCycleDaysMin: {p['cycle_min']},")
            lines.append(f"    fullCycleDaysMax: {p['cycle_max']},")
        lines.append(f"    light: {dart_str(p['light'])},")
        lines.append(f"    temperature: {dart_str(p['temperature'])},")
        lines.append(f"    soil: {dart_str(p['soil'])},")
        lines.append("    tips: [")
        for t in p["tips"]:
            lines.append(f"      {dart_str(t)},")
        lines.append("    ],")
        if p["tags"]:
            tags_lit = ", ".join(dart_str(t) for t in p["tags"])
            lines.append(f"    tags: [{tags_lit}],")
        else:
            lines.append("    tags: const [],")
        if p["taste"]:
            lines.append(f"    taste: {dart_str(p['taste'])},")
        if p["storage"]:
            lines.append(f"    storage: {dart_str(p['storage'])},")
        if p["tray"]:
            lines.append(f"    tray: {dart_str(p['tray'])},")
        if p["feature"]:
            lines.append(f"    feature: {dart_str(p['feature'])},")
        if p["germinate_note"]:
            lines.append(f"    germinateNote: {dart_str(p['germinate_note'])},")
        if p["grow_note"]:
            lines.append(f"    growNote: {dart_str(p['grow_note'])},")
        lines.append("  ),")

    lines.extend(
        [
            "];",
            "",
            "Plant? plantById(String id) {",
            "  final resolved = _plantIdAliases[id] ?? id;",
            "  for (final plant in plantsCatalog) {",
            "    if (plant.id == resolved) return plant;",
            "  }",
            "  return null;",
            "}",
            "",
        ]
    )

    OUT_DART.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {OUT_DART} with {len(plants)} plants")
    print("Images:", ", ".join(sorted(set(copied))))
    print("Aliases:", aliases)
    for p in plants:
        print(f"  {p['id']}: {p['name']}".encode("utf-8", "replace").decode("utf-8"))


if __name__ == "__main__":
    main()
