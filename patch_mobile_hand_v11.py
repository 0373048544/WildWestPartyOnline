from pathlib import Path
import sys, shutil, datetime
ROOT = Path(__file__).resolve().parent
# Run from the project root or pass its path as the first argument.
args = [x for x in sys.argv[1:] if x != '--check']
base = Path(args[0]).resolve() if args else Path.cwd()
check = '--check' in sys.argv
replacements = {
 'scripts/ui/MatchLayout.gd': [
('return units(node, 160.0 if targeting else 166.0)', 'return units(node, 122.0 if targeting else 128.0)'),
('return units(node, clampf(141.0 + maxf(0.0, css.x - 360.0) * 0.08, 141.0, 146.0))', 'return units(node, clampf(104.0 + maxf(0.0, css.x - 360.0) * 0.04, 104.0, 108.0))'),
 ],
 'scripts/ui/HandFan.gd': [
('''\t\tview.configure(
\t\t\tcard,
\t\t\tCardData.data(card.card_data_id),
\t\t\tusable.has(card.instance_id),
\t\t\tselected.has(card.instance_id),
\t\t\tstr(reasons.get(card.instance_id, ""))
\t\t)

\t\tview.compact(
\t\t\tselected.has(card.instance_id),
\t\t\treactions and usable.has(card.instance_id)
\t\t)

\t\tif mobile_mode:
\t\t\tvar touch_width: float = minf(
\t\t\t\tsize.x,
\t\t\t\tfloat(layout.touch_card_width(self))
\t\t\t)
\t\t\tview.touch_compact(touch_width)
''', '''\t\t# Reuse unchanged card visuals across network snapshots. Recreating the
\t\t# entire Control tree for every update causes touch-frame spikes.
\t\tvar can_use: bool = usable.has(card.instance_id)
\t\tvar is_chosen: bool = selected.has(card.instance_id)
\t\tvar disabled_reason: String = str(reasons.get(card.instance_id, ""))
\t\tvar touch_width: float = minf(size.x, float(layout.touch_card_width(self))) if mobile_mode else 0.0
\t\tvar signature: String = JSON.stringify([card, can_use, is_chosen, disabled_reason, reactions and can_use, mobile_mode, touch_width])
\t\tif str(view.get_meta("hand_visual_signature", "")) != signature:
\t\t\tview.configure(card, CardData.data(card.card_data_id), can_use, is_chosen, disabled_reason)
\t\t\tview.compact(is_chosen, reactions and can_use)
\t\t\tif mobile_mode:
\t\t\t\tview.touch_compact(touch_width)
\t\t\tview.set_meta("hand_visual_signature", signature)
'''),
('''\tvar minimum: float = (
\t\tfloat(layout.units(self, 42.0))
\t\tif mobile_mode
\t\telse 48.0
\t)''', '''\tvar minimum: float = (
\t\tfloat(layout.units(self, 48.0))
\t\tif mobile_mode
\t\telse 48.0
\t)'''),
 ],
 'scripts/ui/CardView.gd': [
('''\tvar narrow: bool = width < 110.0''', '''\tvar narrow: bool = readable_scale < 0.55'''),
('''\tvar title_size: int = clampi(ceili((13.0 if narrow else 14.0) / readable_scale), 18, 34)''', '''\tvar title_size: int = clampi(ceili(12.0 / maxf(0.2, readable_scale)), 17, 30)'''),
('''\tcard_name.size = Vector2(144, 64 if narrow else 40)''', '''\tcard_name.size = Vector2(144, 38)'''),
('''\tcard_name.clip_text = false
\tcard_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if narrow else TextServer.AUTOWRAP_OFF
\tcard_name.max_lines_visible = 2 if narrow else 1''', '''\tcard_name.clip_text = true
\tcard_name.autowrap_mode = TextServer.AUTOWRAP_OFF
\tcard_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
\tcard_name.max_lines_visible = 1'''),
('''\tcorner.size = Vector2(40, 64 if narrow else 40)''', '''\tcorner.size = Vector2(40, 38)'''),
('''\ttitle_band.size = Vector2(198, 66 if narrow else 42)''', '''\ttitle_band.size = Vector2(198, 42)'''),
('''\tartwork_frame.position.y = 70.0 if narrow else 54.0
\tartwork_frame.size.y = 63.0 if narrow else 79.0''', '''\tartwork_frame.position.y = 54.0
\tartwork_frame.size.y = 79.0'''),
('''\tvisual.scale = Vector2.ONE * touch_scale * (1.05 if chosen_state else 1.0)''', '''\tvisual.scale = Vector2.ONE * touch_scale'''),
 ],
}
# Entire transaction is validated before any file is written.
updated = {}
errors=[]
for relative, changes in replacements.items():
    path=base/relative
    if not path.is_file():
        errors.append(f'MISSING {relative}'); continue
    original=path.read_text(encoding='utf-8-sig')
    content=original
    for old,new in changes:
        count=content.count(old)
        if count!=1:
            errors.append(f'{relative}: expected exactly 1 match, got {count}: {old[:65]!r}')
        else:
            content=content.replace(old,new,1)
    updated[path]=(original,content)
if errors:
    print('PATCH ABORTED SAFELY. No files changed.')
    for e in errors: print(' -',e)
    sys.exit(1)
print('CHECK PASSED: all expected source blocks matched.')
for p,(a,b) in updated.items():print(' ',p.relative_to(base),'changed:',a!=b)
if check:
    print('DRY RUN ONLY: no files changed.');sys.exit(0)
stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
for path,(original,modified) in updated.items():
    shutil.copy2(path,path.with_name(path.name+'.before_mobile_v11_'+stamp+'.bak'))
    path.write_text(modified,encoding='utf-8',newline='\n')
print('PATCH APPLIED. Backups created. Run Godot tests before committing.')
