#!/usr/bin/env python3
"""WWPO hotfix V4 - source-guarded edits, backups, no external dependencies.
Run from Godot project directory; use --check before applying.
"""
from pathlib import Path
import sys, difflib

root = Path.cwd()
check = '--check' in sys.argv
if not (root/'project.godot').is_file():
    sys.exit('ERROR: Run from project root (project.godot missing).')
changes = {}

def sub(s, old, new, label, optional=False):
    if old not in s:
        if optional or new in s:
            print('SKIP (already done / unavailable):', label)
            return s
        raise ValueError(label + ': expected code not found, stopped before writing any files')
    if s.count(old) != 1:
        raise ValueError(label + ': matched multiple locations, stopped before writing files')
    print('OK:', label)
    return s.replace(old, new, 1)

# --- 1) Rematch crash: the closure in the existing source captured a nil Button.
p = root/'scripts/ui/MatchHUD.gd'
s = p.read_text(encoding='utf-8')
s = sub(s,
'''\t\tvar continue_button: Button
\t\tcontinue_button = action("TIẾP TỤC", func(): _request_rematch(continue_button), box)''',
'''\t\tvar continue_button := action("TIẾP TỤC", _request_rematch, box)''',
'Bind rematch action without capturing an uninitialized Button')
s = sub(s,
'''func _request_rematch(button: Button) -> void:
\tif button.disabled or not NetworkManager.can_submit_intents():
\t\treturn
\tif app.intent("rematch"):
\t\tbutton.disabled = true
\t\tbutton.text = "ĐANG XÁC NHẬN…"''',
'''func _request_rematch() -> void:
\t# Resolve the actual button on click. The previous closure captured Nil.
\tif not is_instance_valid(app.overlay):
\t\treturn
\tvar button: Button = app.overlay.find_child("RematchReadyButton", true, false) as Button
\tif not is_instance_valid(button) or button.disabled:
\t\treturn
\tif not NetworkManager.can_submit_intents():
\t\treturn
\t# Disable immediately to block repeated clicks; restore if submission fails.
\tbutton.disabled = true
\tbutton.text = "ĐANG XÁC NHẬN…"
\tif not app.intent("rematch"):
\t\tif is_instance_valid(button):
\t\t\tbutton.disabled = false
\t\t\tbutton.text = "TIẾP TỤC"''',
'Fix Nil crash, double click and unsuccessful rematch submission')

# --- 2) Known server-driven draw-steal reaction: provide a visible action.
needle = '''\t\tif reaction_type == "draw_steal" or reaction_type == "draw_discard":
\t\t\tprompt.text = (
\t\t\t\t"CHỌN CHỒNG RÚT / CHỒNG BỎ"
\t\t\t\tif reaction_type == "draw_discard"
\t\t\t\telse "CHỌN CHỒNG RÚT HOẶC TAY BÀI ĐỐI THỦ"
\t\t\t)'''
new = '''\t\tif reaction_type == "draw_steal" or reaction_type == "draw_discard":
\t\t\tprompt.text = (
\t\t\t\t"CHỌN CHỒNG RÚT / CHỒNG BỎ"
\t\t\t\tif reaction_type == "draw_discard"
\t\t\t\telse "KỸ NĂNG: RÚT HOẶC LẤY BÀI ĐỐI THỦ"
\t\t\t)
\t\t\tif reaction_type == "draw_steal":
\t\t\t\t# Existing GameManager/world_action expects another player's ID as
\t\t\t\t# the reaction option. Never reveal or enumerate their private cards.
\t\t\t\tif layout.mobile_portrait(self):
\t\t\t\t\tprompt.visible = false
\t\t\t\tvar opponent_picker := OptionButton.new()
\t\t\t\topponent_picker.name = "DrawStealOpponentPicker"
\t\t\t\topponent_picker.add_item("LẤY BÀI ĐỐI THỦ")
\t\t\t\topponent_picker.set_item_disabled(0, true)
\t\t\t\tfor other in state.get("players", []):
\t\t\t\t\tif int(other.get("player_id", -1)) == app.local_id() or not bool(other.get("is_alive", false)):
\t\t\t\t\t\tcontinue
\t\t\t\t\topponent_picker.add_item(str(other.get("display_name", "Cao bồi")))
\t\t\t\t\topponent_picker.set_item_metadata(opponent_picker.item_count - 1, int(other.get("player_id", 0)))
\t\t\t\topponent_picker.selected = 0
\t\t\t\topponent_picker.custom_minimum_size = Vector2(layout.units(self, 132.0), layout.units(self, 44.0))
\t\t\t\topponent_picker.tooltip_text = "KỸ NĂNG: Chọn người để lấy ngẫu nhiên 1 lá trên tay (nếu hợp lệ)"
\t\t\t\tfooter.add_child(opponent_picker)
\t\t\t\topponent_picker.item_selected.connect(func(index: int):
\t\t\t\t\tif index > 0:
\t\t\t\t\t\tworld_action({"kind": "zone", "player": int(opponent_picker.get_item_metadata(index))})
\t\t\t\t)
\t\t\t\tvar draw_button := action("RÚT CHỒNG", func(): world_action({"kind": "deck"}), footer)
\t\t\t\tdraw_button.name = "DrawStealDeckButton"
\t\t\t\tdraw_button.custom_minimum_size.x = layout.units(self, 106.0)'''
s = sub(s, needle, new, 'Add server-authorized draw-steal target picker')

