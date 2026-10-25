## Sudoku Dash approved art palette (Art Direction v1, approved 2026-10-24).
## Pure constants: no nodes, no side effects. Use ArtPalette.DIGIT_GIVEN etc. Layout-agnostic.
## Source of truth: docs/art/palette.json (regenerate with tools/art/gen_palette.py if values change).
class_name ArtPalette
extends RefCounted

const BG_LINEN := Color("F4EBDC")  # App background behind panels (replaces flat #BFE3EF on menus)
const PANEL_CREAM := Color("FFFAF0")  # Panels, modals, keypad tiles
const GRID_CELL := Color("FFFDF8")  # Grid cell paper
const GRID_LINE_THIN := Color("82959F")  # Thin cell lines
const GRID_LINE_BOX := Color("2E4A5C")  # 3x3 box lines + grid border
const DIGIT_GIVEN := Color("1E2B38")  # Given digits (Bold 700)
const DIGIT_PLAYER := Color("1A4FA3")  # Player digits (Regular 450-500)
const DIGIT_NOTES := Color("4E5D69")  # Pencil notes
const HL_SELECTED := Color("FFE3A3")  # Selected cell (sunlit butter)
const HL_PEER := Color("EDF2F1")  # Row/column/box peers
const HL_SAME := Color("B9D9E6")  # Same-digit cells
const ERROR_INK := Color("A3211A")  # Wrong digit (+ underline + shake, never colour-only)
const ERROR_CELL := Color("F9D9D3")  # Wrong-digit cell tint
const ACCENT_TEAL := Color("2C6E73")  # Primary buttons (Play, Resume, Hint)
const ACCENT_TERRACOTTA := Color("B5523B")  # Secondary CTA / Buy / rewarded
const STAR_GOLD := Color("F2B33D")  # Stars, coins, rewards (with navy text/outline)
const BTN_DISABLED := Color("E4DDD0")  # Locked/disabled button fill (with lock icon)
const TEXT_INK := Color("1E2B38")  # Body/UI text
const SKY := Color("BFE3EF")  # Village sky (kept; matches splash/body bg)
const SEA := Color("2F7FA6")  # Deep harbour water
const SEA_SHALLOW := Color("6BB8C9")  # Shallows/turquoise
const SAND := Color("E9D8B4")  # Quay, sand, stone paths
const WHITEWASH := Color("F7F3EA")  # Cottage walls
const ROOF_TERRACOTTA := Color("C4633F")  # Roofs, awning stripes
const SHUTTER_BLUE := Color("3E6FA3")  # Shutters, doors, boat trim
const SAGE := Color("8BA37A")  # Foliage, olive trees
const LAVENDER := Color("9C8AC4")  # Lavender beds, dusk accents
const GERANIUM := Color("D9473F")  # Flowers, lighthouse stripes
const WOOD := Color("8A5A3B")  # Dock planks, boats, rope posts
const SHADOW_LILAC := Color("5B5470")  # Shadow tint (never pure black)

## Derived interaction shades (computed once, palette-consistent)
const ACCENT_TEAL_HOVER := Color("286469")
const ACCENT_TEAL_PRESSED := Color("235a5e")
const ACCENT_TERRACOTTA_HOVER := Color("a84b35")
const ACCENT_TERRACOTTA_PRESSED := Color("9a4431")
const PANEL_CREAM_PRESSED := Color("f1e8d6")
const SHADOW := Color(0.357, 0.329, 0.439, 0.28)  # shadow_lilac @ 28%

## Fonts (preload-free paths so this script never forces font loading)
const FONT_DISPLAY_SEMIBOLD := "res://assets/art/fonts/Fraunces-SemiBoldSoft.ttf"
const FONT_DISPLAY_BOLD := "res://assets/art/fonts/Fraunces-BoldSoft.ttf"
const FONT_UI_REGULAR := "res://assets/art/fonts/AtkinsonHyperlegibleNext-Regular.ttf"
const FONT_UI_MEDIUM := "res://assets/art/fonts/AtkinsonHyperlegibleNext-Medium.ttf"
const FONT_UI_BOLD := "res://assets/art/fonts/AtkinsonHyperlegibleNext-Bold.ttf"
const THEME_PATH := "res://assets/art/theme/sudoku_dash_theme.tres"

## Grid digit guidance: given = FONT_UI_BOLD, player = FONT_UI_MEDIUM, notes = FONT_UI_REGULAR.
## Digit size = 0.68-0.72 x cell height; notes = 0.26 x cell height. Error = ERROR_INK + underline (never colour only).
const DIGIT_SIZE_RATIO := 0.70
const NOTE_SIZE_RATIO := 0.26

## Minimum touch target in px at a 720-wide portrait base (about 48dp on phones).
const MIN_TOUCH := 88

static func icon_path(name: String, variant: String = "ink") -> String:
	return "res://assets/art/icons/icon_%s_%s.png" % [name, variant]

static func task_sprite_path(task_id: String, restored: bool) -> String:
	return "res://assets/art/harbour/task_%s_%s.webp" % [task_id, "restored" if restored else "unrestored"]
