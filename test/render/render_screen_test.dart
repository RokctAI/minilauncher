// Copyright (c) 2026 ROKCT INTELLIGENCE (PTY) LTD
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, version 3.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

// Render harness for the Minilauncher shell - the launcher home screen.
//
// Adapted from RokctAI/shared-workflows templates/render-harness/
// render_screen_test.dart; conventions, numbering rules and the status
// vocabulary live in that repo's scripts/render/README.md. Everything below
// the "proven mechanism" divider is the template verbatim - the fixed-point
// height measurement, the real-event-loop drain, the RepaintBoundary capture
// and the rect sidecar are what make the output composable by
// scripts/render/compose_strip.py.
//
// The screen: LauncherHomePage (launch_sdk's home_page template, installed
// by the composer at lib/presentation/pages/launch/home.dart). It is the
// screen this shell exists for - the tour's `launcher_home` step and the
// Play feature graphic both point at it.
//
// Where the data comes from, honestly:
//   * Theme (light/dark) is the app's own path - LocalStorage's app theme
//     mode, read by base_sdk's AppNotifier through appProvider, exactly as
//     a real launch does.
//   * The app list is NOT demo data from an SDK, because launch_sdk has no
//     demo path: `launchProvider` constructs `LaunchRepository` directly and
//     that repository talks to the `installed_apps` platform channel. There
//     is no `AppConstants.isDemo` branch to switch, and nothing in this
//     shell's composed SDKs registers one. So this harness takes the
//     documented exception (template marker 4/8) at the LOWEST seam
//     available: it mocks the `installed_apps` MethodChannel and returns a
//     small fixed device inventory. Everything above the channel -
//     LaunchRepository, InstalledApps.getInstalledApps, AppInfo.parseList,
//     LaunchNotifier's sort/filter, the whole widget tree - is the shipped
//     code path. The strip config says so in its notes.
//
// Run:
//   flutter test --dart-define=IS_DEMO=true test/render/render_screen_test.dart
//   RENDER_SUFFIX=_draft flutter test --dart-define=IS_DEMO=true \
//       test/render/render_screen_test.dart

// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:base_sdk/base_sdk.dart';
import 'package:base_sdk/src/presentation/theme/app_style.dart';
import 'package:launch_sdk/launch_sdk.dart';
import 'package:launcher/presentation/pages/launch/home.dart';
import 'package:launcher/presentation/pages/launch/widgets/app_item.dart';

// ---------------------------------------------------------------------------
// Render settings - phone size the reviews are judged at. Only change these
// if the whole review is moving to a different device class.
// ---------------------------------------------------------------------------

/// Logical width of the frame (iPhone-class phone). The strip composer scales
/// the PNG to the bezel, so this only affects LAYOUT, not output resolution.
const double kLogicalWidth = 390;

/// Device pixel ratio the PNG is captured at (3 = @3x, crisp on any display).
const double kDevicePixelRatio = 3.0;

/// Tall probe viewport for the first pass. Must exceed the tallest screen; the
/// second pass shrinks to the measured content height.
const double kProbeHeight = 2600;

/// Slack below the last element in the final frame, in logical pixels.
const double kBottomPadding = 20;

/// The design size base_sdk's AppWidget hands ScreenUtilInit for a compact
/// (phone-shaped) window. Mirrored here so `.w`/`.h`/`.sp`/`.r` inside the
/// composed widgets scale exactly as they do in the running app.
const Size kDesignSize = Size(375, 812);

