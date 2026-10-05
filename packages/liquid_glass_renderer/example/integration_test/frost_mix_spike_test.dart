import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import '../../test/src/capture_scenes.dart';

// The spike inspects the package-internal render object directly, and
// passes frostMix 1 explicitly where the default is the point of the check.
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: avoid_redundant_argument_values

/// Frost-mix spike: renders a toolbar-sized real glass over the striped
/// capture backdrop with today's single-pass frost and with the two-pass mix
/// (σ_fixed 16), writes one PNG per arm to /tmp/frost_mix, checks that the
/// mix at visibility 0 reproduces the bare backdrop, and emits a labelled
/// contact sheet.
///
///   flutter test -d macos integration_test/frost_mix_spike_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const boundaryKey = ValueKey('frost-mix-scene');
  const frosts = [2.0, 6.1, 16.6];
  // The macOS example app is sandboxed; the only writable location is its
  // container temp. The host side copies the files to /tmp/frost_mix.
  final outDir = Directory('${Directory.systemTemp.path}/frost_mix')
    ..createSync(recursive: true);
  debugPrint('FROST_MIX_OUT_DIR:${outDir.path}');

  setUpAll(LiquidGlass.precache);

  Future<ui.Image> render(
    WidgetTester tester, {
    double frost = 6.1,
    double frostMix = 1,
    double visibility = 1,
    bool bare = false,
  }) async {
    tester.view
      ..physicalSize = const Size(720, 480)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const CustomPaint(painter: CaptureBackdrop()),
              if (!bare)
                Center(
                  child: LiquidGlassLayer(
                    settings: LiquidGlassSettings.ios27ToolbarLight(
                      frost: frost,
                    ).copyWith(frostMix: frostMix),
                    defaultAppearance:
                        const LiquidGlassAppearance.ios27ToolbarLight(),
                    child: LiquidGlass(
                      shape: const LiquidRoundedSuperellipse(borderRadius: 22),
                      appearance: LiquidGlassAppearance.ios27ToolbarLight(
                        visibility: visibility,
                      ),
                      child: const SizedBox(width: 340, height: 52),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    return (await tester.runAsync(
      () => boundary.toImage(pixelRatio: tester.view.devicePixelRatio),
    ))!;
  }

  Future<Uint8List> rgba(WidgetTester tester, ui.Image image) async =>
      (await tester.runAsync(image.toByteData))!.buffer.asUint8List();

  Future<void> savePng(
    WidgetTester tester,
    ui.Image image,
    String name,
  ) async {
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    await tester.runAsync(
      () => File('${outDir.path}/$name.png').writeAsBytes(
        bytes!.buffer.asUint8List(),
      ),
    );
  }

  testWidgets('frost mix renders and visibility 0 is identity', (tester) async {
    final captures = <String, ui.Image>{};
    for (final frost in frosts) {
      for (final mix in [false, true]) {
        final name = 'frost${frost}_${mix ? "mix" : "current"}';
        // Mix arm: blur fixed at σ16, weight = frost / 16.
        final image = await render(
          tester,
          frost: mix ? 16.0 : frost,
          frostMix: mix ? frost / 16.0 : 1.0,
        );
        await savePng(tester, image, name);
        captures[name] = image;
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }

    // frostMix 1.0 is the fast path: byte-identical to the classic render.
    final fastPath = await render(tester, frost: 16.6, frostMix: 1);
    final classic = await render(tester, frost: 16.6);
    final fastPathBytes = await rgba(tester, fastPath);
    final classicBytes = await rgba(tester, classic);
    var identical = fastPathBytes.length == classicBytes.length;
    if (identical) {
      for (var i = 0; i < fastPathBytes.length; i++) {
        if (fastPathBytes[i] != classicBytes[i]) {
          identical = false;
          break;
        }
      }
    }
    debugPrint('FROST_MIX_FAST_PATH_IDENTICAL:$identical');
    expect(identical, isTrue);
    await savePng(tester, fastPath, 'frost16.6_frostMix1');
    fastPath.dispose();
    classic.dispose();
    await tester.pumpWidget(const SizedBox.shrink());

    final invisible = await render(
      tester,
      frost: 16,
      frostMix: 6.1 / 16.0,
      visibility: 0,
    );
    await savePng(tester, invisible, 'visibility0_mix');
    final bare = await render(tester, bare: true);
    await savePng(tester, bare, 'backdrop_bare');
    final a = await rgba(tester, invisible);
    final b = await rgba(tester, bare);
    expect(a.length, b.length);
    var maxDiff = 0;
    for (var i = 0; i < a.length; i++) {
      final d = (a[i] - b[i]).abs();
      if (d > maxDiff) maxDiff = d;
    }
    debugPrint('FROST_MIX_VISIBILITY0_MAX_CHANNEL_DIFF:$maxDiff');
    expect(maxDiff, 0);
    invisible.dispose();
    bare.dispose();

    // Labelled contact sheet: rows are frost values, columns current / mix.
    final cellW = captures.values.first.width.toDouble();
    final cellH = captures.values.first.height.toDouble();
    const columns = 2;
    final rows = (captures.length / columns).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    var index = 0;
    for (final entry in captures.entries) {
      final origin = Offset(
        (index % columns) * cellW,
        (index ~/ columns) * cellH,
      );
      canvas.drawImage(entry.value, origin, Paint());
      final paragraph =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(fontSize: 28, fontWeight: FontWeight.bold),
            )
            ..pushStyle(
              ui.TextStyle(
                color: const Color(0xFFFFFFFF),
                background: Paint()..color = const Color(0xCC000000),
              ),
            )
            ..addText(' ${entry.key} ');
      final label = paragraph.build()
        ..layout(ui.ParagraphConstraints(width: cellW));
      canvas.drawParagraph(label, origin + const Offset(16, 16));
      label.dispose();
      index++;
    }
    final sheet = await recorder.endRecording().toImage(
      (cellW * columns).round(),
      (cellH * rows).round(),
    );
    await savePng(tester, sheet, 'contact_sheet');
    sheet.dispose();
    for (final image in captures.values) {
      image.dispose();
    }
  });

  testWidgets('mix adds a sharp pass sharing the backdrop snapshot', (
    tester,
  ) async {
    // allRenderObjects reports each render object once per element that
    // resolves to it, so dedupe by identity before picking the active layer.
    RenderLiquidGlassLayer layer() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .where((layer) => layer.debugBackdropFilterLayer != null)
        .single;

    // Direct BackdropFilterLayer children of the clip the diffused pass sits
    // in; paint order is child order, so index 0 is the sharp pass.
    List<BackdropFilterLayer> clipFilters(RenderLiquidGlassLayer layer) {
      final clip = layer.debugBackdropFilterLayer!.parent!;
      final filters = <BackdropFilterLayer>[];
      var child = clip.firstChild;
      while (child != null) {
        if (child is BackdropFilterLayer) filters.add(child);
        child = child.nextSibling;
      }
      return filters;
    }

    // frostMix 1 is the fast path: one filter, no shared key.
    var image = await render(tester, frost: 16, frostMix: 1);
    final renderObject = layer();
    expect(clipFilters(renderObject), hasLength(1));
    expect(clipFilters(renderObject).single.backdropKey, isNull);
    image.dispose();

    void expectMixPasses() {
      final filters = clipFilters(renderObject);
      expect(filters, hasLength(2));
      expect(
        identical(filters.first, filters.last),
        isFalse,
        reason: 'sharp and diffused passes must be distinct filters',
      );
      expect(
        identical(filters.last, renderObject.debugBackdropFilterLayer),
        isTrue,
      );
      expect(filters.first.backdropKey, isNotNull);
      expect(
        identical(filters.first.backdropKey, filters.last.backdropKey),
        isTrue,
        reason: 'both passes share one backdrop snapshot',
      );
    }

    image = await render(tester, frost: 16, frostMix: .5);
    expect(identical(layer(), renderObject), isTrue);
    expectMixPasses();
    image.dispose();

    // Back at frostMix 1 on the same render object the sharp pass is gone.
    image = await render(tester, frost: 16, frostMix: 1);
    expect(identical(layer(), renderObject), isTrue);
    expect(clipFilters(renderObject), hasLength(1));
    expect(clipFilters(renderObject).single.backdropKey, isNull);
    final toggledBack = await rgba(tester, image);
    image.dispose();

    image = await render(tester, frost: 16, frostMix: .25);
    expect(identical(layer(), renderObject), isTrue);
    expectMixPasses();
    image.dispose();

    // frost 0 never takes the mix path.
    image = await render(tester, frost: 0, frostMix: .25);
    expect(identical(layer(), renderObject), isTrue);
    expect(clipFilters(renderObject), hasLength(1));
    expect(clipFilters(renderObject).single.backdropKey, isNull);
    image.dispose();

    // frostMix 0 is still two passes (sharp under a zero-weight diffused
    // pass); no optimization is required at this endpoint.
    image = await render(tester, frost: 16, frostMix: 0);
    expect(identical(layer(), renderObject), isTrue);
    expectMixPasses();
    image.dispose();

    // Returning to the fast path must render exactly like a freshly mounted
    // single-pass scene — no stale sharp pass, key or uniforms.
    await tester.pumpWidget(const SizedBox.shrink());
    final fresh = await render(tester, frost: 16);
    expect(await rgba(tester, fresh), toggledBack);
    fresh.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
