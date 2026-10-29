import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hodour/src/shared/widgets/ui/app/navigation/app_bottom_nav_bar.dart';

void main() {
  testWidgets(
      'floating dock exposes selected destination and handles every tap',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => child!,
      ),
      home: StatefulBuilder(builder: (context, setState) {
        return Scaffold(
          bottomNavigationBar: AppBottomNavBar(
            featuredIndex: 0,
            currentIndex: selected,
            onTap: (index) => setState(() => selected = index),
            items: const [
              AppBottomNavItem(label: 'Home', icon: Icons.home_outlined),
              AppBottomNavItem(label: 'Attendance', icon: Icons.access_time),
              AppBottomNavItem(label: 'Requests', icon: Icons.description),
              AppBottomNavItem(label: 'Account', icon: Icons.person),
              AppBottomNavItem(label: 'Sales', icon: Icons.home_work),
            ],
          ),
        );
      }),
    ));
    expect(find.text('Home'), findsNothing);
    expect(
        tester.getCenter(find.byTooltip('Home')).dx,
        closeTo(
            tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
            1));
    expect(tester.getCenter(find.byTooltip('Home')).dy,
        lessThan(tester.getCenter(find.byTooltip('Attendance')).dy));
    expect(tester.widget<Text>(find.text('Attendance')).maxLines, 1);
    final dockHeight = tester.getSize(find.byType(AppBottomNavBar)).height;
    final semantics = tester.ensureSemantics();
    for (final label in [
      'Home',
      'Attendance',
      'Requests',
      'Account',
      'Sales'
    ]) {
      await tester
          .tap(label == 'Home' ? find.byTooltip('Home') : find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final transforms = find.descendant(
          of: find.byTooltip(label), matching: find.byType(Transform));
      expect(
          tester
              .widgetList<Transform>(transforms)
              .any((transform) => transform.transform.storage[13] < -0.1),
          isTrue);
      await tester.pumpAndSettle();
      expect(
          tester.widgetList<Transform>(transforms).every(
              (transform) => transform.transform.storage[13].abs() < 0.1),
          isTrue);
      expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          matchesSemantics(
              label: label,
              isButton: true,
              isSelected: true,
              hasSelectedState: true,
              hasTapAction: true,
              isFocusable: true,
              hasFocusAction: true));
      expect(tester.getSize(find.byType(AppBottomNavBar)).height, dockHeight);
      expect(tester.takeException(), isNull);
    }
    expect(selected, 4);
    final colors =
        Theme.of(tester.element(find.byTooltip('Sales'))).colorScheme;
    final salesInk = tester.widget<InkWell>(find.descendant(
        of: find.byTooltip('Sales'), matching: find.byType(InkWell)));
    expect(salesInk.overlayColor!.resolve({WidgetState.hovered}),
        colors.onInverseSurface.withValues(alpha: 0.04));
    expect(salesInk.overlayColor!.resolve({WidgetState.pressed}),
        colors.onInverseSurface.withValues(alpha: 0.08));
    expect(salesInk.overlayColor!.resolve({WidgetState.focused}),
        colors.onInverseSurface.withValues(alpha: 0.12));
    expect(salesInk.overlayColor!.resolve({}), Colors.transparent);
    final selectedIcon = tester.widget<AnimatedContainer>(find.descendant(
        of: find.byTooltip('Sales'), matching: find.byType(AnimatedContainer)));
    expect((selectedIcon.decoration! as BoxDecoration).color,
        colors.onInverseSurface.withValues(alpha: 0.12));
    semantics.dispose();
  });

  testWidgets('Arabic dock fits a small phone in dark mode with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => child!,
      ),
      theme: ThemeData.dark(),
      home: MediaQuery(
        data: const MediaQueryData(
            textScaler: TextScaler.linear(2), disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            bottomNavigationBar: AppBottomNavBar(
              featuredIndex: 0,
              currentIndex: 1,
              onTap: (_) {},
              items: const [
                AppBottomNavItem(label: 'الرئيسية', icon: Icons.home),
                AppBottomNavItem(label: 'الحضور', icon: Icons.access_time),
                AppBottomNavItem(label: 'الطلبات', icon: Icons.description),
                AppBottomNavItem(label: 'الحساب', icon: Icons.person),
                AppBottomNavItem(label: 'المبيعات', icon: Icons.home_work),
              ],
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(tester.getCenter(find.text('الحضور')).dx,
        greaterThan(tester.getCenter(find.text('المبيعات')).dx));
    expect(find.text('الرئيسية'), findsNothing);
    for (final animation in tester.widgetList<TweenAnimationBuilder<double>>(
        find.byType(TweenAnimationBuilder<double>))) {
      expect(animation.duration, Duration.zero);
    }
    expect(tester.getCenter(find.byTooltip('الرئيسية')).dx, closeTo(160, 1));
    expect(tester.getSize(find.byType(InkWell).first).width,
        greaterThanOrEqualTo(kMinInteractiveDimension));
  });
}