/// The device inventory the mocked `installed_apps` channel reports.
///
/// This is the harness's ONE hand-written input, and it exists only because
/// launch_sdk has no demo repository to borrow (see the header). Keys match
/// what the plugin's Android side sends and what `AppInfo.create` reads, so
/// the real parse/sort path runs over it unchanged. Deliberately listed out
/// of alphabetical order: `LaunchNotifier.loadApps` sorts, and the render is
/// evidence that it does.
const List<Map<String, Object?>> kDeviceApps = <Map<String, Object?>>[
  <String, Object?>{
    'name': 'Messages',
    'package_name': 'com.example.messaging',
    'version_name': '11.4.2',
    'version_code': 110402,
    'platform_type': 'native_or_others',
    'installed_timestamp': 1735689600000,
    'is_system_app': true,
    'is_launchable_app': true,
    'category': 4,
  },
  <String, Object?>{
    'name': 'Calculator',
    'package_name': 'com.example.calculator',
    'version_name': '8.0.1',
    'version_code': 80001,
    'platform_type': 'native_or_others',
    'installed_timestamp': 1735689600000,
    'is_system_app': true,
    'is_launchable_app': true,
    'category': 7,
  },
  <String, Object?>{
    'name': 'Camera',
    'package_name': 'com.example.camera',
    'version_name': '9.2.0',
    'version_code': 90200,
    'platform_type': 'native_or_others',
    'installed_timestamp': 1735689600000,
    'is_system_app': true,
    'is_launchable_app': true,
    'category': 3,
  },
  <String, Object?>{
    'name': 'Photos',
    'package_name': 'com.example.photos',
    'version_name': '6.51.0',
    'version_code': 65100,
    'platform_type': 'native_or_others',
    'installed_timestamp': 1735689600000,
    'is_system_app': false,
    'is_launchable_app': true,
    'category': 3,
  },
  <String, Object?>{
    'name': 'Clock',
    'package_name': 'com.example.clock',
    'version_name': '7.3.1',
    'version_code': 70301,
    'platform_type': 'native_or_others',
    'installed_timestamp': 1735689600000,
    'is_system_app': true,
    'is_launchable_app': true,
    'category': 7,
  },
  <String, Object?>{
    'name': 'Settings',
    'package_name': 'com.example.settings',
    'version_name': '14.0.0',
    'version_code': 140000,
    'platform_type': 'native_or_others',
    'installed_timestamp': 1735689600000,
    'is_system_app': true,
    'is_launchable_app': true,
    'category': 7,
  },
  <String, Object?>{
    'name': 'Maps',
    'package_name': 'com.example.maps',
    'version_name': '11.126.0',
    'version_code': 1112600,
    'platform_type': 'native_or_others',
    'installed_timestamp': 1735689600000,
    'is_system_app': false,
    'is_launchable_app': true,
    'category': 6,
  },
  <String, Object?>{
    'name': 'Phone',
    'package_name': 'com.example.dialer',
    'version_name': '128.0.4',
    'version_code': 1280004,
    'platform_type': 'native_or_others',
    'installed_timestamp': 1735689600000,
    'is_system_app': true,
    'is_launchable_app': true,
    'category': -1,
  },
];

/// Template marker 4/8 - the documented exception, taken at the platform
/// channel rather than at a Dart seam.
///
/// `installed_apps` is the only channel this screen reaches for. Mocking it
/// keeps LaunchRepository, the plugin's own decoding and LaunchNotifier real;
/// a Dart-level fake would have replaced all three. Unknown methods return
/// null loudly rather than pretending to succeed.
void registerExceptionStubs() {
  const MethodChannel channel = MethodChannel('installed_apps');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getInstalledApps') {
          return kDeviceApps;
        }
        throw UnimplementedError(
          'installed_apps: the render harness only answers getInstalledApps, '
          'but the screen called ${call.method}',
        );
      });
}

/// Template marker 2/8 - the SDKs' own demo data.
///
/// Nothing to register for this screen, and that is the finding rather than
/// an omission. `LauncherHomePage` resolves only optional things from GetIt -
/// a `LaunchGlanceSource` and any registered `LaunchWindowSource` - and no SDK
/// composed into this shell registers either, so both of those slots render
/// zero-size. (The glance rows that DO appear are not from GetIt: they are
/// injected into the page source at the `@launcher-glance` marker by
/// productivity_sdk's manifest at compose time, so they are part of the
/// composed code rather than data.) The app list comes from `launchProvider`,
/// which news up `LaunchRepository` directly and never consults GetIt or
/// `AppConstants.isDemo`.
///
/// `BaseSdkDependencies.register` is deliberately NOT called: this screen
/// reads none of the kernel facades, and the registration starts
/// `ConnectivityService`, whose connectivity_plus event channel has no
/// implementation under `flutter test` and would fail the render with an
/// unhandled asynchronous error rather than a picture.
Future<void> registerDemoDependencies() async {}

/// Template marker 3/8 - device history the demo mode cannot supply.
///
/// Empty, and expected to stay empty: the launcher home derives nothing from
/// an accumulated local store.
Future<void> seedDeviceHistory(WidgetTester tester) async {}

/// Template marker 5/8 - sections / routes / gates.
///
/// The launcher home has no section registry and no visibility gates; its
/// only branch is the app-list state, which the channel mock drives.
void registerScreen() {}

