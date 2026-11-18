import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

/// Notes that insert, expand and swipe away; the rows below and the card
/// behind them follow, each change one `withSpring` around a `setState`.
class NotesSection extends StatefulWidget {
  const NotesSection({super.key});

  @override
  State<NotesSection> createState() => _NotesSectionState();
}

final class _Note {
  const _Note(this.id, this.title, this.body);

  final int id;
  final String title;
  final String body;
}

class _NotesSectionState extends State<NotesSection> {
  static const _spring = Spring.smooth;
  static const _add = #add;
  static const _drafts = [
    ('Groceries', 'Oat milk, lemons, basil, the good bread.'),
    ('Ideas', 'A glass toolbar that remembers where it was.'),
    ('Trip', 'Train at 9:40, platform 7. Window seat.'),
    ('Books', 'Finish the one about lighthouses.'),
    ('Call', 'Ask about the Saturday booking.'),
  ];

  var _next = 3;
  late final List<_Note> _notes = [
    for (final (i, (title, body)) in _drafts.take(3).indexed)
      _Note(i, title, body),
  ];
  final _open = <int>{};

  void _change(VoidCallback change) =>
      withSpring(_spring, () => setState(change));

  void _insert() => _change(() {
    final (title, body) = _drafts[_next % _drafts.length];
    _notes.insert(0, _Note(_next, title, body));
    _next++;
  });

  void _delete(_Note note) => _change(() {
    _notes.remove(note);
    _open.remove(note.id);
  });

  void _expand(_Note note) => _change(() {
    if (!_open.remove(note.id)) _open.add(note.id);
  });

  Widget _row(Object id) {
    if (id == _add) {
      return GlassListRow(
        leading: const SettingsIcon(
          icon: CupertinoIcons.plus,
          color: GlassColors.systemOrange,
        ),
        title: const Text('New Note'),
        onPressed: _insert,
      );
    }
    final note = _notes.firstWhere((note) => note.id == id);
    final open = _open.contains(note.id);
    return GlassSwipeActions(
      trailing: [
        GlassSwipeAction(
          title: 'Delete',
          destructive: true,
          icon: const Icon(CupertinoIcons.trash, color: Color(0xFFFFFFFF)),
          onPressed: () => _delete(note),
        ),
      ],
      child: GlassListRow(
        title: Text(note.title),
        subtitle: open ? Text(note.body) : null,
        accessory: open ? null : GlassListAccessory.disclosureIndicator,
        onPressed: () => _expand(note),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ids = <Object>[for (final note in _notes) note.id, _add];
    return GlassSliverListSection(
      header: const Text('Notes'),
      footer: const Text(
        'Tap a note to open it, swipe it to delete it: the rows below and '
        'the card follow on the same spring.',
      ),
      ids: ids,
      itemCount: ids.length,
      itemBuilder: (context, i) => _row(ids[i]),
    );
  }
}
