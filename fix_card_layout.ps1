# Miền Tây Đại Chiến – card layout hotfix
# Run at the Godot project root with:
# powershell -NoProfile -ExecutionPolicy Bypass -File .\fix_card_layout.ps1
$ErrorActionPreference = "Stop"
$path = Join-Path (Get-Location) "scripts\ui\CardView.gd"
if (-not (Test-Path "project.godot") -or -not (Test-Path $path)) {
    throw "Run this script from the Godot project root."
}
$original = [System.IO.File]::ReadAllText($path)
$src = $original

function Replace-ExactlyOnce([string]$old, [string]$new, [string]$label) {
    $count = ([regex]::Matches($script:src, [regex]::Escape($old))).Count
    if ($count -ne 1) { throw "$label : expected one matching block, found $count. No files changed." }
    $script:src = $script:src.Replace($old,$new)
}

# Header name + suit on one line, like the expanded card preview.
Replace-ExactlyOnce `
    'var card_name := add_text(definition.name, Rect2(10, 8, 190, 25), 17, SaloonTheme.CREAM)' `
    'var card_name := add_text(str(definition.get("name", "")), Rect2(12, 6, 142, 30), 17, SaloonTheme.CREAM)' `
    'header title'
Replace-ExactlyOnce `
    'card_name.max_lines_visible = 2' `
    'card_name.max_lines_visible = 1' `
    'header line count'
Replace-ExactlyOnce `
    "card_name.max_lines_visible = 1`n`tcard_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER`n`tvar corner" `
    "card_name.max_lines_visible = 1`n`tcard_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER`n`tcard_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT`n`tcard_name.autowrap_mode = TextServer.AUTOWRAP_OFF`n`tcard_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS`n`tvar corner" `
    'header title alignment'
Replace-ExactlyOnce `
    'var corner := add_text(CardInstance.corner(card), Rect2(10, 39, 62, 32), 22, CardInstance.suit_color(card.suit))' `
    'var corner := add_text(CardInstance.corner(card), Rect2(156, 7, 43, 28), 17, CardInstance.suit_color(card.suit))' `
    'header corner'
Replace-ExactlyOnce `
    'corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT' `
    'corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT' `
    'corner alignment'
Replace-ExactlyOnce `
    'band.position = Vector2(6, 6)' `
    'band.position = Vector2(6, 5)' `
    'header band position'
Replace-ExactlyOnce `
    'band.size = Vector2(198, 31)' `
    'band.size = Vector2(198, 34)' `
    'header band size'
Replace-ExactlyOnce `
    'band_glint.position = Vector2(8, 34)' `
    'band_glint.position = Vector2(8, 39)' `
    'header glint'
Replace-ExactlyOnce `
    'status_rail.position = Vector2(6, 42)' `
    'status_rail.position = Vector2(6, 44)' `
    'rail position'
Replace-ExactlyOnce `
    'status_rail.size = Vector2(4 if chosen else 3, 157)' `
    'status_rail.size = Vector2(4 if chosen else 3, 163)' `
    'rail size'

# Consistent art, category, and description layout, reserving a larger body.
Replace-ExactlyOnce `
    'artwork_frame.position = Vector2(12, 62)' `
    'artwork_frame.position = Vector2(12, 45)' `
    'art position'
Replace-ExactlyOnce `
    'artwork_frame.size = Vector2(186, 76)' `
    'artwork_frame.size = Vector2(186, 88)' `
    'art frame size'
Replace-ExactlyOnce `
    'artwork.size = Vector2(180, 70)' `
    'artwork.size = Vector2(180, 82)' `
    'art content size'
Replace-ExactlyOnce `
    'type_badge.position = Vector2(55, 141)' `
    'type_badge.position = Vector2(55, 137)' `
    'category position'
Replace-ExactlyOnce `
    'var type_text := add_text(TextCatalog.text(CardData.CardType.keys()[definition.type]), Rect2(58, 143, 94, 17), 11, SaloonTheme.CREAM)' `
    'var type_text := add_text(TextCatalog.text(CardData.CardType.keys()[definition.type]), Rect2(58, 139, 94, 17), 11, SaloonTheme.CREAM)' `
    'category text'
Replace-ExactlyOnce `
    'var description := add_text(definition.description, Rect2(12, 163, 186, 25), 11, Color("#29333a"))' `
    'var description := add_text(str(definition.get("description", "")), Rect2(13, 165, 184, 42), 12, Color("#29333a"))' `
    'description rect'