# Visible info for every defined character, without inventing active abilities.
needle = '''\tif app.sid_mode:
\t\taction(
\t\t\t"HỒI 1 MÁU",'''
new = '''\t# Character skill reference: informative unless an ability is actually
\t# activated by the server-supported actions below.
\tvar ability_description := str(character.get("ability_description_vi", ""))
\tif not ability_description.is_empty() and not app.sid_mode and request.is_empty():
\t\tvar show_skill := func() -> void:
\t\t\tif is_instance_valid(app.personal_toasts):
\t\t\t\tapp.personal_toasts.show_notice(
\t\t\t\t\tstr(character.get("display_name", "KỸ NĂNG")), ability_description,
\t\t\t\t\t"positive", "✦", 4.0
\t\t\t\t)
\t\tvar skill_info := action("KỸ NĂNG", show_skill, footer)
\t\tskill_info.name = "CharacterSkillInfo"
\t\tskill_info.tooltip_text = ability_description
\t\tskill_info.custom_minimum_size.x = layout.units(self, 90.0)

\tif app.sid_mode:
\t\taction(
\t\t\t"HỒI 1 MÁU",'''
s = sub(s,needle,new,'Show named character skill information',optional=False)
s = sub(s, '''\t\tvar sid := action(
\t\t\t"+",''', '''\t\tvar sid := action(
\t\t\t"KỸ NĂNG: HỒI MÁU",''', 'Label active Sid ability',optional=True)
s = sub(s, '''\t\tsid.name = "SidAbility"
\t\tsid.tooltip_text''','''\t\tsid.name = "SidAbility"
\t\tsid.custom_minimum_size.x = layout.units(self, 148.0)
\t\tsid.tooltip_text''','Size active Sid button',optional=True)

# Preview safe text: no oversized glyphs or overflow.
s = sub(s, '''\tpreview.name = "CardPreview"
\tpreview.mouse_filter''','''\tpreview.name = "CardPreview"
\tpreview.clip_contents = true
\tpreview.mouse_filter''','Clip preview contents',optional=True)
s = sub(s, 'var preview_height: float = (176.0 if not reason.is_empty() else 150.0) * unit', 'var preview_height: float = (202.0 if not reason.is_empty() else 172.0) * unit', 'Enlarge preview for Vietnamese desc',optional=True)
s = sub(s,'''\tcard_name.add_theme_font_size_override("font_size", int(18.0 * unit))''','''\tcard_name.add_theme_font_size_override("font_size", int(16.0 * unit))
\tcard_name.autowrap_mode = TextServer.AUTOWRAP_OFF
\tcard_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS''','Preview title single-line fitting',optional=True)
s = sub(s, '''\tdescription.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
\tdescription.add_theme_font_size_override("font_size", int(14.0 * unit))''', '''\tdescription.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
\tdescription.max_lines_visible = 4
\tdescription.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
\tdescription.add_theme_font_size_override("font_size", int(13.0 * unit))''','Preview description fitting',optional=True)
s = sub(s, 'reason_label.position = Vector2(14.0, 139.0) * unit', 'reason_label.position = Vector2(14.0, 163.0) * unit','Preview reason below desc',optional=True)
changes[p]=s

