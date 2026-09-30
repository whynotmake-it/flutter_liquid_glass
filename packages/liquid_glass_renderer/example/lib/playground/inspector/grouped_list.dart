import 'package:flutter/cupertino.dart';

/// An inset grouped section in the style of iOS Settings.
class InspectorSection extends StatelessWidget {
  const InspectorSection({
    required this.children,
    this.header,
    this.footer,
    super.key,
  });

  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final separator = CupertinoColors.separator.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header case final header?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                header,
                style: TextStyle(
                  color: CupertinoColors.label.resolveFrom(context),
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: CupertinoColors.secondarySystemGroupedBackground
                  .resolveFrom(context),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, child) in children.indexed) ...[
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: SizedBox(
                        height: 0.5,
                        child: ColoredBox(color: separator),
                      ),
                    ),
                  child,
                ],
              ],
            ),
          ),
          if (footer case final footer?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                footer,
                style: TextStyle(color: secondary, fontSize: 13, height: 1.3),
              ),
            ),
        ],
      ),
    );
  }
}

/// A plain row with a title and an optional trailing widget.
class InspectorRow extends StatelessWidget {
  const InspectorRow({
    required this.title,
    this.trailing,
    this.onTap,
    this.titleColor,
    super.key,
  });

  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color:
                        titleColor ??
                        CupertinoColors.label.resolveFrom(context),
                    fontSize: 17,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// A full-width segmented control inside a section.
class SegmentedRow<T extends Object> extends StatelessWidget {
  const SegmentedRow({
    required this.value,
    required this.segments,
    required this.onChanged,
    super.key,
  });

  final T value;
  final Map<T, String> segments;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        onValueChanged: (value) {
          if (value != null) onChanged(value);
        },
        children: {
          for (final MapEntry(:key, value: label) in segments.entries)
            key: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(label, style: const TextStyle(fontSize: 14)),
            ),
        },
      ),
    );
  }
}

/// A titled slider with its current value, like the sliders in iOS Settings.
class SliderRow extends StatelessWidget {
  const SliderRow({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.format,
    this.minLabel,
    this.maxLabel,
    super.key,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// Formats the value shown next to the title; hidden when `null`.
  final String Function(double value)? format;

  /// Labels under the ends of the track.
  final String? minLabel;
  final String? maxLabel;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: CupertinoColors.label.resolveFrom(context),
                    fontSize: 17,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              if (format case final format?)
                Text(
                  format(value),
                  style: TextStyle(
                    color: secondary,
                    fontSize: 17,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          CupertinoSlider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
          if (minLabel != null || maxLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: DefaultTextStyle(
                style: TextStyle(color: secondary, fontSize: 13),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text(minLabel ?? ''), Text(maxLabel ?? '')],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A titled switch.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InspectorRow(
      title: title,
      onTap: () => onChanged(!value),
      trailing: CupertinoSwitch(value: value, onChanged: onChanged),
    );
  }
}
