import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/gallery_bar.dart';
import 'package:flutter/widgets.dart';

/// The page of one component, the same for every one of them: what it is
/// in a line, the component itself on a stage, the knobs that turn its own
/// parameters, and a few things to make with it.
class ComponentPage extends StatelessWidget {
  const ComponentPage({
    required this.name,
    required this.summary,
    this.stage,
    this.backdrop,
    this.stageHeight = 190,
    this.knobs = const [],
    this.ideas = const [],
    this.slivers = const [],
    super.key,
  });

  /// The class or function the page is about, as an app writes it.
  final String name;

  /// What the component is, in a sentence.
  final String summary;

  /// The component, as the knobs have it; null where it only shows in
  /// use, as a list or a sheet does.
  final Widget? stage;

  /// The photo the stage lies on, for a component of glass, or null for the
  /// page's own grouped card.
  final Wallpaper? backdrop;

  final double stageHeight;

  /// Rows that set the component's parameters ([ToggleKnob], [ChoiceKnob],
  /// [AmountKnob]).
  final List<Widget> knobs;

  /// What can be made with the component ([Idea]).
  final List<Widget> ideas;

  /// More of the page as slivers, after the ideas: a list that animates its
  /// rows needs one of its own.
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    final secondary = GlassDynamicColor.resolve(
      GlassColors.secondaryLabel,
      context,
    );
    return GlassPageScaffold(
      backgroundColor: GlassColors.systemGroupedBackground,
      navigationBar: GlassNavigationBar(
        title: Text(name),
        previousPageTitle: 'Components',
        backButtonDisplayMode: GlassBackButtonDisplayMode.minimal,
        trailing: galleryItems(context),
      ),
      child: GlassContentScroll(
        child: CustomScrollView(
          slivers: [
            SliverSafeArea(
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                      child: Text(
                        summary,
                        style: TextStyle(
                          color: secondary,
                          fontSize: 16,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                  if (stage case final stage?)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Stage(
                          backdrop: backdrop,
                          height: stageHeight,
                          child: stage,
                        ),
                      ),
                    ),
                  if (knobs.isNotEmpty)
                    SliverToBoxAdapter(
                      child: GlassListSection(
                        header: const Text('Try it'),
                        children: knobs,
                      ),
                    ),
                  if (ideas.isNotEmpty)
                    const SliverToBoxAdapter(child: _Heading('Ideas')),
                  for (final idea in ideas) SliverToBoxAdapter(child: idea),
                  ...slivers,
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    child: Text(
      text,
      style: TextStyle(
        color: GlassDynamicColor.resolve(GlassColors.label, context),
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
  );
}

/// Where a component stands to be looked at: a photo, for glass to have
/// something under it, or a card of the page's grouped color.
class Stage extends StatelessWidget {
  const Stage({
    required this.child,
    this.backdrop,
    this.height = 190,
    super.key,
  });

  final Widget child;
  final Wallpaper? backdrop;
  final double? height;

  @override
  Widget build(BuildContext context) => ClipRSuperellipse(
    borderRadius: BorderRadius.circular(28),
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: height ?? 0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: switch (backdrop) {
              final photo? => Image(image: photo.image, fit: BoxFit.cover),
              null => ColoredBox(
                color: GlassDynamicColor.resolve(
                  GlassColors.secondarySystemGroupedBackground,
                  context,
                ),
              ),
            },
          ),
          Padding(padding: const EdgeInsets.all(20), child: child),
        ],
      ),
    ),
  );
}

/// A knob that turns one thing on or off.
class ToggleKnob extends StatelessWidget {
  const ToggleKnob(
    this.label, {
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GlassListRow(
    title: Text(label),
    trailing: GlassSwitch(
      value: value,
      semanticLabel: label,
      onChanged: onChanged,
    ),
    onPressed: () => onChanged(!value),
  );
}

/// A knob that picks one of a few values.
class ChoiceKnob<T extends Object> extends StatelessWidget {
  const ChoiceKnob(
    this.label, {
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T value;

  /// Each value and what it is called.
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => GlassListRow(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            color: GlassDynamicColor.resolve(
              GlassColors.secondaryLabel,
              context,
            ),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        GlassSegmentedControl<T>(
          segments: [
            for (final MapEntry(:key, value: name) in options.entries)
              GlassSegment(value: key, label: Text(name)),
          ],
          groupValue: value,
          semanticLabel: label,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

/// A knob that sets an amount.
class AmountKnob extends StatelessWidget {
  const AmountKnob(
    this.label, {
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.ticks = 0,
    this.shows,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int ticks;
  final ValueChanged<double> onChanged;

  /// The amount as the row shows it; the rounded value by default.
  final String Function(double value)? shows;

  @override
  Widget build(BuildContext context) => GlassListRow(
    child: Row(
      children: [
        SizedBox(width: 92, child: Text(label)),
        Expanded(
          child: GlassSlider(
            value: value,
            min: min,
            max: max,
            ticks: ticks,
            semanticLabel: label,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            shows?.call(value) ?? '${value.round()}',
            textAlign: TextAlign.end,
            style: TextStyle(
              color: GlassDynamicColor.resolve(
                GlassColors.secondaryLabel,
                context,
              ),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Something to make with a component: what it is, in a line, and the
/// thing itself. A [flush] child brings its own side margins, as a list
/// section does.
class Idea extends StatelessWidget {
  const Idea(
    this.title,
    this.note, {
    required this.child,
    this.flush = false,
    super.key,
  });

  final String title;
  final String note;
  final Widget child;
  final bool flush;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: GlassDynamicColor.resolve(GlassColors.label, context),
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                note,
                style: TextStyle(
                  color: GlassDynamicColor.resolve(
                    GlassColors.secondaryLabel,
                    context,
                  ),
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: flush ? 0 : 10),
        if (flush)
          child
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: child,
          ),
      ],
    ),
  );
}
