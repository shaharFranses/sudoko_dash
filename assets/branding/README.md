# Branding (art kit v1)
- `assets/branding/icon.png` (256x256): project icon -> also exported as the web favicon / apple-touch icon (`application/config/icon`).
  Lighthouse crop of the approved cover key art (`docs/art/moodboard/04_cover_key_art.jpg`) + gold star, rounded square, ink border.
- `assets/branding/splash.png` (640x360): the approved cover key art with rounded corners (alpha). It was the boot splash until the
  PKD studio intro landed; the boot splash / web `index.png` is now `res://pkd_boot_splash.png` on navy `#1E1B3A` (studio rule:
  every game opens with the PKD intro, see `pkd_intro/` and /workspace/pikeydi-logo/godot/INTEGRATION.md). Kept for menus/marketing.
Both are self-generated (see docs/art/LICENSES.md), 256-colour PNG. Replace the files with same names/sizes and re-export; no other changes needed.
