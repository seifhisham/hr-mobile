import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hodour/src/services/url_launcher_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  const url = 'https://wallstreetwsc.com/hodour-hr/privacy-policy';
  final calls = <MethodCall>[];
  var launched = true;

  setUp(() {
    calls.clear();
    launched = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'launch' && launched;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('opens policy even when browser discovery would return false', () async {
    final result = await UrlLauncherService.instance.launch(url);
    expect(result.isRight(), isTrue);
    expect(calls.map((call) => call.method), ['launch']);
    expect(calls.single.arguments['url'], url);
    expect(calls.single.arguments['useWebView'], isFalse);
  });

  test('reports failure when the actual browser launch returns false',
      () async {
    launched = false;
    final result = await UrlLauncherService.instance.launch(url);
    expect(result.isLeft(), isTrue);
    expect(calls.map((call) => call.method), ['launch']);
  });
}
