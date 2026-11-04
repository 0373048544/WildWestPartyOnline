#!/usr/bin/env python3
"""Render the in-hand card header with the same fixed geometry as preview.
Run in the Godot project root with --check first. Only changes CardView.gd.
"""
from pathlib import Path
import argparse
import shutil
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
parser.add_argument('--project', default='.')
args = parser.parse_args()
root = Path(args.project).resolve()
file = root / 'scripts/ui/CardView.gd'
if not (root / 'project.godot').exists() or not file.exists():
    sys.exit('ERROR: run from the Godot project root.')
original = file.read_text(encoding='utf-8-sig')
if 'WWPO_HAND_PREVIEW_HEADER_V6' in original:
    sys.exit('ALREADY APPLIED: V6 is already present.')
if not all(t in original for t in ('func configure(', 'func touch_compact(', 'card_name.name = "CardName"', 'corner.name = "RankSuitCorner"', 'var title_band: ColorRect')):
    sys.exit('ABORT: unexpected CardView.gd; no files changed.')
anchor = '\tcorner.name = "RankSuitCorner"'
position = original.find(anchor)
cut = original.find('\n\tif CardData.is_quick_equipment(', position)
if position < 0 or cut < 0:
    sys.exit('ABORT: header insertion point not found; no files changed.')
insert = '''
	# WWPO_HAND_PREVIEW_HEADER_V6
	# Fixed text drawing prevents font intrinsic-minimum changes from pushing
	# the Vietnamese title into the artwork after compact/touch scaling.
	card_name.visible = false
	corner.visible = false
	var header_paint := Control.new()
	header_paint.name = "PreviewStyleHeader"
	header_paint.position = Vector2(6.0, 5.0)
	header_paint.size = Vector2(198.0, 34.0)
	header_paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_paint.z_index = 12
	visual.add_child(header_paint)
	var header_name: String = display_name if not display_name.is_empty() else "LÁ BÀI"
	var header_corner: String = CardInstance.corner(card)
	var header_font: Font = get_theme_default_font()
	header_paint.draw.connect(func() -> void:
		var title_size: int = 17
		while title_size > 11 and header_font.get_string_size(header_name, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > 137.0:
			title_size -= 1
		header_paint.draw_string(header_font, Vector2(8.0, 24.0), header_name, HORIZONTAL_ALIGNMENT_LEFT, 140.0, title_size, SaloonTheme.CREAM)
		header_paint.draw_string(header_font, Vector2(150.0, 24.0), header_corner, HORIZONTAL_ALIGNMENT_RIGHT, 39.0, 16, SaloonTheme.CREAM)
	)
'''
patched = original[:cut] + insert + original[cut:]
start = patched.find('\nfunc touch_compact(')
end = patched.find('\nfunc ', start + 2)
if start < 0:
    sys.exit('ABORT: touch layout function missing; no files changed.')
if end < 0:
    end = len(patched)
touch = patched[start:end]
touch = touch.replace('\tcard_name.visible = true', '\tcard_name.visible = false')
touch = touch.replace('\tcorner.visible = true', '\tcorner.visible = false')
patched = patched[:start] + touch + patched[end:]
patched = patched.replace('band.color = accent.darkened(0.10) if usable else accent.darkened(0.38)', 'band.color = Color("#8a7040") if usable else Color("#6f6653")')
if patched == original:
    sys.exit('ABORT: no applicable changes.')
if args.check:
    print('CHECK PASSED: local CardView.gd supports V6; no files changed.')
else:
    backup = file.with_name('CardView.gd.before_v6.bak')
    if not backup.exists():
        shutil.copy2(file, backup)
    file.write_text(patched, encoding='utf-8')
    print('PATCH APPLIED: scripts/ui/CardView.gd')
    print('Backup:', backup.name)
    print('Open Godot, inspect card header, and run UI tests before pushing.')