/// Template marker 6/8 - the widget under test.
///
/// Mirrors this shell's own `lib/presentation/app_widget.dart` for a compact
/// window: ProviderScope, then ScreenUtilInit at the app's design size, then a
/// MaterialApp carrying the app's `theme`, its `darkTheme` and its `themeMode`.
/// `LauncherHomePage` itself is the real composed page, unwrapped and
/// unmodified.
///
/// The two ThemeDatas are copied from AppWidget deliberately and are not
/// decoration: widgets that style text with a bare `TextStyle` (base_sdk's
/// GlanceCard rows, for one) take their colour from the active theme, so a
/// harness that passed only `theme:` would render them in light-theme ink on
/// the dark frame and invent a contrast bug the app does not have.
///
/// The page reads its own light/dark from `appProvider`, which reads
/// LocalStorage - so [renderVariant] sets the stored theme mode before the
/// first pump rather than passing `dark` down through this wrapper.
Widget buildScreen({required bool dark}) {
  return ProviderScope(
    child: ScreenUtilInit(
      useInheritedMediaQuery: false,
      designSize: kDesignSize,
      builder: (BuildContext context, Widget? child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: false,
          brightness: Brightness.light,
          scaffoldBackgroundColor: AppStyle.surfaceLightRaw,
          appBarTheme: const AppBarTheme(
            systemOverlayStyle: AppStyle.systemUiOverlay,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: false,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppStyle.surfaceDarkRaw,
          appBarTheme: const AppBarTheme(
            systemOverlayStyle: AppStyle.systemUiOverlay,
          ),
        ),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: const LauncherHomePage(),
      ),
    ),
  );
}

/// Template marker 7/8 - the elements the review points at.
///
/// Keys are the stable identities the composer binds numbers to; app rows are
/// keyed by package name (a display name is prose and can be relabelled, a
/// package name cannot).
///
/// Deliberately NOT numbered, and each for a reason worth knowing:
///   * the second GlanceCard (the GetIt LaunchGlanceSource seam) and
///     LauncherWindowHost both render zero-size here - nothing registers a
///     source in this shell - so a chip on either would point at nothing;
///   * LauncherDrawerHandle is bottom-anchored, so numbering it would make
///     the measured content height equal the viewport height and the frame
///     would converge on the probe viewport instead of the page. It is the
///     strip at the foot of both frames; [bottomChromeHeight] is what keeps
///     it inside them.
List<ElementSpec> elementSpecs() {
  return <ElementSpec>[
    ElementSpec(
      key: 'launch.home.theme_toggle',
      label: 'Theme toggle - sun/moon, writes the stored app theme mode',
      finder: find.byWidgetPredicate(
        (Widget w) => w is GestureDetector && w.child is Icon,
      ),
    ),
    ElementSpec(
      key: 'launch.home.auth_control',
      label: 'Account control - launch_sdk LauncherAuthControl',
      finder: find.byType(LauncherAuthControl),
    ),
    ElementSpec(
      key: 'launch.home.glance',
      label:
          'Glance card - the rows productivity_sdk injects at '
          '@launcher-glance',
      finder: find.byType(GlanceCard).first,
    ),
    ElementSpec.each(
      keyOf: (int i, Widget w) =>
          'launch.home.app_row.${(w as LauncherAppItem).app.packageName}',
      labelOf: (int i, Widget w) =>
          'App row - ${(w as LauncherAppItem).app.name}',
      finder: find.byType(LauncherAppItem),
    ),
  ];
}

/// Vertical space the frame must reserve BELOW the measured content.
///
/// NOT in the shared template - see the note on [renderVariant]. The launcher
/// home is a viewport-bound page: its app list is an `Expanded` child with
/// `LauncherDrawerHandle` anchored under it. Shrinking the frame to the last
/// app row alone therefore shrinks the list too and clips that row behind the
/// handle. Reserving the handle's own height fixes the frame at a size where
/// every row and the handle are both fully drawn.
double bottomChromeHeight(WidgetTester tester) {
  final Finder handle = find.byWidgetPredicate(
    (Widget w) => w.runtimeType.toString() == 'LauncherDrawerHandle',
  );
  if (handle.evaluate().isEmpty) return 0;
  return tester.getRect(handle.first).height;
}

