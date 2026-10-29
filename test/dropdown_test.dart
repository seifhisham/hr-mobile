import 'package:flutter_test/flutter_test.dart';
import 'package:hodour/src/imports/imports.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'dropdown selection and reset in ${dark ? 'dark RTL' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var value = 'all';
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
              theme: dark
                  ? buildDarkTheme(primaryColorHex: '#2457A7')
                  : buildLightTheme(primaryColorHex: '#2457A7'),
              home: StatefulBuilder(
                  builder: (context, setState) => Scaffold(
                      body: MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(textScaler: const TextScaler.linear(2)),
                          child: Directionality(
                              textDirection:
                                  dark ? TextDirection.rtl : TextDirection.ltr,
                              child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(children: [
                                    AppDropdown<String>(
                                        label: 'Status',
                                        value: value,
                                        items: const [
                                          AppDropdownItem(
                                              value: 'all',
                                              label: 'All statuses'),
                                          AppDropdownItem(
                                              value: 'pending',
                                              label: 'Pending'),
                                          AppDropdownItem(
                                              value: 'disabled',
                                              label: 'Unavailable',
                                              enabled: false),
                                        ],
                                        onChanged: (next) =>
                                            setState(() => value = next!)),
                                    TextButton(
                                        onPressed: () =>
                                            setState(() => value = 'all'),
                                        child: const Text('Reset')),
                                  ])))))))));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(find.text('Unavailable').last);
      await tester.pumpAndSettle();
      expect(value, 'all');
      await tester.tap(find.text('Pending').last);
      await tester.pumpAndSettle();
      expect(value, 'pending');
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<DropdownButton<String>>(
                  find.byType(DropdownButton<String>))
              .value,
          'all');
      expect(tester.takeException(), isNull);
    });
  }
}
