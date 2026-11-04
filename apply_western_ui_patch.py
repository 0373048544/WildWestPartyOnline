#!/usr/bin/env python3
"""Safe patch for WildWestPartyOnline. Run in project root with --check first."""
from pathlib import Path
import sys

check = '--check' in sys.argv
root = Path.cwd()
if not (root / 'project.godot').exists():
    raise SystemExit('Run from the Godot project root (project.godot required).')

def rep(s, a, b, tag):
    n = s.count(a)
    if n != 1:
        raise RuntimeError(f'{tag}: expected 1 source match, got {n}; no files changed.')
    return s.replace(a, b, 1)

changes = {}
p = root / 'scripts/ui/CardView.gd'
s = p.read_text(encoding='utf-8')
s = rep(s, 'var source_title_font: int = mini(38, maxi(17, ceili(desired_title_font / touch_scale)))', 'var source_title_font: int = mini(26, maxi(17, ceili(desired_title_font / touch_scale)))', 'Mobile card title size')
s = rep(s, 'var source_title_height: float = minf(52.0, maxf(34.0, desired_title_height / touch_scale))', 'var source_title_height: float = 31.0', 'Mobile title safe height')
s = rep(s, 'card_name.position = Vector2(8.0, 5.0)', 'card_name.position = Vector2(10.0, 5.0)', 'Mobile title position')
s = rep(s, 'title_band.size = Vector2(198.0, minf(55.0, source_title_height + 3.0))', 'title_band.size = Vector2(198.0, 32.0)', 'Mobile title background')
changes[p] = s

p = root / 'scripts/ui/MatchHUD.gd'
s = p.read_text(encoding='utf-8')
s = rep(s, 'var preview_height: float = (176.0 if not reason.is_empty() else 150.0) * unit', 'var preview_height: float = (292.0 if not reason.is_empty() else 264.0) * unit', 'Preview height')
s = rep(s, 'preview.name = "CardPreview"\n\tpreview.mouse_filter', 'preview.name = "CardPreview"\n\tpreview.clip_contents = true\n\tpreview.mouse_filter', 'Preview clip')
s = rep(s, 'card_name.add_theme_font_size_override("font_size", int(18.0 * unit))', 'card_name.add_theme_font_size_override("font_size", int(16.0 * unit))\n\tcard_name.autowrap_mode = TextServer.AUTOWRAP_OFF\n\tcard_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS', 'Preview title font')
# Preserve the drawing style but put a real artwork panel between the title and type label.
needle = '\tvar type_label := Label.new()\n\ttype_label.text = TextCatalog.text('
illustration = '''\t# Preview shows a framed illustration and never draws outside its own bounds.
\tvar artwork_frame := Panel.new()
\tartwork_frame.name = "PreviewArtworkFrame"
\tartwork_frame.position = Vector2(14.0, 62.0) * unit
\tartwork_frame.size = Vector2(preview_width / unit - 28.0, 94.0) * unit
\tartwork_frame.clip_contents = true
\tartwork_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
\tartwork_frame.add_theme_stylebox_override("panel", SaloonTheme.panel(Color("#30281f"), accent, 2.0 * unit))
\tpreview.add_child(artwork_frame)
\tvar artwork := TextureRect.new()
\tartwork.name = "PreviewArtwork"
\tartwork.position = Vector2(3.0, 3.0) * unit
\tartwork.size = artwork_frame.size - Vector2(6.0, 6.0) * unit
\tartwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
\tartwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
\tartwork.texture = CardArt.texture(str(card.get("card_data_id", "")))
\tartwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
\tartwork_frame.add_child(artwork)

'''
s = rep(s, needle, illustration + needle, 'Preview artwork')
s = rep(s, 'type_label.position = Vector2(14.0, 39.0) * unit', 'type_label.position = Vector2(14.0, 161.0) * unit', 'Preview type position')
s = rep(s, 'description.position = Vector2(14.0, 63.0) * unit', 'description.position = Vector2(14.0, 184.0) * unit', 'Preview description position')
s = rep(s, 'description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART\n\tdescription.add_theme_font_size_override("font_size", int(14.0 * unit))', 'description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART\n\tdescription.max_lines_visible = 4\n\tdescription.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS\n\tdescription.add_theme_font_size_override("font_size", int(13.0 * unit))', 'Preview text fitting')
s = rep(s, 'reason_label.position = Vector2(14.0, 139.0) * unit', 'reason_label.position = Vector2(14.0, 257.0) * unit', 'Preview disabled reason')
s = rep(s, '\t\tvar sid := action(\n\t\t\t"+",', '\t\tvar sid := action(\n\t\t\t"KỸ NĂNG",', 'Sid skill action label')
s = rep(s, '\t\tsid.name = "SidAbility"\n\t\tsid.tooltip_text', '\t\tsid.name = "SidAbility"\n\t\tsid.custom_minimum_size = Vector2(110.0, 44.0)\n\t\tsid.tooltip_text', 'Sid skill button size')
changes[p] = s

p = root / 'scripts/ui/PlayerLoadoutPanel.gd'
s = p.read_text(encoding='utf-8')
s = rep(s, 'width = minf(layout.units(self, 180.0), get_viewport_rect().size.x * 0.28)', 'width = minf(layout.units(self, 206.0), get_viewport_rect().size.x * 0.34)', 'Compact loadout width')
s = rep(s, '"♠ %s · T%d%s" % [current_weapon_name.left(9), current_range, " · +%d" % current_equipment_count if current_equipment_count > 0 else ""]', '"TRANG BỊ · TẦM %d · %d LÁ" % [current_range, current_equipment_count]', 'Loadout visible label')
s = rep(s, 'title_button.custom_minimum_size.y = layout.units(self, 34.0) if compact else 36.0', 'title_button.custom_minimum_size.y = layout.units(self, 42.0) if compact else 40.0', 'Loadout hit target')
changes[p] = s

for p, new in changes.items():
    print(('CHECK' if check else 'PATCH') + ': ' + str(p.relative_to(root)))
if not check:
    for p, new in changes.items():
        backup = p.with_suffix(p.suffix + '.bak')
        if not backup.exists(): backup.write_bytes(p.read_bytes())
        p.write_text(new, encoding='utf-8')
    print('Modified 3 source files, with .bak backups. Run Godot parser and regression tests.')
else:
    print('All 3 source checks passed; rerun without --check to apply.')
