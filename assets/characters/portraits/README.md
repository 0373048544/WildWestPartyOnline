# Character portraits

Portraits are rendered from the same original modular 3D model as table avatars by scripts/ui/CharacterPortrait.gd. There are no downloaded portraits, image-generation dependencies or mismatched illustrations.

Each portrait uses its own small transparent SubViewport, updates once by default, and redraws briefly when reacting to hover/selection. Cosmetic presets live in resources/characters/visuals/base_visuals.json. They do not contain abilities, roles, hands or game rules. All meshes are code-generated and shared where possible.
