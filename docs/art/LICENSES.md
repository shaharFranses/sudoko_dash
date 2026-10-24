# Art licenses log (Sudoku Dash)

Status: **PROPOSED**. None of these assets is in the game or the export yet. Add a row whenever an art asset enters the repo.

## Fonts (proposed, not yet added to the project)
| Asset | Source | License | Verified | Notes |
|---|---|---|---|---|
| Fraunces (variable) | https://github.com/undercasetype/Fraunces · https://fonts.google.com/specimen/Fraunces | SIL Open Font License 1.1 | 2026-10-24, upstream `OFL.txt` (Copyright 2018 The Fraunces Project Authors) | Display font. Ship `OFL.txt` alongside the font when added |
| Atkinson Hyperlegible Next (variable) | https://github.com/googlefonts/atkinson-hyperlegible-next · https://fonts.google.com/specimen/Atkinson+Hyperlegible+Next | SIL Open Font License 1.1 | 2026-10-24, upstream `OFL.txt` (Copyright 2020-2024 The Atkinson Hyperlegible Next Project Authors) | UI and digit font. Ship `OFL.txt` alongside the font when added |

## Asset packs (proposed)
| Asset | Source | License | Verified | Notes |
|---|---|---|---|---|
| Kenney Game Icons | https://kenney.nl/assets/game-icons | CC0 1.0 (public domain) | 2026-10-24, asset page states "Creative Commons CC0" | UI glyphs only. Attribution not required, but credit "Kenney (kenney.nl)" as a courtesy |
| Kenney UI Pack (fallback) | https://kenney.nl/assets/ui-pack | CC0 1.0 | 2026-10-24, asset page states "Creative Commons CC0" | Icons only, if needed |

## Generated mood board images (docs only, excluded from export via `docs/.gdignore`)
Made with the Grok Bot image generation tool on 2026-10-24, from studio-written prompts. They are owned by the studio for concept and marketing use. Before shipping any derivative as a portal cover, check the portal rules ("art we own") and the terms of the image tool in use.

| File | Content | Made by |
|---|---|---|
| `moodboard/01_grid_screen.jpg` | Grid screen mockup | Generated background and UI chrome, plus a code-rendered 9x9 grid (`tools/grid_overlay.py`, palette + Atkinson Hyperlegible Next, puzzle `9x9_t1_0000`) |
| `moodboard/02_harbour_village.jpg` | Harbour village scene | Generated. This is the style reference for all later generations |
| `moodboard/03_restore_before_after.jpg` | Café before/after | Generated, with 02 used as reference (second attempt; the first was rejected because the before/after difference was too subtle) |
| `moodboard/04_cover_key_art.jpg` | Cover/key art with the title "Sudoku Dash" | Generated, with 02 used as reference |
| `moodboard/00_combined_moodboard.jpg` | Combined board with palette swatches and font samples | Composed with `tools/board.py` (PIL) |

`tools/*.py` are helper scripts for docs only. They use box paths and are not part of the game.
