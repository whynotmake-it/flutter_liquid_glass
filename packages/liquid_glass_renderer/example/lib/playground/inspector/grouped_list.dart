import 'package:flutter/cupertino.dart';

/// Corner radius of the sheet that hosts the inspector.
const panelRadius = 34.0;

/// Distance of the inspector's content from the sheet edge.
const inspectorInset = 12.0;

/// Corner radius of cards and buttons, concentric with the sheet corners.
const cardRadius = panelRadius - inspectorInset;

/// Rows grouped on one card, in the style of iOS Settings.
class InspectorCard extends StatelessWidget {
  const InspectorCard({required this.children, this.header, super.key});

  final String? header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final separator = CupertinoColors.separator.resolveFrom(context);
    return Column(
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
          decoration: ShapeDecoration(
            color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
              context,
            ),
            shape: const RoundedSuperellipseBorder(
              borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
            ),
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
      ],
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
              Expanded(child: _Title(title)),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            Expanded(child: _Title(title)),
            CupertinoSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// A capsule button, concentric with the sheet like the cards.
class CapsuleButton extends StatelessWidget {
  const CapsuleButton({
    required this.label,
    required this.onPressed,
    this.prominent = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Whether the button is tinted with the accent color.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoTheme.of(context).primaryColor;
    final enabled = onPressed != null;
    return GestureDetector(
      onTap: onPressed,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: prominent
              ? accent.withValues(alpha: 0.15)
              : CupertinoColors.tertiarySystemFill.resolveFrom(context),
          shape: const StadiumBorder(),
        ),
        child: SizedBox(
          height: cardRadius * 2,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: enabled
                    ? (prominent
                          ? accent
                          : CupertinoColors.label.resolveFrom(context))
                    : CupertinoColors.tertiaryLabel.resolveFrom(context),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: CupertinoColors.label.resolveFrom(context),
        fontSize: 17,
        letterSpacing: -0.4,
      ),
    );
  }
}
