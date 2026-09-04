# minimal_launcher

A new Flutter project.

<!-- @generated-tour-gallery-start -->
## App tour

Styled stills from the committed guided tour - regenerated on every
tour run, so new screens appear here automatically.

| Welcome | Auth Login | Auth Register |
| :---: | :---: | :---: |
| ![Welcome][s01] | ![Auth Login][s02] | ![Auth Register][s03] |
| **Auth Reset Password** | **Launcher Home** | **Launch Dark Mode** |
| ![Reset Password][s04] | ![Launcher Home][s05] | ![Launch Dark Mode][s06] |
| **Launch Drawer** | **Base Profile** | **Productivity Tasks** |
| ![Launch Drawer][s07] | ![Base Profile][s08] | ![Productivity Tasks][s09] |

The full tour lives in the [feature guide](marketing/tour/feature-guide.md),
with walkthrough videos alongside it in [`marketing/tour/`](marketing/tour).

[s01]: marketing/tour/store/01-welcome.png
[s02]: marketing/tour/store/02-auth_login.png
[s03]: marketing/tour/store/03-auth_register.png
[s04]: marketing/tour/store/04-auth_reset_password.png
[s05]: marketing/tour/store/05-launcher_home.png
[s06]: marketing/tour/store/06-launch_dark_mode.png
[s07]: marketing/tour/store/07-launch_drawer.png
[s08]: marketing/tour/store/08-base_profile.png
[s09]: marketing/tour/store/09-productivity_tasks.png
<!-- @generated-tour-gallery-end -->

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

<!-- @generated-recompose-start -->
## Recomposing this app

`lib/` is fully installer-generated and disposable - it is safe to delete
and is gitignored. Anything app-specific lives in tracked manifests
(`app_routes`, or `host_routes` in `composer.json`), never in `lib/` itself.

To regenerate it:

```sh
python3 .rokct/initiate.py   # provisions the composer under .rokct/skills/
python3 .rokct/skills/.rok/flutter/scripts/compose.py
```

Session cleanup (`python3 .rokct/end_protocol.py`) wipes the provisioned
tools again.
<!-- @generated-recompose-end -->