/// Template marker 8/8 - real fonts.
///
/// Without real faces every glyph renders as the Ahem/FlutterTest block font
/// and the PNG is worthless, so this never fails silently: if no usable text
/// face is found anywhere the render aborts.
///
/// This shell bundles no font assets - base_sdk styles the app through
/// `google_fonts`, which fetches Inter and Montserrat over the network at
/// runtime. There is no network in a widget test (and runtime fetching is
/// switched off below so a miss is loud), so the faces are registered here
/// from files, under the family names google_fonts asks for: the per-weight
/// variant families (`Inter_600`) plus the plain family that
/// `fontFamilyFallback` lands on.
///
/// Face preference, first hit wins: real Inter/Montserrat dropped into
/// test/render/fonts/, then whatever real sans the runner has. A substitute
/// face keeps glyphs, colour and layout honest but shifts text metrics, so
/// the strip config's notes say which one the run used.
Future<void> loadRealFonts() async {
  final String root = Directory.current.path;

  Future<void> load(String family, List<String> files) async {
    final FontLoader loader = FontLoader(family);
    for (final String path in files) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  String? firstExisting(List<String> candidates) {
    for (final String path in candidates) {
      if (path.isNotEmpty && File(path).existsSync()) return path;
    }
    return null;
  }

  final String? regular = firstExisting(<String>[
    '$root/test/render/fonts/Inter-Regular.ttf',
    '/usr/share/fonts/truetype/inter/Inter-Regular.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf',
    '/usr/share/fonts/TTF/DejaVuSans.ttf',
    '/System/Library/Fonts/Supplemental/Arial.ttf',
  ]);
  final String bold =
      firstExisting(<String>[
        '$root/test/render/fonts/Inter-Bold.ttf',
        '/usr/share/fonts/truetype/inter/Inter-Bold.ttf',
        '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
        '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
        '/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf',
        '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf',
        '/usr/share/fonts/TTF/DejaVuSans-Bold.ttf',
        '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
      ]) ??
      regular ??
      '';

  if (regular == null) {
    throw StateError(
      'render harness: no text face found. Every glyph would render as the '
      'FlutterTest block font, which makes the PNG worthless. Drop real '
      'Inter faces into test/render/fonts/ (Inter-Regular.ttf, '
      'Inter-Bold.ttf) or install a system sans on the runner.',
    );
  }
  // ignore: avoid_print
  print('render harness: text face = $regular (bold: $bold)');

  // AppStyle asks google_fonts for Inter at 400/500/600/700 and Montserrat at
  // 400/700/900; `regular` is w400 in google_fonts' variant naming.
  const List<String> lightVariants = <String>['regular', '500'];
  const List<String> heavyVariants = <String>['600', '700', '900'];
  for (final String family in <String>['Inter', 'Montserrat']) {
    for (final String variant in lightVariants) {
      await load('${family}_$variant', <String>[regular]);
    }
    for (final String variant in heavyVariants) {
      await load('${family}_$variant', <String>[bold]);
    }
    // fontFamilyFallback lands on the plain family name.
    await load(family, <String>[regular]);
  }
  // Bare TextStyles with no family fall back to the platform default.
  await load('Roboto', <String>[regular]);

  // Icon fonts. MaterialIcons ships inside the Flutter SDK cache; remixicon
  // (the launcher's sun/moon toggle and the search field's magnifier) lives in
  // the pub cache under its package-scoped family name.
  final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final String? materialIcons = firstExisting(<String>[
    if (flutterRoot != null)
      '$flutterRoot/bin/cache/artifacts/material_fonts/'
          'MaterialIcons-Regular.otf',
  ]);
  if (materialIcons != null) {
    await load('MaterialIcons', <String>[materialIcons]);
  }
  final String? remix = _findInPubCache('remixicon', 'fonts/Remix.ttf');
  if (remix != null) {
    await load('packages/remixicon/Remix', <String>[remix]);
  } else {
    // ignore: avoid_print
    print(
      'render harness: remixicon font not found in the pub cache - the '
      'toggle and search icons will render as tofu.',
    );
  }
}

/// Absolute path to [relative] inside the newest cached copy of [package],
/// or null when the package is not in the pub cache.
String? _findInPubCache(String package, String relative) {
  final String pubCache =
      Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['HOME']}/.pub-cache';
  final Directory hosted = Directory('$pubCache/hosted');
  if (!hosted.existsSync()) return null;
  final List<String> matches = <String>[];
  for (final FileSystemEntity host in hosted.listSync()) {
    if (host is! Directory) continue;
    for (final FileSystemEntity entry in host.listSync()) {
      if (entry is! Directory) continue;
      final String name = entry.path.split(Platform.pathSeparator).last;
      if (name.startsWith('$package-') &&
          File('${entry.path}/$relative').existsSync()) {
        matches.add('${entry.path}/$relative');
      }
    }
  }
  if (matches.isEmpty) return null;
  matches.sort();
  return matches.last;
}

