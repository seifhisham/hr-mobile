import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hodour/src/theme/theme.dart';
import 'package:hodour/src/ui/sales/sales_dashboard_widgets.dart';

void main() {
  for (final reducedMotion in [false, true]) {
    testWidgets('sales disclosure respects reduced motion $reducedMotion',
        (tester) async {
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, child) => MaterialApp(
          theme: buildLightTheme(primaryColorHex: '#0068DC'),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reducedMotion),
            child: const Scaffold(
                body: SalesDisclosure(
                    title: 'Filters', child: Text('Filter controls'))),
          ),
        ),
      ));
      expect(find.text('Filter controls'), findsNothing);
      expect(find.byType(AnimatedSize),
          reducedMotion ? findsNothing : findsOneWidget);
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('Filter controls'), findsOneWidget);
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('Filter controls'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
