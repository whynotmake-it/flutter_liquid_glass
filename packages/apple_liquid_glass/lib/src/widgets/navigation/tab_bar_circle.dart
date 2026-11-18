part of 'tab_bar.dart';

/// The search tab's circle on its way into the field: its glass, the
/// magnifier travelling from the circle's center to the field's glyph and
/// the placeholder fading in over the morph's last 60 percent (matched to
/// a simulator film by eye).
class _SearchCircle extends StatelessWidget {
  const _SearchCircle({
    required this.q,
    required this.placeholder,
    required this.glyph,
    required this.rtl,
    required this.onTap,
  });

  final ValueListenable<double> q;
  final ValueListenable<double> placeholder;
  final Color glyph;
  final bool rtl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: GlassLocalizations.of(context).searchLabel,
    onTap: onTap,
    excludeSemantics: true,
    child: RawGlassButton(
      onPressed: onTap,
      builder: (context, details) => GlassSurface.live(
        frame: details.body,
        states: details.statesListenable,
        child: details.label,
      ),
      child: CustomMultiChildLayout(
        delegate: _CircleLayout(q: q, rtl: rtl),
        children: [
          LayoutId(
            id: 0,
            child: GlassSearchIcon(color: glyph),
          ),
          LayoutId(
            id: 1,
            child: MotionTransition(
              opacity: placeholder,
              child: ClipRect(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DefaultTextStyle(
                    style: GlassTextScale.of(context).resolve(
                      barLabelStyle.copyWith(
                        color: StateColors(context, const {})(
                          GlassSearchField.placeholderColors,
                          GlassColors.secondaryLabel,
                        ),
                      ),
                    ),
                    maxLines: 1,
                    softWrap: false,
                    child: Text(GlassLocalizations.of(context).searchLabel),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CircleLayout extends MultiChildLayoutDelegate {
  _CircleLayout({required this.q, required this.rtl}) : super(relayout: q);

  final ValueListenable<double> q;
  final bool rtl;

  @override
  void performLayout(Size size) {
    const glyph = GlassSearchIcon.defaultSize;
    final t = q.value.clamp(0.0, 1.0);
    final grown = 1 + 0.15 * (1 - t);
    final box = Size(glyph.width * grown, glyph.height * grown);
    final start = Offset(
      rtl
          ? size.width - GlassSearchField.glyphInset - glyph.width / 2
          : GlassSearchField.glyphInset + glyph.width / 2,
      size.height / 2,
    );
    final center = Offset.lerp(size.center(Offset.zero), start, t)!;
    layoutChild(0, BoxConstraints.tight(box));
    positionChild(0, center - Offset(box.width / 2, box.height / 2));
    final text = Rect.fromLTRB(
      rtl ? 8 : GlassSearchField.textInset,
      0,
      rtl ? size.width - GlassSearchField.textInset : size.width - 8,
      size.height,
    );
    layoutChild(
      1,
      BoxConstraints.tight(
        Size(math.max(0, text.width), math.max(0, text.height)),
      ),
    );
    positionChild(1, text.topLeft);
  }

  @override
  bool shouldRelayout(_CircleLayout oldDelegate) =>
      rtl != oldDelegate.rtl || !identical(q, oldDelegate.q);
}