// ===========================================================================
// Below here is the proven mechanism. Leave it alone.
// ===========================================================================

/// One numbered point: a finder, a stable key, and a human label.
class ElementSpec {
  ElementSpec({required this.key, required this.label, required this.finder})
    : keyOf = null,
      labelOf = null;

  /// A finder that matches SEVERAL widgets (e.g. every settings row); key and
  /// label are derived per match, so the numbering stays per-row.
  ElementSpec.each({
    required this.keyOf,
    required this.labelOf,
    required this.finder,
  }) : key = '',
       label = '';

  final String key;
  final String label;
  final Finder finder;
  final String Function(int index, Widget widget)? keyOf;
  final String Function(int index, Widget widget)? labelOf;
}

class _Measured {
  _Measured(this.key, this.label, this.rect);

  final String key;
  final String label;
  final Rect rect;
}

/// Mocks the path_provider channel so real drift/sqlite stores can open a
/// database in a temp dir. This is the ONLY platform channel the harness
/// fakes beyond the one named in marker 4/8 - everything else runs its real
/// code path.
void _mockPathProvider(String dir) {
  const MethodChannel channel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async => dir);
}

/// Lets REAL async work (drift isolate, futures, file IO) complete, then pumps
/// frames so the resulting setStates land.
///
/// `pumpAndSettle` cannot do this: widget-test fake-async never runs the real
/// event loop, so a screen that waits on a real Future settles as empty.
Future<void> _drain(WidgetTester tester, {int rounds = 8}) async {
  for (int i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump(const Duration(milliseconds: 250));
  }
}

List<_Measured> _measure(WidgetTester tester, List<ElementSpec> specs) {
  final List<_Measured> measured = <_Measured>[];
  for (final ElementSpec spec in specs) {
    final List<Element> elements = spec.finder.evaluate().toList();
    for (int i = 0; i < elements.length; i++) {
      try {
        final Widget widget = elements[i].widget;
        measured.add(
          _Measured(
            spec.keyOf?.call(i, widget) ?? spec.key,
            spec.labelOf?.call(i, widget) ?? spec.label,
            tester.getRect(spec.finder.at(i)),
          ),
        );
      } catch (_) {
        // Off-stage or unlaid-out matches are skipped rather than failing the
        // render: a section hidden by a gate is a legitimate outcome.
      }
    }
  }

  // Top-to-bottom, then drop wrappers that share a rect with a more specific
  // match (a decorated card whose child is the row we already measured).
  //
  // DIVERGENCE from the shared template, and a candidate fix for it: the
  // template compares only top and height, which reads two controls sitting
  // SIDE BY SIDE on one row as a wrapper/child pair and silently drops one of
  // them. This page's theme toggle and account control are both 24x24 at the
  // same top, so the account control disappeared. A wrapper shares its child's
  // left edge as well, so requiring that too keeps the heuristic's intent and
  // stops it eating horizontal siblings.
  measured.sort((_Measured a, _Measured b) => a.rect.top.compareTo(b.rect.top));
  final List<_Measured> deduped = <_Measured>[];
  for (final _Measured item in measured) {
    final bool clash = deduped.any(
      (_Measured kept) =>
          (kept.rect.top - item.rect.top).abs() < 2 &&
          (kept.rect.left - item.rect.left).abs() < 2 &&
          (kept.rect.height - item.rect.height).abs() < 4,
    );
    if (!clash) deduped.add(item);
  }
  return deduped;
}

