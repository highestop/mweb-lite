# App icon

Lucide’s `playing-cards-fan` on a charcoal gradient, with silver, muted rose, and warm gray strokes inspired by MWeb’s palette. MWeb artwork is not included.

- Original SVG: `playing-cards-fan.svg`, from [Lucide commit 02eb916](https://raw.githubusercontent.com/lucide-icons/lucide/02eb9161b57917ccaa262f1bf070507cddde3b08/icons/playing-cards-fan.svg).
- License and inherited notices: `../AppIcon-LICENSE.txt`; also included in the app bundle.
- Edited input: `playing-cards-fan-edited.svg`, with colors and drawing order adjusted for the overlapping cards. The generated artwork uses 1.8-unit strokes and a 77% symbol canvas.
- Native source: `../AppIcon.icon`, with an outlined SVG foreground and default, dark, and monochrome appearances.
- Static vector fallback: `../AppIcon.svg`. The background runs from `#3F4553` to `#252A34`; the foreground colors are `#E0E2E6`, `#B29B9F`, and `#97968D`.

The vectors were prepared with the local `design-app-icon` helper. The repository build uses only macOS tools: it renders every 1x/2x icon size directly from the static SVG, and Xcode 26 or later additionally compiles the native Icon Composer document. Generated PNGs, ICNS files, asset catalogs, and app bundles stay under ignored `build/`.

The static enclosure is a fallback drawing; the native document leaves the enclosure and glass rendering to macOS. To change the design, update both vector variants and keep the Lucide license notice.
