import 'package:flutter/cupertino.dart';
import 'package:motor/motor.dart';

/// A capsule segmented control whose thumb springs between segments.
///
/// The thumb is inset by [_inset] and rounded by the track radius minus that
/// inset, so the two capsules stay concentric.
class CapsuleSegmentedControl<T extends Object> extends StatelessWidget {
  const CapsuleSegmentedControl({
    required this.value,
    required this.segments,
    required this.onChanged,
    super.key,
  });

  final T value;
  final Map<T, String> segments;
  final ValueChanged<T> onChanged;

  static const height = 36.0;
  static const _inset = 2.0;

  static const _track = CupertinoDynamicColor.withBrightness(
    color: Color(0x1F767680),
    darkColor: Color(0x3D767680),
  );
  static const _thumb = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF636366),
  );

  @override
  Widget build(BuildContext context) {
    final keys = segments.keys.toList(growable: false);
    final selected = keys.indexOf(value).toDouble();
    final label = CupertinoColors.label.resolveFrom(context);
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: _track.resolveFrom(context),
          shape: const StadiumBorder(),
        ),
        child: Padding(
          padding: const EdgeInsets.all(_inset),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth / keys.length;
              return Stack(
                children: [
                  SingleMotionBuilder(
                    motion: const CupertinoMotion.snappy(),
                    value: selected,
                    builder: (context, index, thumb) => Positioned(
                      left: index * width,
                      top: 0,
                      bottom: 0,
                      width: width,
                      child: thumb!,
                    ),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: _thumb.resolveFrom(context),
                        shape: const StadiumBorder(),
                        shadows: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final key in keys)
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onChanged(key),
                            child: Center(
                              child: Text(
                                segments[key]!,
                                maxLines: 1,
                                style: TextStyle(
                                  color: label,
                                  fontSize: 14,
                                  letterSpacing: -0.2,
                                  fontWeight: key == value
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
