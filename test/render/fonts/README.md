# Committed Google faces

Inter, Montserrat and Roboto, all under the
[SIL Open Font License 1.1](OFL.txt). `AppStyle`'s whole type scale is
`GoogleFonts.inter(...)` and `GoogleFonts.montserrat(...)`, google_fonts
fetches faces at runtime, and a widget test has no network — without a
real face every glyph renders as the FlutterTest block font and the PNG
is worthless.

These are the exact files Google serves. google_fonts addresses every
face as `https://fonts.gstatic.com/s/a/<sha256>.ttf`, so **the file name
is the checksum**, and `render_screen_test.dart` serves them back through
google_fonts' own `@visibleForTesting` http seam. google_fonts then takes
its normal path and verifies each file's length *and* SHA-256 before
registering it — so the render is provably the real face, and no hash is
hard-coded in the harness.

## Inter — the body scale

- `ecdb53099b1a68cd24c6900ea5beeafec81bd3c8cb9d0f3c51b9986583ba3982.ttf`
  400 — `AppStyle.interRegular`
- `492dec3bc33255f9d81bd5fb18704ad72f96f9b9318e4171bc9f9be9dd4bf44b.ttf`
  500 — `AppStyle.interNormal`
- `d7ba633bab7f40576e539a7e934a1301d7618dceea59c743de477c2c493462fc.ttf`
  600 — `AppStyle.interNoSemi`
- `b7e339223d56e8c4210c86f1ba87b3d43d6c47e03956ea56f0a7a938ae61b2a3.ttf`
  700 — `AppStyle.interSemi` and `AppStyle.interBold`

## Montserrat — the logo and motto scale

- `e3bb63f2cd246ff159b0841c2bd55d0914291a93487340cfa27574cc8d1861dd.ttf`
  400 — `AppStyle.logoMottoRegular`
- `c33ff345dd6b33c01890010990c475be1e2791e2aec0320160bdfdfe50df97f8.ttf`
  400 italic — `AppStyle.logoMottoRegularItalic`
- `f7d4074869afb39d444728a57fe9d7dd18321cd8b7f94f014e8429c7a7b95c96.ttf`
  700 — `AppStyle.logoFontBold`
- `091a994866ca5994bc4d8954b7eacf09d415fb7faded21f1621b13c57baa0299.ttf`
  700 italic — `AppStyle.logoFontBoldItalic`
- `0130a08a68975f07adfa07ca5b2e7aa2799af9b46d2b3b108fb90169b77c8d13.ttf`
  900 — no upright caller; paired with the italic below
- `9ebd0a4ee149e91df28fd70baaaaef3b81a16f762044a5bfeb3c126ec887ef71.ttf`
  900 italic — `AppStyle.logoFontBlackItalic`

`AppStyle` declares three *italic* Montserrat styles. google_fonts
resolves an italic as a separate face with its own checksum, so those are
committed too even though the profile screen this harness renders does
not currently use them — an uncommitted face fails the whole run loudly,
and a logo style is exactly the kind of thing a future section would
reach for.

## Roboto — the platform default

- `d1d7c5f4500eeb1a09e051781906c3642015a3f6c9b69046b905c8bf34c6ad60.ttf`
  400 — bare `TextStyle`s that name no family

Roboto is the one face google_fonts is never asked for: nothing in
`AppStyle` calls `GoogleFonts.roboto`, but a `TextStyle` that names no
family resolves to the platform default, which under `flutter test` is
the FlutterTest block font. It is therefore registered directly with a
`FontLoader` under the plain family name rather than through the
google_fonts seam.

They are **not** app assets: nothing here is declared in `pubspec.yaml`,
so none of it ships in a build. The harness reads them straight off disk.

## Adding a face

A weight or family nobody committed 404s through the offline client and
fails the run loudly, naming the URL. To add one, read the expected hash
out of google_fonts' own table for that family
(`google_fonts/lib/src/google_fonts_parts/part_<letter>.g.dart`), then
fetch it and add a bullet above:

```bash
curl -sSL -o "test/render/fonts/<hash>.ttf" \
  "https://fonts.gstatic.com/s/a/<hash>.ttf"
```

The same table is what a google_fonts version bump would change — which
is why a bump surfaces as an honest 404 rather than a silently wrong
render.
