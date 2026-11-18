part of 'tab_bar.dart';

/// A tab's glyph and title where UIKit places them in a bar 62 points tall,
/// not as a column: the glyph's center 24 points from the top, the title's
/// bottom at 51, so a title in a taller script grows upward and moves
/// nothing. [morph] takes the title away as the bar turns into its circle.
class _TabItem extends MultiChildRenderObjectWidget {
  const _TabItem({
    required this.morph,
    required this.titleGoneAt,
    required super.children,
  });

  final ValueListenable<double>? morph;
  final double titleGoneAt;

  @override
  _RenderTabItem createRenderObject(BuildContext context) =>
      _RenderTabItem(morph, titleGoneAt);

  @override
  void updateRenderObject(BuildContext context, _RenderTabItem renderObject) {
    renderObject.morph = morph;
    renderObject.titleGoneAt = titleGoneAt;
  }
}

class _TabItemParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderTabItem extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TabItemParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TabItemParentData>,
        ListenableFollower {
  _RenderTabItem(this._morph, this._titleGoneAt);

  static const double _titleBottom = 51;

  ValueListenable<double>? _morph;
  ValueListenable<double>? get morph => _morph;
  set morph(ValueListenable<double>? value) {
    if (identical(value, _morph)) return;
    refollow(() => _morph = value);
    markNeedsPaint();
  }

  @override
  List<(Listenable, VoidCallback)> get followed => [
    if (_morph case final morph?) (morph, markNeedsPaint),
  ];

  double _titleGoneAt;
  double get titleGoneAt => _titleGoneAt;
  set titleGoneAt(double value) {
    if (value == _titleGoneAt) return;
    _titleGoneAt = value;
    markNeedsPaint();
  }

  RenderBox get _glyph => firstChild!;
  RenderBox get _title => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TabItemParentData) {
      child.parentData = _TabItemParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      computeMaxIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) => math.max(
    _glyph.getMaxIntrinsicWidth(double.infinity),
    _title.getMaxIntrinsicWidth(double.infinity),
  );

  @override
  double computeMinIntrinsicHeight(double width) => GlassTabBar.height;

  @override
  double computeMaxIntrinsicHeight(double width) => GlassTabBar.height;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(
        Size(
          constraints.hasBoundedWidth
              ? constraints.maxWidth
              : computeMaxIntrinsicWidth(GlassTabBar.height),
          GlassTabBar.height,
        ),
      );

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
    _glyph.layout(const BoxConstraints(), parentUsesSize: true);
    (_glyph.parentData! as _TabItemParentData).offset = Offset(
      (size.width - _glyph.size.width) / 2,
      TabBarMinimizeMotion.glyphCenter - _glyph.size.height / 2,
    );
    _title.layout(
      BoxConstraints(
        maxWidth: math.max(0, size.width - TabBarLayout.titleMargin),
      ),
      parentUsesSize: true,
    );
    (_title.parentData! as _TabItemParentData).offset = Offset(
      (size.width - _title.size.width) / 2,
      _titleBottom - _title.size.height,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(
      _glyph,
      offset + (_glyph.parentData! as _TabItemParentData).offset,
    );
    final title = offset + (_title.parentData! as _TabItemParentData).offset;
    final morph = _morph?.value ?? 0;
    if (morph == 0) {
      context.paintChild(_title, title);
      return;
    }
    final left = 1 - morph / _titleGoneAt;
    if (left <= 0) return;
    context.pushOpacity(
      title,
      Color.getAlphaFromOpacity(left.clamp(0.0, 1.0)),
      (context, offset) => context.paintChild(_title, offset),
    );
  }
}
