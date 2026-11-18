import 'package:flutter/widgets.dart';

/// The query of a search and whether the search is open, like Flutter's
/// `SearchController`.
///
/// UIKit: `UISearchController` (`isActive`). SwiftUI: `searchable` with
/// `isPresented`. Flutter: `SearchController`.
///
/// A `GlassTabBar` given one shows a search tab beside its tabs: opening
/// the search turns the bar into its search field, and closing it turns
/// the field back and clears the query. Listeners hear both the query and
/// the open state change.
class GlassSearchController extends TextEditingController {
  /// Creates a closed search with [text] as its query.
  GlassSearchController({super.text});

  bool _isOpen = false;

  /// Whether the search is open.
  bool get isOpen => _isOpen;

  /// Opens the search.
  void openView() {
    if (_isOpen) return;
    _isOpen = true;
    notifyListeners();
  }

  /// Closes the search; the widget showing it clears the query as it
  /// closes.
  void closeView() {
    if (!_isOpen) return;
    _isOpen = false;
    notifyListeners();
  }
}
