import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_accessibility/apple_liquid_glass_accessibility.dart';
import 'package:apple_liquid_glass_example/frame_meter.dart';
import 'package:apple_liquid_glass_example/home.dart';
import 'package:apple_liquid_glass_example/settings.dart';
import 'package:flutter/widgets.dart';

class GalleryApp extends StatefulWidget {
  const GalleryApp({
    this.settings = const GallerySettings(),
    this.notifier,
    this.home = const GalleryHome(),
    super.key,
  });

  /// The page the app opens on.
  final Widget home;

  final GallerySettings settings;

  /// Holds the settings instead of the app, for a caller that reads or
  /// changes them.
  final ValueNotifier<GallerySettings>? notifier;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  late final _settings = widget.notifier ?? ValueNotifier(widget.settings);

  @override
  void dispose() {
    if (widget.notifier == null) _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GallerySettingsScope(
    notifier: _settings,
    child: ValueListenableBuilder(
      valueListenable: _settings,
      builder: (context, settings, _) => WidgetsApp(
        title: 'Liquid Glass',
        color: settings.accent.light,
        debugShowCheckedModeBanner: false,
        pageRouteBuilder: <T>(routeSettings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: routeSettings),
        builder: (context, child) => GlassScope(
          renderer: settings.renderer.renderer,
          data: GlassThemeData(
            brightness: settings.brightness,
            primaryColor: settings.accent.color,
          ),
          child: GlassPlatformTraits(
            child: GlassTraitsOverride(
              reduceTransparency: settings.reduceTransparency ? true : null,
              showBorders: settings.showBorders ? true : null,
              prefersCrossFade: settings.crossFade ? true : null,
              glassTintAmount: settings.glassTint,
              child: FrameMeter(
                shown: settings.frameMeter,
                child: const bool.fromEnvironment('GLASS_REPORT_OVERLAY')
                    ? LiquidGlassReportOverlay(child: _Ambient(child: child!))
                    : _Ambient(child: child!),
              ),
            ),
          ),
        ),
        home: widget.home,
      ),
    ),
  );
}

/// The text and icon style of everything the gallery draws itself.
class _Ambient extends StatelessWidget {
  const _Ambient({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: TextStyle(
      color: GlassDynamicColor.resolve(GlassColors.label, context),
    ),
    child: GlassDefaultTextStyle(
      role: GlassTextRole.body,
      child: IconTheme(
        data: IconThemeData(
          color: GlassDynamicColor.resolve(GlassColors.label, context),
          size: 22,
        ),
        child: child,
      ),
    ),
  );
}
