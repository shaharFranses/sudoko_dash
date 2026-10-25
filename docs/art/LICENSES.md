# Art licenses log (Sudoku Dash)

Art direction **approved 2026-10-24**. Art kit v1 is in `assets/art/` (branch `art/assets-v1`). It is **not yet wired into any scene**.
Add a row whenever an art asset enters the repo.

> Shipping note: export preset uses `export_filter="all_resources"`, so everything imported under `assets/art/` ships in the `.pck` even before it's referenced. Measured cost of kit v1: **+0.83 MB pck**. See STYLE_GUIDE.md §8.

## Fonts (shipped: `assets/art/fonts/`)
| File | Source | License | Modification | Verified |
|---|---|---|---|---|
| `Fraunces-SemiBoldSoft.ttf`, `Fraunces-BoldSoft.ttf` | https://github.com/undercasetype/Fraunces (via google/fonts `ofl/fraunces`) | SIL OFL 1.1, no Reserved Font Name | Static instances of the variable font (wght 600/700, opsz 48, SOFT 100, WONK 0) and Latin subset made with fontTools. Copyright and license kept in name IDs 0/13/14 | 2026-10-24, `OFL-Fraunces.txt` |
| `AtkinsonHyperlegibleNext-{Regular,Medium,Bold}.ttf` | https://github.com/googlefonts/atkinson-hyperlegible-next (via google/fonts `ofl/atkinsonhyperlegiblenext`) | SIL OFL 1.1, no Reserved Font Name | Static instances (wght 400/500/700) and Latin subset made with fontTools. Name IDs 0/13/14 kept | 2026-10-24, `OFL-AtkinsonHyperlegibleNext.txt` |

The OFL text files sit next to the fonts. The TTFs also carry the copyright and license in their name table, which OFL accepts as "machine-readable metadata". The `.txt` files are not exported by default. Optional extra for Build: add `assets/art/fonts/*.txt` to the Web preset `include_filter`, and/or credit the fonts in an in-game Credits screen.

## Icons (shipped: `assets/art/icons/`, 100x100 PNG, recoloured to palette ink/cream/gold)
| Icon | Source file | Pack | License |
|---|---|---|---|
| star, settings (gear), sound_on (audioOn), undo (return), lock (locked), back (arrowLeft) | `PNG/White/2x/*.png` | [Kenney Game Icons](https://kenney.nl/assets/game-icons) | CC0 1.0 (pack `license.txt`) |
| sound_off | `audioOff.png` plus a studio-drawn "x" for clarity | Kenney Game Icons | CC0 1.0 |
| notes (toolPencil), erase (toolEraser), coin (coin) | `PNG/White/2x/*.png` | [Kenney Game Icons Expansion](https://kenney.nl/assets/game-icons-expansion) (Game Icons has no pencil, eraser or coin) | CC0 1.0 (pack `license.txt`) |
| hint (light bulb) | drawn by SD Art with PIL (`docs/art/tools/icons.py`) | studio-owned | n/a. Neither Kenney pack has a bulb |

Attribution isn't required for CC0, but "Icons: Kenney (kenney.nl)" in the Credits is a nice courtesy.

## Generated art (shipped: `assets/art/harbour/`)
All made 2026-10-24 with the Grok Bot image generation tool, in the locked style from ART_DIRECTION_PROPOSAL.md §5, with `docs/art/moodboard/02_harbour_village.jpg` as the style reference. Prompts were written by the studio. Cutouts use rembg (`isnet-general-use` model, MIT-licensed tool) plus edge decontamination. These are studio-owned assets. Before using them in marketing or portal covers, re-check the image tool's terms.

| File | Content |
|---|---|
| `harbour_bg_portrait.webp` (720x1280), `harbour_bg_landscape.webp` (1280x720) | Harbour base scene with empty slots (plinth, open water, quay corner, soil strips, jetty edge) |
| `task_{dock,boats,flowers,lighthouse,cafe}_{unrestored,restored}.webp` | 10 transparent task sprites. Each before/after pair was generated together as one image so they match, then split |

## Docs-only images (`docs/`, excluded via `docs/.gdignore`)
| File | Notes |
|---|---|
| `moodboard/*.jpg` | Approved mood board. The grid screen's 9x9 grid is rendered in code from puzzle `9x9_t1_0000` |
| `contact_sheet_v1.jpg`, `theme_preview_v1.jpg` | Kit v1 overview. The theme preview is a real Godot render (`tools/art/theme_preview.gd`) |

`docs/art/tools/*.py` and `tools/art/*` are helper scripts. They aren't shipped (`tools/*` is export-excluded, `docs/` is gdignored). Raw generations and cutouts are kept outside the project, on the art box at `/workspace/sd_art/raw/`.
