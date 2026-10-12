import 'package:flutter_test/flutter_test.dart';
import 'package:hrmobile/src/imports/imports.dart';

void main() {
  for (final dark in [false, true]) {
    for (final status in ['success', 'info', 'warning', 'error']) {
      testWidgets(
          '$status toast supports ${dark ? 'dark RTL' : 'light'} and dismissal',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            theme: dark
                ? buildDarkTheme(primaryColorHex: '#2457A7')
                : buildLightTheme(primaryColorHex: '#2457A7'),
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showToast(context,
                            message: dark
                                ? 'خدمات الموقع متوقفة. فعّلها من الإعدادات وأعد المحاولة.'
                                : 'Location services are off. Enable them in settings and retry.',
                            status: status,
                            autoDismiss: false),
                        child: const Text('Show toast')))),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(top: 44),
                    textScaler: const TextScaler.linear(2)),
                child: Directionality(
                    textDirection: dark ? TextDirection.rtl : TextDirection.ltr,
                    child: child!)),
          ),
        ));
        await tester.tap(find.text('Show toast'));
        await tester.pumpAndSettle();
        final card = find.byType(ToastCard);
        expect(card, findsOneWidget);
        expect(tester.getTopLeft(card).dy, greaterThanOrEqualTo(44));
        expect(tester.takeException(), isNull);
        final close = find.byIcon(Icons.close_rounded);
        final message =
            find.descendant(of: card, matching: find.byType(Text)).first;
        expect(
            tester.getCenter(close).dx,
            dark
                ? lessThan(tester.getCenter(message).dx)
                : greaterThan(tester.getCenter(message).dx));
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(card, findsNothing);
        await tester.pump(const Duration(seconds: 6));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