# --- 3) Card titles: lift on top of artwork and constrain to one line.
p=root/'scripts/ui/CardView.gd'
s=p.read_text(encoding='utf-8')
s=sub(s,'''\tvar card_name := add_text(definition.name, Rect2(10, 8, 190, 25), 17, SaloonTheme.CREAM)
\tcard_name.name = "CardName"
\tcard_name.clip_text = false
\tcard_name.max_lines_visible = 2
\tcard_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER''','''\tvar card_name := add_text(str(definition.get("name", "LÁ BÀI")), Rect2(10, 7, 190, 29), 17, SaloonTheme.CREAM)
\tcard_name.name = "CardName"
\tcard_name.z_index = 3
\tcard_name.visible = true
\tcard_name.clip_text = true
\tcard_name.autowrap_mode = TextServer.AUTOWRAP_OFF
\tcard_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
\tcard_name.max_lines_visible = 1
\tcard_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER''','Keep card name readable in fixed header')
s=sub(s,'''\tvar desired_title_height: float = 30.0 if portrait_card else 21.0''','''\tvar desired_title_height: float = 30.0 if portrait_card else 21.0''','Existing font sizing',optional=True)
s=sub(s,'var source_title_font: int = mini(38, maxi(17, ceili(desired_title_font / touch_scale)))','var source_title_font: int = mini(26, maxi(17, ceili(desired_title_font / touch_scale)))','Avoid oversized mobile header font',optional=True)
s=sub(s,'var source_title_height: float = minf(52.0, maxf(34.0, desired_title_height / touch_scale))','var source_title_height: float = 31.0','Prevent header overlap with rank/art',optional=True)
s=sub(s,'card_name.position = Vector2(8.0, 5.0)','card_name.position = Vector2(10.0, 5.0)','Align mobile title',optional=True)
s=sub(s,'title_band.size = Vector2(198.0, minf(55.0, source_title_height + 3.0))','title_band.size = Vector2(198.0, 32.0)','Keep mobile title band inside top 32 pixels',optional=True)
changes[p]=s

# --- 4) Equipment section gets a legible title rather than cryptic chips.
p=root/'scripts/ui/PlayerLoadoutPanel.gd'
s=p.read_text(encoding='utf-8')
s=sub(s,'''"♠ %s · T%d%s" % [current_weapon_name.left(9), current_range, " · +%d" % current_equipment_count if current_equipment_count > 0 else ""]''','''"TRANG BỊ · TẦM %d · %d LÁ" % [current_range, current_equipment_count]''','Readable equipment caption',optional=True)
s=sub(s,'width = minf(layout.units(self, 180.0), get_viewport_rect().size.x * 0.28)','width = minf(layout.units(self, 206.0), get_viewport_rect().size.x * 0.34)','Widen compact equipment UI',optional=True)
changes[p]=s

for p, value in changes.items():
    old=p.read_text(encoding='utf-8')
    print(('CHANGED: ' if value!=old else 'UNCHANGED: ')+str(p.relative_to(root)))
if check:
    print('\nCHECK PASSED: Preview only; nothing was written.')
else:
    for p, new in changes.items():
        old=p.read_text(encoding='utf-8')
        if new==old: continue
        bak=p.with_suffix(p.suffix+'.before_v4.bak')
        if not bak.exists(): bak.write_text(old, encoding='utf-8')
        p.write_text(new, encoding='utf-8')
    print('\nPATCH APPLIED. Backups *.before_v4.bak were created. Run Godot tests before git push.')
