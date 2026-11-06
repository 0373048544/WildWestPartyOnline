#!/usr/bin/env python3
"""Safely attach the existing mobile HP HUD to MatchHUD; no rules or network edits."""
from pathlib import Path
import sys
import shutil

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
match_path = ROOT / 'scripts/ui/MatchHUD.gd'
hud_path = ROOT / 'scripts/ui/MobileSelfHealthHUD.gd'
if not match_path.is_file() or not hud_path.is_file():
    raise SystemExit('ERROR: scripts/ui/MatchHUD.gd or MobileSelfHealthHUD.gd not found. No files modified.')

original_match = match_path.read_text(encoding='utf-8-sig')
original_hud = hud_path.read_text(encoding='utf-8-sig')
marker = '\tif top_changed:\n\t\t_free_named("TopBar")\n\t\tbuild_top()\n'
method_marker = 'func _sync_action_history() -> void:'
if method_marker not in original_match:
    raise SystemExit('ERROR: MatchHUD.gd structure differs. No files modified.')
if 'func _sync_self_health(' not in original_match and marker not in original_match:
    raise SystemExit('ERROR: TopBar layout section changed. No files modified.')
if 'func update_health(row: Dictionary, layout: Script)' not in original_hud:
    raise SystemExit('ERROR: Unexpected MobileSelfHealthHUD.gd. No files modified.')

updated_match = original_match
if 'func _sync_self_health(' not in updated_match:
    method = '''# Show local HP in 2D: the seated first-person camera hides the local 3D nameplate.
func _sync_self_health(local_row: Dictionary) -> void:
\tvar health_hud: PanelContainer = get_node_or_null("MobileSelfHealthHUD") as PanelContainer
\tif not layout.mobile_first_person(self) or local_row.is_empty() or str(state.get("phase", "")) == "CHARACTER_SELECTION":
\t\tif is_instance_valid(health_hud):
\t\t\thealth_hud.visible = false
\t\treturn
\tif not is_instance_valid(health_hud):
\t\thealth_hud = load("res://scripts/ui/MobileSelfHealthHUD.gd").new() as PanelContainer
\t\thealth_hud.z_index = layout.Z_NAMEPLATE + 10
\t\tadd_child(health_hud)
\t# HP comes from the authoritative public snapshot, never client estimates.
\thealth_hud.call("update_health", local_row, layout)
\thealth_hud.visible = true


'''
    updated_match = updated_match.replace(method_marker, method + method_marker, 1)
if '\t_sync_self_health(local_row)\n' not in updated_match:
    updated_match = updated_match.replace(marker, marker + '\t_sync_self_health(local_row)\n', 1)

lines = original_hud.splitlines(keepends=True)
changed_text = 0
for i, line in enumerate(lines):
    if '_hp_label.text =' in line:
        indent = line[:len(line) - len(line.lstrip())]
        lines[i] = indent + '_hp_label.text = "%s %d/%d" % [char(0x2665), current_hp, max_hp]\n'
        changed_text += 1
if changed_text != 1:
    raise SystemExit('ERROR: Could not reliably find HP label line. No files modified.')
updated_hud = ''.join(lines)

changed = []
for path, old, new in [(match_path, original_match, updated_match), (hud_path, original_hud, updated_hud)]:
    if old != new:
        backup = path.with_suffix(path.suffix + '.before_mobile_hp.bak')
        if not backup.exists():
            shutil.copy2(path, backup)
        path.write_text(new, encoding='utf-8', newline='\n')
        changed.append(str(path.relative_to(ROOT)))
print('Updated:', ', '.join(changed) if changed else 'Already applied; no changes.')
print('Backups: *.before_mobile_hp.bak (first modification only)')
print('Next: run Godot parser/test and verify on mobile; do not commit until checked.')
