part of 'bar.dart';

class _LinkScope extends InheritedWidget {
  const _LinkScope({required this.link, required super.child});

  final GlassPageBarLink link;

  @override
  bool updateShouldNotify(_LinkScope oldWidget) => false;
}

/// The z-slot a glass page route gives its navigator's bars: an
/// [OverlayPortal] around the page's content, whose overlay child is the
/// bar view while the page is the host's painter.
///
/// The overlay child paints right above the route's page and below every
/// later route, inherits the route's themes, direction and media query,
/// and is neither painted nor hit while the route is offstage. It sits
/// outside the page's card and swipe: the bars stay while the page moves.
@internal
class GlassBarSlot extends StatefulWidget {
  /// Gives [link]'s page a slot around [child].
  const GlassBarSlot({required this.link, required this.child, super.key});

  /// The page's link.
  final GlassPageBarLink link;

  /// The page's content.
  final Widget child;

  @override
  State<GlassBarSlot> createState() => _GlassBarSlotState();
}

class _GlassBarSlotState extends State<GlassBarSlot> {
  final _portal = OverlayPortalController();
  ValueListenable<GlassPageBarLink?>? _painter;

  @override
  void initState() {
    super.initState();
    _portal.show();
    _follow();
  }

  @override
  void didUpdateWidget(GlassBarSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.link.host, widget.link.host)) _follow();
  }

  @override
  void dispose() {
    _painter?.removeListener(_painted);
    super.dispose();
  }

  void _follow() {
    _painter?.removeListener(_painted);
    _painter = widget.link.host.painter;
    _painter!.addListener(_painted);
  }

  // Another page's slot takes the bars, or this one does: a page's event,
  // not a frame of motion.
  void _painted() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final host = link.host;
    return _LinkScope(
      link: link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => identical(host.painter.value, link)
            ? KeyedSubtree(
                key: host.viewKey,
                child: GlassBarView(host: host),
              )
            : const SizedBox.shrink(),
        child: widget.child,
      ),
    );
  }
}

/// The bars of [host]: the navigation bar's row under the status bar and
/// the toolbar's row 28 points above the screen's bottom (8 above a
/// keyboard), each with its capsules and their buttons; with [only], that
/// bar alone, filling the box it is given.
///
/// Each bar builds in a [LayoutBuilder], so a page that declares while it
/// builds reaches it in the same frame.
@internal
class GlassBarView extends StatelessWidget {
  /// Creates the view of [host].
  const GlassBarView({required this.host, this.only, super.key});

  /// The bars.
  final GlassBarHost host;

  /// The one bar to draw in the given box, or null for both in their
  /// places on the screen.
  final GlassBarKind? only;

  @override
  Widget build(BuildContext context) {
    for (final bar in host._bars.values) {
      bar.tint = GlassDynamicColor.resolve(
        bar.itemStyleOf(context)?.prominentColor ??
            GlassTheme.primaryColorOf(context) ??
            _prominentColor,
        context,
      );
    }
    final only = this.only;
    if (only != null) return _Band(bar: host._bars[only]!);
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: media.padding.top,
          left: 0,
          right: 0,
          height: GlassNavigationBar.height,
          child: _Band(bar: host._bars[GlassBarKind.navigation]!),
        ),
        Positioned(
          bottom: keyboard > 0
              ? keyboard + GlassToolbar.keyboardInset
              : GlassToolbar.bottomInset,
          left: 0,
          right: 0,
          height: GlassBarMetrics.toolbar.capsuleHeight,
          child: _Band(bar: host._bars[GlassBarKind.toolbar]!),
        ),
      ],
    );
  }

  /// The prominent capsule's tint without a primary color (device).
  static const _prominentColor = Color(0xFF0088FF);
}

/// The space between the screen's sides and a navigation bar's outer
/// items: 16 on a 402 point screen (bars passport); the Pro Max's 20 is not
/// followed (approximation).
@internal
const double navigationSideInset = 16;

/// Cuts off what moves above the clipped box's top, and nothing below: a
/// pulled large title still follows the content down.
@internal
class BelowTop extends CustomClipper<Rect> {
  /// Creates the clipper.
  const BelowTop();

  @override
  Rect getClip(Size size) => const Rect.fromLTRB(-100000, 0, 100000, 100000);

  @override
  bool shouldReclip(BelowTop oldClipper) => false;
}

