class_name CardArt
extends RefCounted

const ROOT := "res://assets/cards/art/"
const PATHS := {
	"shoot": ROOT + "shoot.webp",
	"dodge": ROOT + "dodge.webp",
	"drink": ROOT + "drink.webp",
	"panic": ROOT + "panic.webp",
	"cat_balou": ROOT + "cat_balou.webp",
	"showdown": ROOT + "showdown.webp",
	"jail": ROOT + "jail.webp",
	"schofield": ROOT + "schofield.webp",
	"barrel": ROOT + "barrel.webp",
	"horse": ROOT + "horse.webp",
	"volcanic": ROOT + "volcanic.webp",
	"supply": ROOT + "supply.webp",
	"general_store": ROOT + "general_store.webp",
	"indians": ROOT + "indians.webp",
	"dynamite": ROOT + "dynamite.webp",
	"spyglass": ROOT + "spyglass.webp",
	"remington": ROOT + "remington.webp",
	"carabine": ROOT + "carabine.webp",
	"winchester": ROOT + "winchester.webp",
	"gatling": ROOT + "gatling.webp",
	"saloon": ROOT + "saloon.webp",
	"wells_fargo": ROOT + "wells_fargo.webp",
	"department_store": ROOT + "department_store.webp",
	"iced_tea": ROOT + "iced_tea.webp"
}

static var cache: Dictionary = {}


static func texture(card_data_id: String) -> Texture2D:
	var id := CardData.canonical_id(card_data_id)
	if cache.has(id):
		return cache[id]
	var path: String = str(PATHS.get(id, ""))
	var result: Texture2D = load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else _fallback(id)
	cache[id] = result
	return result


static func has_dedicated(card_data_id: String) -> bool:
	var path: String = str(PATHS.get(CardData.canonical_id(card_data_id), ""))
	return not path.is_empty() and ResourceLoader.exists(path)


static func missing_ids() -> Array[String]:
	var missing: Array[String] = []
	for id in CardData.definitions():
		if not has_dedicated(str(id)):
			missing.append(str(id))
	missing.sort()
	return missing


static func _fallback(card_data_id: String) -> Texture2D:
	# Broken/missing imports still render a readable category-colored panel. This
	# is a safety net only; the shipped definition audit requires zero fallbacks.
	var definition: Dictionary = CardData.data(card_data_id)
	var type: int = int(definition.get("type", CardData.CardType.ACTION))
	var colors: Array = [
		[Color("#b96845"), Color("#e3c78d")],
		[Color("#415d68"), Color("#b98c52")],
		[Color("#7b6043"), Color("#d4b66f")],
		[Color("#596e75"), Color("#c5aa72")]
	][clampi(type, 0, 3)]
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray(colors)
	var fallback := GradientTexture2D.new()
	fallback.gradient = gradient
	fallback.width = 512
	fallback.height = 384
	fallback.fill_from = Vector2(0.1, 0.1)
	fallback.fill_to = Vector2(0.9, 0.9)
	return fallback
