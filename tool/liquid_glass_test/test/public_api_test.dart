import 'dart:io';

import 'package:api_listing/api_listing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ApiListing listing;

  setUpAll(() async {
    listing = await listApi(Directory.current);
  });

  void hold(String? failure) {
    if (failure != null) fail(failure);
  }

  test('the public API matches test/api/public_api.txt', () {
    hold(
      checkSnapshot(
        File('test/api/public_api.txt'),
        listing.api,
        update: updateRequested,
      ),
    );
  });

  test('the public names match test/api/public_names.txt', () {
    hold(
      checkSnapshot(
        File('test/api/public_names.txt'),
        listing.names,
        update: updateRequested,
      ),
    );
  });

  test('public signatures leak only the internal types listed', () {
    hold(
      checkAllowlist(
        File('test/api/internal_in_signatures.txt'),
        listing.leaks,
        update: updateRequested,
      ),
    );
  });
}
