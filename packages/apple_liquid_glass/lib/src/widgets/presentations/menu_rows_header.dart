part of 'menu_rows.dart';

/// How bold a card header's title is, how far its chevron has turned and
/// the opacity of its separator, each from 0 to 1.
@internal
typedef MenuHeaderValues = ({double bold, double turn, double separator});

/// The header of a submenu card: the row it grew out of, its title
/// turning bold and its chevron turning down as the card opens, each read
/// again on every frame of [frames].
@internal
class MenuCardHeader extends StatelessWidget {
  /// Creates the header [header] of a card.
  const MenuCardHeader({
    required this.frames,
    required this.header,
    required this.placed,
    required this.values,
    required this.style,
    required this.width,
    required this.content,
    super.key,
  });

  /// The frames on which the header reads [placed] and [values] again.
  final ValueListenable<Object?> frames;

  /// The header as the card's layout places it.
  final MenuPlaced header;

  /// The header now: its columns move from the row's to its own.
  final MenuPlaced Function() placed;

  /// The header's moving values now.
  final MenuHeaderValues Function() values;

  /// The colors.
  final MenuAppearance style;

  /// The card's width.
  final double width;

  /// The menu's entries and their state.
  final MenuContent content;

  Color get _title => style.textStyle.color!;

  static const _bold = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);

  Widget _text(BuildContext context, TextStyle base) => Text(
    header.title ?? '',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: GlassTextScale.of(context).resolve(base).copyWith(color: _title),
  );

  Rect _span(double start, double extent, double height, bool rtl) =>
      Rect.fromLTWH(rtl ? width - start - extent : start, 0, extent, height);

  @override
  Widget build(BuildContext context) {
    final header = this.header;
    final entry = header.entry;
    final icon = entry is GlassSubmenu ? entry.icon : null;
    final rtl = content.rtl;
    final metrics = content.metrics;
    final height = header.rect.height;
    return Positioned.fromRect(
      rect: header.rect,
      // The header is the back target, described by its zone.
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (header.imageCenter != null && icon != null)
              menuDriven(
                frames,
                (_) => menuPlacement(
                  _span(
                    placed().imageCenter! - MenuAppearance.imageSlot / 2,
                    MenuAppearance.imageSlot,
                    height,
                    rtl,
                  ),
                ),
                child: Center(
                  child: IconTheme.merge(
                    data: IconThemeData(
                      size: MenuAppearance.rowIconSize,
                      color: _title,
                    ),
                    child: icon,
                  ),
                ),
              ),
            menuDriven(
              frames,
              (_) {
                final now = placed();
                return menuPlacement(
                  _span(
                    now.titleStart,
                    now.titleEnd - now.titleStart,
                    height,
                    rtl,
                  ),
                );
              },
              child: Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [
                  menuDriven(
                    frames,
                    (_) => Opacity(opacity: 1 - values().bold),
                    child: _text(context, style.textStyle),
                  ),
                  menuDriven(
                    frames,
                    (_) => Opacity(opacity: values().bold),
                    child: _text(context, style.textStyle.merge(_bold)),
                  ),
                ],
              ),
            ),
            PositionedDirectional(
              start: metrics.chevronCenter - MenuAppearance.markSlot / 2,
              width: MenuAppearance.markSlot,
              top: 0,
              bottom: 0,
              child: Center(
                child: Transform.flip(
                  flipX: rtl,
                  child: menuDriven(
                    frames,
                    (_) => Transform.rotate(
                      angle: values().turn * math.pi / 2,
                    ),
                    child: CustomPaint(
                      size: MenuAppearance.chevronSize,
                      painter: _ChevronPainter(color: _title),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: metrics.separatorInset,
              right: metrics.separatorInset,
              bottom: 0,
              height: 1,
              child: menuDriven(
                frames,
                (_) => Opacity(opacity: values().separator),
                child: ColoredBox(color: style.separatorColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