/// Renders one variant end to end and writes `out/<name>.png` plus
/// `out/<name>.json`.
Future<void> renderVariant(
  WidgetTester tester, {
  required bool dark,
  required String name,
  required String dbDir,
}) async {
  final Directory outDir = Directory('${Directory.current.path}/out')
    ..createSync(recursive: true);

  _mockPathProvider(dbDir);

  // App-wide state the screen reads before it builds. The launcher home takes
  // its light/dark from appProvider, which reads it back out of LocalStorage -
  // the same path `changeTheme` writes on a real tap of the sun/moon toggle.
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await tester.runAsync(() async {
    await LocalStorage.init();
    await LocalStorage.setAppThemeMode(dark);
  });
  AppStyle.setBrightness(dark ? Brightness.dark : Brightness.light);

  await tester.runAsync(_loadRealFontsOnce);

  // Order matters. Exception stubs go in FIRST so guarded SDK registrations
  // stand aside; then the SDKs register their own demo implementations; then
  // any device history the demo mode cannot supply.
  registerExceptionStubs();
  await tester.runAsync(registerDemoDependencies);
  await seedDeviceHistory(tester);
  registerScreen();

  tester.view.physicalSize = Size(
    kLogicalWidth * kDevicePixelRatio,
    kProbeHeight * kDevicePixelRatio,
  );
  tester.view.devicePixelRatio = kDevicePixelRatio;
  addTearDown(tester.view.reset);

  final GlobalKey boundaryKey = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: buildScreen(dark: dark),
    ),
  );
  await _drain(tester);

  // Pass 1 measures the real content height in the tall probe viewport; pass 2
  // re-renders at exactly that height so the PNG is a full-length strip with
  // no dead space. Two passes are REQUIRED, not an optimisation: screenutil
  // `.h` sizes scale with the viewport, so the height converges to a fixed
  // point rather than being known up front.
  List<_Measured> measured = _measure(tester, elementSpecs());
  expect(
    measured,
    isNotEmpty,
    reason:
        'no elements matched - check elementSpecs() and the gates in '
        'registerScreen()',
  );

  final double contentBottom = measured
      .map((_Measured m) => m.rect.bottom)
      .reduce((double a, double b) => a > b ? a : b);
  // `bottomChromeHeight` is this shell's addition to the template formula:
  // without it a viewport-bound page shrinks its own scroll area and clips the
  // last row it was measured from.
  final double targetHeight =
      (contentBottom + bottomChromeHeight(tester) + kBottomPadding)
          .clamp(400.0, kProbeHeight)
          .toDouble();

  tester.view.physicalSize = Size(
    kLogicalWidth * kDevicePixelRatio,
    targetHeight * kDevicePixelRatio,
  );
  await tester.pump(const Duration(milliseconds: 50));
  await _drain(tester, rounds: 4);
  measured = _measure(tester, elementSpecs());

  await tester.runAsync(() async {
    final RenderRepaintBoundary boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(
      pixelRatio: kDevicePixelRatio,
    );
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    File(
      '${outDir.path}/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());

    // Sidecar consumed by scripts/render/compose_strip.py. `number` is a
    // convenience only - the composer re-derives stable global numbers from
    // `key`, so a new element never renumbers the ones already reviewed.
    final Map<String, Object?> sidecar = <String, Object?>{
      'variant': name,
      'logicalWidth': kLogicalWidth,
      'logicalHeight': targetHeight,
      'devicePixelRatio': kDevicePixelRatio,
      'elements': <Object>[
        for (int i = 0; i < measured.length; i++)
          <String, Object?>{
            'number': i + 1,
            'key': measured[i].key,
            'label': measured[i].label,
            'x': measured[i].rect.left,
            'y': measured[i].rect.top,
            'w': measured[i].rect.width,
            'h': measured[i].rect.height,
          },
      ],
    };
    File(
      '${outDir.path}/$name.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(sidecar));
  });
}

bool _fontsLoaded = false;
Future<void> _loadRealFontsOnce() async {
  if (_fontsLoaded) return;
  await loadRealFonts();
  _fontsLoaded = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Never let a test reach out for a webfont: the render must be reproducible
  // offline, and a silent fetch failure is a silent Ahem fallback.
  GoogleFonts.config.allowRuntimeFetching = false;

  final String dbDir = Directory.systemTemp
      .createTempSync('render_harness_db')
      .path;

  // RENDER_SUFFIX distinguishes runs of the SAME harness against different
  // checkouts (e.g. `_draft` for the PR heads, empty for main), so both sets
  // of outputs can sit in one out/ dir and be composed into one page.
  final String suffix = Platform.environment['RENDER_SUFFIX'] ?? '';

  testWidgets('render launcher home - dark', (WidgetTester tester) async {
    await renderVariant(
      tester,
      dark: true,
      name: 'launcher_home_dark$suffix',
      dbDir: dbDir,
    );
  });

  testWidgets('render launcher home - light', (WidgetTester tester) async {
    await renderVariant(
      tester,
      dark: false,
      name: 'launcher_home_light$suffix',
      dbDir: dbDir,
    );
  });
}
