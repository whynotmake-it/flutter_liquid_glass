import 'dart:io';
import 'dart:convert';

void main() async {
  final buildDir = Directory('build');
  if (!buildDir.existsSync()) {
    print('::set-output name=summary::No benchmark results found');
    return;
  }

  final summaryFiles = buildDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.timeline_summary.json'))
      .toList();

  if (summaryFiles.isEmpty) {
    print('::set-output name=summary::No performance summary files found');
    return;
  }

  // Sort files alphabetically by their test names
  summaryFiles.sort((a, b) {
    final testNameA = a.path
        .split('/')
        .last
        .replaceAll('.timeline_summary.json', '')
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');

    final testNameB = b.path
        .split('/')
        .last
        .replaceAll('.timeline_summary.json', '')
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');

    return testNameA.compareTo(testNameB);
  });

  final buffer = StringBuffer();
  buffer.writeln('## 🚀 Performance Benchmark Results\n');

  for (final file in summaryFiles) {
    try {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      final testName = file.path
          .split('/')
          .last
          .replaceAll('.timeline_summary.json', '')
          .replaceAll('_', ' ')
          .split(' ')
          .map((word) => word[0].toUpperCase() + word.substring(1))
          .join(' ');

      buffer.writeln('### $testName\n');

      // Extract key metrics
      final averageFrameBuildTime = data['average_frame_build_time_millis'];
      final worstFrameBuildTime = data['worst_frame_build_time_millis'];
      final missedFrameBuildBudget = data['missed_frame_build_budget_count'];
      final averageFrameRasterTime =
          data['average_frame_rasterizer_time_millis'];
      final worstFrameRasterTime = data['worst_frame_rasterizer_time_millis'];
      final missedFrameRasterBudget =
          data['missed_frame_rasterizer_budget_count'];

      buffer.writeln('| Metric | Value |');
      buffer.writeln('|--------|-------|');

      if (averageFrameBuildTime != null) {
        buffer.writeln(
          '| Average Frame Build Time | ${averageFrameBuildTime.toStringAsFixed(2)}ms |',
        );
      }
      if (worstFrameBuildTime != null) {
        buffer.writeln(
          '| Worst Frame Build Time | ${worstFrameBuildTime.toStringAsFixed(2)}ms |',
        );
      }
      if (missedFrameBuildBudget != null) {
        final emoji = missedFrameBuildBudget == 0 ? '✅' : '⚠️';
        buffer.writeln(
          '| Missed Frame Build Budget | $emoji $missedFrameBuildBudget frames |',
        );
      }
      if (averageFrameRasterTime != null) {
        buffer.writeln(
          '| Average Frame Raster Time | ${averageFrameRasterTime.toStringAsFixed(2)}ms |',
        );
      }
      if (worstFrameRasterTime != null) {
        buffer.writeln(
          '| Worst Frame Raster Time | ${worstFrameRasterTime.toStringAsFixed(2)}ms |',
        );
      }
      if (missedFrameRasterBudget != null) {
        final emoji = missedFrameRasterBudget == 0 ? '✅' : '⚠️';
        buffer.writeln(
          '| Missed Frame Raster Budget | $emoji $missedFrameRasterBudget frames |',
        );
      }

      buffer.writeln('');
    } catch (e) {
      buffer.writeln('### ${file.path}\n');
      buffer.writeln('❌ Failed to parse results: $e\n');
    }
  }

  buffer.writeln('---');
  buffer.writeln('*Benchmarks run on macOS with Flutter stable channel*');
  buffer.writeln('');
  buffer.writeln('<details>');
  buffer.writeln('<summary>📁 Generated Files</summary>');
  buffer.writeln('');

  final allFiles = buildDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.contains('.timeline'))
      .toList();

  for (final file in allFiles) {
    final relativePath = file.path.replaceFirst(buildDir.path + '/', '');
    buffer.writeln('- `$relativePath`');
  }

  buffer.writeln('</details>');

  final output = buffer.toString();

  print('summary<<EOF');
  print(output);
  print('EOF');
}