// One bar's row: its glass and its buttons, rebuilt during its layout. It
// owns the zones of the bar's items while it shows them.
class _Band extends StatefulWidget {
  const _Band({required this.bar});

  final _Bar bar;

  @override
  State<_Band> createState() => _BandState();
}

class _BandState extends State<_Band> {
  final _zones = InputZonesController<Object>();

  _Bar get bar => widget.bar;

  @override
  void initState() {
    super.initState();
    bar.zones = _zones;
  }

  @override
  void didUpdateWidget(_Band oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.bar, bar)) return;
    oldWidget.bar.letGo(_zones);
    bar.zones = _zones;
  }

  @override
  void dispose() {
    bar.letGo(_zones);
    _zones.dispose();
    super.dispose();
  }

  InputZone<Object> _zoneOf(BuildContext context, Object id, _Button button) {
    final input = bar.inputOf(id);
    final item = button.item;
    final action = _actionOf(button);
    final menu = action.menu != null;
    input.onPressed = action.onPressed;
    final hold = menu && action.onPressed != null;
    return InputZone<Object>(
      id: id,
      interactions: menu ? input.menuSource : input.press,
      enabled: action.enabled,
      reach: glassButtonReach,
      semantics: SemanticsProperties(
        label: switch (button.back) {
          final back? => back.labelIn(context),
          null => _labelOf(item!),
        },
        button: true,
        expanded: menu ? bar.menuShows(id) : null,
        onLongPress: hold ? input.menu.open : null,
      ),
    );
  }

  static String? _labelOf(GlassBarItem item) => switch (item) {
    GlassBarButton(:final semanticLabel) ||
    GlassBarProminentButton(
      :final semanticLabel,
    ) => semanticLabel ?? glassLabelTextOf(_glyphOfItem(item)),
    GlassBarCustomItem() => null,
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      bar.view = context as Element;
      final roster = bar.roster();
      bar.keepInputs(roster.keys);
      bar.grow(roster.length + 2);
      final items = InputZones<Object>(
        // An item no page declares any more is leaving: it gets no zone,
        // which also keeps a hidden zone's stale semantics out of a bar
        // that moves to another route's overlay.
        zones: [
          for (final MapEntry(key: id, value: button) in roster.entries)
            if (button.item is! GlassBarCustomItem &&
                bar.measuredIds.contains(id))
              _zoneOf(context, id, button),
        ],
        frameOf: bar.zoneFrameOf,
        frames: bar.frames,
        controller: _zones,
        excludeChildSemantics: false,
        child: _BarItems(
          bar: bar,
          zones: _zones,
          children: [
            for (final MapEntry(key: id, value: button) in roster.entries)
              _BarItem(
                key: ValueKey(id),
                bar: bar,
                id: id,
                button: button,
              ),
          ],
        ),
      );
      return MotionScope(
        motion: bar.motion,
        child: RepaintBoundary(
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              _Surfaces(
                frames: bar.container,
                merge: const GlassMerge.spacing(GlassToolbar.fusion),
              ),
              _Surfaces(frames: bar.apart, merge: const GlassMerge.none()),
              if (bar.fade case final fade?)
                MotionTransition(opacity: fade, child: items)
              else
                items,
            ],
          ),
        ),
      );
    },
  );
}

class _Surfaces extends StatelessWidget {
  const _Surfaces({required this.frames, required this.merge});

