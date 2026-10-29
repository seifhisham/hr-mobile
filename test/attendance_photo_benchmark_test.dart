import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:hodour/src/services/attendance_capture_service.dart';

// Historical helper only; native picker processing/network time is excluded.
Uint8List _legacyPreparePhoto(Uint8List bytes) {
  final oriented = image.bakeOrientation(image.decodeImage(bytes)!);
  final resized = oriented.width > 1600 || oriented.height > 1600
      ? image.copyResize(oriented,
          width: oriented.width >= oriented.height ? 1600 : null,
          height: oriented.height > oriented.width ? 1600 : null)
      : oriented;
  resized.exif = image.ExifData();
  resized.iccProfile = null;
  resized.textData = null;
  return image.encodeJpg(resized, quality: 85);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('PHOTO_BENCHMARK');
  test('measure deterministic camera-sized fixtures on the host', () async {
    final results = <Map<String, Object>>[];
    for (final fixture in [
      (name: '12MP landscape JPEG', width: 4032, height: 3024, png: false),
      (name: '12MP portrait JPEG', width: 3024, height: 4032, png: false),
      (name: 'small PNG', width: 640, height: 480, png: true),
    ]) {
      final source = image.Image(width: fixture.width, height: fixture.height);
      final random = Random(2026);
      for (final pixel in source) {
        final noise = random.nextInt(41) - 20;
        pixel.setRgb(
            (pixel.x * 200 ~/ fixture.width + noise + 20).clamp(0, 255),
            (pixel.y * 200 ~/ fixture.height + noise + 20).clamp(0, 255),
            (100 + noise + (pixel.x ~/ 80 % 2) * 40).clamp(0, 255));
      }
      final input = fixture.png
          ? image.encodePng(source)
          : image.encodeJpg(source, quality: 95);
      final beforeTimes = <int>[];
      final afterTimes = <int>[];
      late Uint8List before;
      late Uint8List after;
      // Warm both helpers before three timed runs, including isolate startup.
      await compute(_legacyPreparePhoto, input);
      await compute(prepareAttendancePhoto, input);
      for (var run = 0; run < 3; run++) {
        final timer = Stopwatch()..start();
        before = await compute(_legacyPreparePhoto, input);
        beforeTimes.add(timer.elapsedMilliseconds);
        timer.reset();
        after = await compute(prepareAttendancePhoto, input);
        afterTimes.add(timer.elapsedMilliseconds);
        timer.stop();
      }
      beforeTimes.sort();
      afterTimes.sort();
      final decoded = image.decodeJpg(after)!;
      expect(max(decoded.width, decoded.height), lessThanOrEqualTo(1280));
      expect(after.length, lessThanOrEqualTo(5 * 1024 * 1024));
      final measurement = <String, Object>{
        'fixture': fixture.name,
        'sourceDimensions': '${fixture.width}x${fixture.height}',
        'sourceBytes': input.length,
        'legacy1600Bytes': before.length,
        'prepared1280Bytes': after.length,
        'legacyMedianMs': beforeTimes[1],
        'preparedMedianMs': afterTimes[1],
        'outputDimensions': '${decoded.width}x${decoded.height}',
      };
      results.add(measurement);
      // ignore: avoid_print
      print(jsonEncode(measurement));
    }
    final directory = Directory('artifacts/attendance_compression');
    await directory.create(recursive: true);
    await File('${directory.path}/benchmark.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert({
      'environment':
          'Flutter test Dart VM on Windows; synthetic fixtures, median of 3 warmed compute runs',
      'excludes':
          'Native camera/picker processing, GPS, file reading, network, and actual phone timings',
      'measurements': results,
    }));
  },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: enabled
          ? false
          : 'Opt-in host measurement: --dart-define=PHOTO_BENCHMARK=true');
}
