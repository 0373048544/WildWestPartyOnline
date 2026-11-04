#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""WWPO card face V5 – update the existing CardView.gd after Hotfix V4.

  python patch_card_layout_v5.py --check
  python patch_card_layout_v5.py

Only modifies scripts/ui/CardView.gd. Makes an untouched backup .before_v5.bak.
Fails safely if required anchors are missing or the output has already been patched.
"""
from pathlib import Path
import argparse
import re
import sys

ap = argparse.ArgumentParser()
ap.add_argument('--check', action='store_true', help='inspect source, do not write')
ap.add_argument('--root', default='.', help='Godot project root')
args = ap.parse_args()
root = Path(args.root).resolve()
path = root / 'scripts/ui/CardView.gd'
if not (root / 'project.godot').is_file() or not path.is_file():
    sys.exit('ERROR: Run from Godot project root (project.godot and CardView.gd required).')
source = path.read_text(encoding='utf-8-sig')
if '# WWPO_CARD_LAYOUT_V5' in source:
    print('ALREADY APPLIED: CardView.gd contains WWPO_CARD_LAYOUT_V5. Nothing changed.')
    sys.exit(0)


def replace_line(pattern, replacement, description, flags=re.M):
    global source
    result, count = re.subn(pattern, lambda m: replacement, source, flags=flags)
    if count != 1:
        raise RuntimeError(f'{description}: expected one match, found {count}. No files changed.')
    source = result
    print('OK:', description)


def replace_block(start, end, replacement, description):
    global source
    a = source.find(start)
    if a < 0 or source.find(start, a + 1) != -1:
        raise RuntimeError(f'{description}: start marker missing or ambiguous. No files changed.')
    b = source.find(end, a + len(start))
    if b < 0:
        raise RuntimeError(f'{description}: end marker missing. No files changed.')
    source = source[:a] + replacement + source[b:]
    print('OK:', description)

try:
    # 1. Header: title left, rank/suit right, exactly like the big preview.
    replace_block(
        '\tvar card_name :=',
        '\tif CardData.is_quick_equipment(',
        '''\t# WWPO_CARD_LAYOUT_V5: card hand and enlarged preview use one header hierarchy.\n\tvar display_name: String = str(definition.get("name", "LÁ BÀI"))\n\tvar card_name := add_text(display_name, Rect2(13, 7, 144, 28), 17, SaloonTheme.CREAM)\n\tcard_name.name = "CardName"\n\tcard_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT\n\tcard_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER\n\tcard_name.autowrap_mode = TextServer.AUTOWRAP_OFF\n\tcard_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS\n\tcard_name.clip_text = true\n\tcard_name.max_lines_visible = 1\n\tcard_name.z_index = 3\n\tvar corner := add_text(CardInstance.corner(card), Rect2(158, 7, 40, 28), 17, CardInstance.suit_color(card.suit))\n\tcorner.name = "RankSuitCorner"\n\tcorner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT\n\tcorner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER\n\tcorner.autowrap_mode = TextServer.AUTOWRAP_OFF\n\tcorner.clip_text = true\n\tcorner.z_index = 3\n''',
        'unify card title and corner')
    replace_line(r'^\tband\.size = Vector2\(198,\s*\d+\)[ \t]*$', '\tband.size = Vector2(198, 33)', 'header background height')
    replace_line(r'^\tband_glint\.position = Vector2\(8,\s*\d+\)[ \t]*$', '\tband_glint.position = Vector2(8, 39)', 'header separator')
    replace_line(r'^\tartwork_frame\.position = Vector2\([^\n]+\)$', '\tartwork_frame.position = Vector2(12, 44)', 'art frame y')
    replace_line(r'^\tartwork_frame\.size = Vector2\([^\n]+\)$', '\tartwork_frame.size = Vector2(186, 89)', 'art frame height')
    replace_line(r'^\tartwork\.size = Vector2\([^\n]+\)$', '\tartwork.size = Vector2(180, 83)', 'art content height')
    replace_line(r'^\ttype_badge\.position = Vector2\([^\n]+\)$', '\ttype_badge.position = Vector2(55, 137)', 'category badge position')
    replace_line(r'^\tvar type_text := add_text\([^\n]+\)$',
                 '\tvar type_text := add_text(TextCatalog.text(CardData.CardType.keys()[definition.type]), Rect2(58, 139, 94, 17), 11, SaloonTheme.CREAM)',
                 'category text position')
    replace_line(r'^\tvar description := add_text\([^\n]+\)$',
                 '\tvar description := add_text(str(definition.get("description", "")), Rect2(12, 164, 186, 43), 12, Color("#29333a"))',
                 'description box')
    replace_line(r'^\tdescription\.max_lines_visible = \d+[ \t]*$',
                 '\tdescription.max_lines_visible = 3\n\tdescription.vertical_alignment = VERTICAL_ALIGNMENT_TOP',
                 'description maximum lines')
    # Last rank/suit duplicates the header and can overlap the description.
    replace_line(r'^\tvar lower := add_text\([^\n]+\)$',
                 '\tvar lower := add_text("", Rect2(145, 190, 54, 20), 14, CardInstance.suit_color(card.suit))',
                 'remove duplicate corner at card bottom')
    # Quick equipment remains available through inspect/preview. Avoid its badge over art.
    replace_line(r'^(\t\tquick_badge\.name = "QuickEquipBadge")$',
                 '\t\tquick_badge.name = "QuickEquipBadge"\n\t\tquick_badge.visible = false',
                 'hide secondary quick equipment badge', re.M)
    replace_line(r'^(\t\tquick_text\.name = "QuickEquipText")$',
                 '\t\tquick_text.name = "QuickEquipText"\n\t\tquick_text.visible = false',
                 'hide secondary quick equipment text', re.M)

    # 2. Phone-specific layout should no longer move suit to the row under artwork.
    # Keep layout dimensions, touch gestures and selected state unchanged.
    replace_block(
        'func touch_compact(width: float) -> void:\n',
        'func draw_symbol(icon: Control) -> void:\n',
        '''func touch_compact(width: float) -> void:\n\ttouch_layout = true\n\tselected_lift = 0.0\n\tcustom_minimum_size = Vector2(width, width * 214.0 / 210.0)\n\tsize = custom_minimum_size\n\tvar touch_scale: float = maxf(0.1, width / 210.0)\n\tvisual.scale = Vector2.ONE * touch_scale * (1.05 if chosen_state else 1.0)\n\tvisual.position = Vector2.ZERO\n\t# Card face stays identical to the desktop face: name/suit above art.\n\tvar card_name: Label = visual.get_node("CardName") as Label\n\tvar corner: Label = visual.get_node("RankSuitCorner") as Label\n\tvar title_size: int = clampi(int(round(14.0 / touch_scale)), 16, 26)\n\tif card_name.text.length() > 13:\n\t\ttitle_size = mini(title_size, 19)\n\tcard_name.add_theme_font_size_override("font_size", title_size)\n\tcard_name.position = Vector2(13, 7)\n\tcard_name.size = Vector2(144, 28)\n\tcard_name.visible = true\n\tcorner.add_theme_font_size_override("font_size", clampi(int(round(13.0 / touch_scale)), 16, 24))\n\tcorner.position = Vector2(158, 7)\n\tcorner.size = Vector2(40, 28)\n\tcorner.visible = true\n\tvar title_band: ColorRect = visual.get_node("TitleBand") as ColorRect\n\ttitle_band.position = Vector2(6, 6)\n\ttitle_band.size = Vector2(198, 33)\n\t# Full descriptions remain readable in the deliberate long-press preview\n\t# on tiny screens. For large phone cards show up to three lines.\n\tvar description: Label = visual.get_node("CardDescription") as Label\n\tdescription.visible = width >= 128.0\n\tif description.visible:\n\t\tdescription.add_theme_font_size_override("font_size", clampi(int(round(11.5 / touch_scale)), 11, 19))\n\t\tdescription.position = Vector2(12, 164)\n\t\tdescription.size = Vector2(186, 43)\n\tvisual.get_node("RankSuitLower").visible = false\n\tvar quick_badge: Control = visual.get_node_or_null("QuickEquipBadge") as Control\n\tvar quick_text: Control = visual.get_node_or_null("QuickEquipText") as Control\n\tif is_instance_valid(quick_badge):\n\t\tquick_badge.visible = false\n\tif is_instance_valid(quick_text):\n\t\tquick_text.visible = false\n\t# Keep original card type and artwork geometry.\n\tmouse_filter = Control.MOUSE_FILTER_STOP\n\n''',
        'unify phone card face')

except RuntimeError as exc:
    sys.exit('PATCH ABORTED SAFELY: ' + str(exc))

if args.check:
    print('\nCHECK PASSED: existing CardView.gd is compatible; no files changed.')
else:
    backup = path.with_suffix(path.suffix + '.before_v5.bak')
    if not backup.exists():
        backup.write_text(path.read_text(encoding='utf-8-sig'), encoding='utf-8')
    path.write_text(source, encoding='utf-8')
    print('\nPATCH APPLIED: scripts/ui/CardView.gd')
    print('BACKUP: scripts/ui/CardView.gd.before_v5.bak')
    print('Review in Godot and test cards on desktop and mobile before commit.')
