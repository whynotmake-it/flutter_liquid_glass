part of 'bar.dart';

/// What a bar knows an item by: UIKit's semantic id of a bar button item,
/// in its order (an explicit identifier, then the image, then the title,
/// then the object), without its system items, which this library has
/// none of.
///
/// Items match across changes of the bar by their identity and the order
/// among items of the same identity ([GlassBarItemId]). An identity that
/// [crossesPages] matches items of another page too, so on a push or a pop
/// an item both pages have stays, or travels to its new place; the others
/// belong to their page, as UIKit tells such items apart by the object.
@immutable
sealed class _ItemIdentity {
  const _ItemIdentity();

  factory _ItemIdentity.of(GlassBarItem item) => switch (item) {
    GlassBarItem(key: final key?) => _Explicit(key),
    GlassBarButton(:final icon, :final label) ||
    GlassBarProminentButton(:final icon, :final label) => switch ((
      icon,
      label,
    )) {
      (Icon(icon: final image?), _) => _Image(image),
      (_, Text(data: final title?)) => _Title(title),
      _ => const _Place(),
    },
    GlassBarCustomItem(:final child) => _CustomView(child.runtimeType),
  };

  /// Whether the identity matches items of another page.
  bool get crossesPages;
}

final class _Explicit extends _ItemIdentity {
  const _Explicit(this.key);

  final LocalKey key;

  @override
  bool get crossesPages => true;

  @override
  bool operator ==(Object other) => other is _Explicit && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

final class _Image extends _ItemIdentity {
  const _Image(this.icon);

  final IconData icon;

  @override
  bool get crossesPages => true;

  @override
  bool operator ==(Object other) => other is _Image && other.icon == icon;

  @override
  int get hashCode => icon.hashCode;
}

final class _Title extends _ItemIdentity {
  const _Title(this.text);

  final String text;

  @override
  bool get crossesPages => true;

  @override
  bool operator ==(Object other) => other is _Title && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

// A custom view is its object in UIKit; a widget is rebuilt, so the kind of
// its child stands for it within its page.
final class _CustomView extends _ItemIdentity {
  const _CustomView(this.kind);

  final Type kind;

  @override
  bool get crossesPages => false;

  @override
  bool operator ==(Object other) => other is _CustomView && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;
}

// An item with neither an icon nor a title to know it by: its order among
// such items of its page.
final class _Place extends _ItemIdentity {
  const _Place();

  @override
  bool get crossesPages => false;

  @override
  bool operator ==(Object other) => other is _Place;

  @override
  int get hashCode => (_Place).hashCode;
}

// An identity that does not cross pages, held to its page.
@immutable
final class _PageId {
  const _PageId(this.page, this.identity);

  final GlassPageBarLink page;
  final _ItemIdentity identity;

  @override
  bool operator ==(Object other) =>
      other is _PageId &&
      identical(other.page, page) &&
      other.identity == identity;

  @override
  int get hashCode => Object.hash(identityHashCode(page), identity);
}
