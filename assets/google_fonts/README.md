# Bundled Google Fonts faces

The exact `.ttf` files the `google_fonts` package fetches at runtime for the
faces `base_sdk`'s `AppStyle` asks for (`GoogleFonts.inter`,
`GoogleFonts.montserrat`), bundled here as assets instead.

`Montserrat-BoldItalic.ttf` is the one `AppStyle.logoFontBoldItalic` asks for —
the app-name wordmark on `LoginPage`. It was added when the render harness
started rendering that page rather than the sign-in sheet alone: with
`allowRuntimeFetching = false` a missing face does not fall back, it throws.

Why they are committed: `google_fonts` checks the app's own assets before it
reaches for the network, and it matches an asset by filename
(`<Family>-<Variant>.ttf`). With these present the app renders its real
typography with no runtime fetch and no first-run fallback flash — and, the
reason they were added, `test/render/render_screen_test.dart` can render a
review frame headlessly with the app's real faces instead of the
Ahem/FlutterTest block font. See RokctAI/shared-workflows
`scripts/render/README.md` §2.4.

Provenance: downloaded from `https://fonts.gstatic.com/s/a/<sha256>.ttf`,
where each `<sha256>` is the hash `google_fonts` itself pins for that variant,
so the bytes are identical to what the package would otherwise fetch.

| File | SHA-256 |
|---|---|
| `Inter-Regular.ttf` | `ecdb53099b1a68cd24c6900ea5beeafec81bd3c8cb9d0f3c51b9986583ba3982` |
| `Inter-Medium.ttf` | `492dec3bc33255f9d81bd5fb18704ad72f96f9b9318e4171bc9f9be9dd4bf44b` |
| `Inter-SemiBold.ttf` | `d7ba633bab7f40576e539a7e934a1301d7618dceea59c743de477c2c493462fc` |
| `Inter-Bold.ttf` | `b7e339223d56e8c4210c86f1ba87b3d43d6c47e03956ea56f0a7a938ae61b2a3` |
| `Montserrat-Regular.ttf` | `e3bb63f2cd246ff159b0841c2bd55d0914291a93487340cfa27574cc8d1861dd` |
| `Montserrat-Bold.ttf` | `f7d4074869afb39d444728a57fe9d7dd18321cd8b7f94f014e8429c7a7b95c96` |
| `Montserrat-BoldItalic.ttf` | `091a994866ca5994bc4d8954b7eacf09d415fb7faded21f1621b13c57baa0299` |

Licence: SIL Open Font Licence 1.1 — see `OFL.txt`. Inter © The Inter Project
Authors; Montserrat © The Montserrat Project Authors.