  final List<ValueNotifier<GlassFrame>> frames;
  final GlassMerge merge;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: GlassGroup(
      merge: merge,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          for (final frame in frames)
            GlassSurface.written(
              frame: frame,
              child: const SizedBox.expand(),
            ),
        ],
      ),
    ),
  );
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.bar,
    required this.id,
    required this.button,
    super.key,
  });

  final _Bar bar;
  final Object id;
  final _Button button;

  // The item's zone in the bar's InputZones takes its input and speaks for
  // it, so its glyph is not read on its own.
  @override
  Widget build(BuildContext context) {
    if (button.item case GlassBarCustomItem(:final child)) {
      return _ItemBox(id: id, child: child);
    }
    final item = button.item;
    final content = ExcludeSemantics(child: _glyphOf(context, button));
    final action = _actionOf(button);
    final menu = action.menu;
    if (menu == null) return _ItemBox(id: id, child: content);
    // The menu's source takes the touches; its keys and focus are the
    // zone's, so it is no stop of its own. Its open menu lies in its
    // semantics, so they are read while it shows.
    return _ItemBox(
      id: id,
      child: _OpenMenuSemantics(
        bar: bar,
        id: id,
        child: ExcludeFocusTraversal(
          child: GlassMenuAnchor(
            menuChildren: menu,
            semanticLabel: _BandState._labelOf(item!),
            controller: bar.inputOf(id).menu,
            scalesOnPress: false,
            sourceOf: (overlay) => bar.menuSource(id, overlay),
            onOpen: () => bar.menuShowing(id, showing: true),
            onClose: () => bar.menuShowing(id, showing: false),
            child: _ItemSource(
              onPressed: action.onPressed ?? bar.inputOf(id).menu.open,
              semanticLabel: _BandState._labelOf(item),
              look: _CapsuleLook(
                bar: bar,
                item: id,
                glyphs: {
                  for (final MapEntry(key: id, value: button)
                      in bar.buttons.entries)
                    if (button.item is! GlassBarCustomItem)
                      id: _glyphOf(context, button),
                },
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Widget _glyphOf(BuildContext context, _Button button) {
    final look = bar.itemStyleOf(context);
    final item = button.item;
    final enabled = _actionOf(button).enabled;
    final prominent = item is GlassBarProminentButton;
    final color = GlassDynamicColor.resolve(
      prominent
          ? look?.prominentForegroundColor ?? const Color(0xFFFFFFFF)
          : look?.foregroundColor?.resolve({
                  if (!enabled) WidgetState.disabled,
                }) ??
                (enabled
                    ? GlassTheme.labelColorOf(context)
                    : GlassTheme.tertiaryLabelColorOf(context)),
      context,
    );
    final text = GlassTextScale.of(context).resolve(
      barLabelStyle
          .copyWith(fontWeight: prominent ? FontWeight.w600 : null)
          .merge(look?.textStyle)
          .copyWith(color: color),
    );
    if (button.back case final back?) {
      const metrics = GlassBarMetrics.navigation;
      final rtl = context.isRightToLeft;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: metrics.backChevronInset),
          SizedBox(
            width: metrics.backChevronWidth,
            height: _chevronHeight,
            child: CustomPaint(
              painter: _ChevronPainter(color: color, mirrored: rtl),
            ),
          ),
          if (back.shownIn(context) case final title?) ...[
            SizedBox(width: metrics.backChevronGap),
            Text(title, style: text, maxLines: 1),
            SizedBox(width: metrics.backTrailingPadding),
          ] else
            SizedBox(width: metrics.backChevronInset),
        ],
      );
    }
    return IconTheme.merge(
      data: IconThemeData(size: bar.metrics.iconSize, color: color),
      child: DefaultTextStyle(
        style: text,
        maxLines: 1,
        child: _glyphOfItem(item)!,
      ),
    );
  }

  static const double _chevronHeight = 23;
}

/// The glyphs of [item]'s capsule, each where it stands in the capsule: what
/// rides the capsule's shape as it shrinks into a menu. An item with a custom
/// view has no copy to ride it, so it is left out.
class _CapsuleLook extends StatelessWidget {
  const _CapsuleLook({
    required this.bar,
    required this.item,
    required this.glyphs,
  });

  final _Bar bar;
  final Object item;
  final Map<Object, Widget> glyphs;

  @override
  Widget build(BuildContext context) {
    final size = bar.capsuleSize(item);
    if (size == null) return const SizedBox.shrink();
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          for (final (id, rect) in bar.capsuleItems(item))
            if (glyphs[id] case final glyph?)
              Positioned.fromRect(
                rect: rect,
                child: Center(child: glyph),
              ),
        ],
      ),
    );
  }
}

/// The back chevron, pointing to the leading edge; [mirrored] flips it.
class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color, required this.mirrored});

  final Color color;
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.19;
    final paint = Paint();
    paint.color = color;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = stroke;
    paint.strokeCap = StrokeCap.round;
    paint.strokeJoin = StrokeJoin.round;
    final left = stroke / 2 + size.width * 0.12;
    final right = size.width - stroke / 2 - size.width * 0.12;
    final path = Path();
    if (mirrored) {
      path.moveTo(left, stroke / 2);
      path.lineTo(right, size.height / 2);
      path.lineTo(left, size.height - stroke / 2);
    } else {
      path.moveTo(right, stroke / 2);
      path.lineTo(left, size.height / 2);
      path.lineTo(right, size.height - stroke / 2);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.mirrored != mirrored;
}