Replace-ExactlyOnce `
    'description.max_lines_visible = 2' `
    "description.max_lines_visible = 3`n`tdescription.vertical_alignment = VERTICAL_ALIGNMENT_TOP" `
    'description line count'
Replace-ExactlyOnce `
    'var lower := add_text(CardInstance.corner(card), Rect2(145, 190, 54, 20), 14, CardInstance.suit_color(card.suit))' `
    'var lower := add_text("", Rect2(145, 190, 54, 20), 14, CardInstance.suit_color(card.suit))' `
    'duplicate corner'

# Compact source layout must not scale title band over the picture.
Replace-ExactlyOnce `
    'var source_title_font: int = mini(38, maxi(17, ceili(desired_title_font / touch_scale)))' `
    'var source_title_font: int = mini(27, maxi(16, ceili(desired_title_font / touch_scale)))' `
    'mobile title font limit'
Replace-ExactlyOnce `
    'var source_title_height: float = minf(52.0, maxf(34.0, desired_title_height / touch_scale))' `
    'var source_title_height: float = 30.0' `
    'mobile title height'
Replace-ExactlyOnce `
    'card_name.position = Vector2(8.0, 5.0)' `
    'card_name.position = Vector2(10.0, 6.0)' `
    'mobile title position'
# Both assignments intentionally exist: before and after the font override.
$count = ([regex]::Matches($src, [regex]::Escape('card_name.size = Vector2(194.0, source_title_height)'))).Count
if ($count -ne 2) { throw "mobile title rect: expected 2 matches, found $count. No files changed." }
$src = $src.Replace('card_name.size = Vector2(194.0, source_title_height)', 'card_name.size = Vector2(144.0, source_title_height)')
Replace-ExactlyOnce `
    'title_band.size = Vector2(198.0, minf(55.0, source_title_height + 3.0))' `
    'title_band.size = Vector2(198.0, 34.0)' `
    'mobile title band'
Replace-ExactlyOnce `
    'visual.get_node("CardDescription").visible = false' `
    'visual.get_node("CardDescription").visible = width >= 168.0' `
    'description on sufficiently wide mobile cards'
# Rank/suit belongs in the header, not below artwork.
Replace-ExactlyOnce `
    'rank_suit.position = Vector2(12.0, 140.0)' `
    'rank_suit.position = Vector2(154.0, 7.0)' `
    'mobile suit position'
Replace-ExactlyOnce `
    'rank_suit.size = Vector2(50.0, minf(48.0, 20.0 / touch_scale))' `
    'rank_suit.size = Vector2(46.0, 28.0)' `
    'mobile suit bounds'
Replace-ExactlyOnce `
    'rank_suit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER' `
    "rank_suit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER`n`trank_suit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT" `
    'mobile suit alignment'
Replace-ExactlyOnce `
    'rank_suit.add_theme_font_size_override("font_size", mini(34, maxi(18, int(round(14.0 / touch_scale)))))' `
    'rank_suit.add_theme_font_size_override("font_size", mini(24, maxi(15, int(round(12.0 / touch_scale)))))' `
    'mobile suit font'
Replace-ExactlyOnce `
    'type_badge.position = Vector2(66.0, 141.0)' `
    'type_badge.position = Vector2(55.0, 137.0)' `
    'mobile category badge position'
Replace-ExactlyOnce `
    'type_badge.size = Vector2(132.0, minf(44.0, 20.0 / touch_scale))' `
    'type_badge.size = Vector2(100.0, 21.0)' `
    'mobile category badge size'
Replace-ExactlyOnce `
    'type_label.position = Vector2(70.0, 141.0)' `
    'type_label.position = Vector2(58.0, 139.0)' `
    'mobile category label position'
Replace-ExactlyOnce `
    'type_label.size = Vector2(124.0, minf(44.0, 20.0 / touch_scale))' `
    'type_label.size = Vector2(94.0, 17.0)' `
    'mobile category label size'
Replace-ExactlyOnce `
    'type_label.add_theme_font_size_override("font_size", mini(32, maxi(17, int(round(13.0 / touch_scale)))))' `
    'type_label.add_theme_font_size_override("font_size", mini(24, maxi(13, int(round(11.0 / touch_scale)))))' `
    'mobile category font'

# A heading may be invisible in the normal card because clipped by intrinsic label minimum size.
# Reapply local title rect after all font properties.
$src = $src.Replace(
    'card_name.add_theme_font_size_override("font_size", source_title_font)',
    'card_name.add_theme_font_size_override("font_size", source_title_font)'
)

$bak = "$path.before_card_layout.bak"
if (-not (Test-Path $bak)) { [System.IO.File]::WriteAllText($bak, $original, (New-Object System.Text.UTF8Encoding($false))) }
[System.IO.File]::WriteAllText($path, $src, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "PATCH APPLIED: scripts/ui/CardView.gd" -ForegroundColor Green
Write-Host "Backup: $bak"
Write-Host "Open Godot, test desktop/mobile, then commit. No gameplay files changed."
