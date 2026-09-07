# minimal_launcher

A new Flutter project.

<!-- @generated-tour-gallery-start -->
## App tour

Styled stills from the committed guided tour - regenerated on every
tour run, so new screens appear here automatically.

| Welcome | Auth Login | Auth Register |
| :---: | :---: | :---: |
| ![Welcome][s01] | ![Auth Login][s02] | ![Auth Register][s03] |
| **Auth Reset Password** | **Launcher Home** | **Launch Drawer** |
| ![Auth Reset Password][s04] | ![Launcher Home][s05] | ![Launch Drawer][s06] |
| **Base Profile** | **Productivity Tasks** | **Productivity Task Compose** |
| ![Base Profile][s07] | ![Productivity Tasks][s08] | ![Task Compose][s09] |
| **Productivity Maintenance Readings** | **Productivity Maintenance Photo** | |
| ![Maintenance Readings][s10] | ![Productivity Maintenance Photo][s11] | |

The full tour lives in the [feature guide](marketing/tour/feature-guide.md),
with walkthrough videos alongside it in [`marketing/tour/`](marketing/tour).

[s01]: marketing/tour/store/01-welcome.png
[s02]: marketing/tour/store/02-auth_login.png
[s03]: marketing/tour/store/03-auth_register.png
[s04]: marketing/tour/store/04-auth_reset_password.png
[s05]: marketing/tour/store/05-launcher_home.png
[s06]: marketing/tour/store/06-launch_drawer.png
[s07]: marketing/tour/store/07-base_profile.png
[s08]: marketing/tour/store/08-productivity_tasks.png
[s09]: marketing/tour/store/09-productivity_task_compose.png
[s10]: marketing/tour/store/10-productivity_maintenance_readings.png
[s11]: marketing/tour/store/11-productivity_maintenance_photo.png
<!-- @generated-tour-gallery-end -->

<!-- @generated-render-strip-start -->
## Design review strip

[render-strip.html](marketing/tour/render-strip.html)
is one self-contained page of this app's real screens - rendered
headlessly from the code in this commit, before the tour's emulator
legs ran, with every point numbered from the widget's own measured
rectangle.

GitHub serves a committed .html file as source, so open it from a
local checkout (or download the raw file) to read the page.
<!-- @generated-render-strip-end -->

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
