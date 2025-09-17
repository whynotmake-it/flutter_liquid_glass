import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (data) async {
      if (data != null) {
        // Dynamically find all timeline keys (keys that contain timeline data)
        final timelineKeys = data.keys
            .where((key) => data[key] is Map<String, dynamic>)
            .where((key) {
              final value = data[key] as Map<String, dynamic>;
              // Check if it looks like timeline data (has events array)
              return value.containsKey('traceEvents') ||
                  value.containsKey('events') ||
                  key.toString().toLowerCase().contains('timeline');
            })
            .toList();

        print(
          'Found ${timelineKeys.length} timeline datasets: ${timelineKeys.join(', ')}',
        );

        for (final timelineKey in timelineKeys) {
          try {
            final timeline = driver.Timeline.fromJson(
              data[timelineKey] as Map<String, dynamic>,
            );

            final summary = driver.TimelineSummary.summarize(timeline);

            await summary.writeTimelineToFile(
              timelineKey,
              pretty: true,
              includeSummary: true,
            );

            print('Performance results saved for $timelineKey');
            print('Summary file: build/${timelineKey}.timeline_summary.json');
            print('Timeline file: build/${timelineKey}.timeline.json');
          } catch (e) {
            print('Failed to process timeline $timelineKey: $e');
          }
        }
      }
    },
  );
}
