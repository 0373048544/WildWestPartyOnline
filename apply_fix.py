"""Apply the first-person self-HP HUD to the local Godot project.

Usage: python apply_fix.py "D:\\GodotProjects\\WildWestPartyOnlin"
Does not connect to GitHub, commit, push, deploy, or modify gameplay rules.
"""
from pathlib import Path
import shutil
import sys

if len(sys.argv) != 2:
    raise SystemExit('Usage: python apply_fix.py "D:\\GodotProjects\\WildWestPartyOnlin"')
root = Path(sys.argv[1]).resolve()
target = root / "scripts/ui/MatchHUD.gd"
source = Path(__file__).parent / "scripts/ui/MobileSelfHealthHUD.gd"
dest = root / "scripts/ui/MobileSelfHealthHUD.gd"
if not target.is_file() or not (root / "project.godot").is_file():
    raise SystemExit("Expected a Godot project with scripts/ui/MatchHUD.gd and project.godot")
s = target.read_text(encoding="utf-8-sig")
anchor = '\tif top_changed:\n\t\t_free_named("TopBar")\n\t\tbuild_top()\n'
call = '\t_sync_self_health(local_row)\n'
method_anchor = 'func _sync_action_history() -> void:'
method = '''func _sync_self_health(local_row: Dictionary) -> void:
\tvar hp_hud: PanelContainer = get_node_or_null("MobileSelfHealthHUD") as PanelContainer
\tvar enabled: bool = layout.mobile_first_person(self) and not local_row.is_empty() and str(state.get("phase", "")) != "CHARACTER_SELECTION"
\tif not enabled:
\t\tif is_instance_valid(hp_hud):
\t\t\thp_hud.visible = false
\t\treturn
\tif not is_instance_valid(hp_hud):
\t\thp_hud = load("res://scripts/ui/MobileSelfHealthHUD.gd").new()
\t\thp_hud.z_index = layout.Z_NAMEPLATE + 10
\t\tadd_child(hp_hud)
\thp_hud.update_health(local_row, layout)
\thp_hud.visible = true


'''
if 'func _sync_self_health(local_row: Dictionary)' in s:
    raise SystemExit("HUD fix already present; no files changed")
if s.count(anchor) != 1 or s.count(method_anchor) != 1:
    raise SystemExit("Local MatchHUD.gd has changed; expected anchors not found exactly once. No files changed.")
if dest.exists():
    raise SystemExit("MobileSelfHealthHUD.gd already exists; refusing to overwrite. No files changed.")
updated = s.replace(anchor, anchor + call, 1).replace(method_anchor, method + method_anchor, 1)
assert updated.count(call) == 1
assert updated.count('func _sync_self_health(local_row: Dictionary)') == 1
backup = target.with_suffix('.gd.pre-mobile-health.bak')
if backup.exists():
    raise SystemExit(f"Backup already exists: {backup}; no files changed")
shutil.copy2(target, backup)
try:
    target.write_text(updated, encoding='utf-8')
    shutil.copy2(source, dest)
except Exception:
    shutil.copy2(backup, target)
    if dest.exists():
        dest.unlink()
    raise
print(f"UPDATED: {target}")
print(f"CREATED: {dest}")
print(f"BACKUP:  {backup}")
print("Static insertion verified. Run Godot parser and mobile Safari playtest locally.")
