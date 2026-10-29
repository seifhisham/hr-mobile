import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:hodour/src/ui/home/home_header.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);
  test('Home greeting follows company timezone with a UTC fallback', () {
    expect(homeGreeting(DateTime.utc(2026, 1, 1, 9), 'Africa/Cairo'),
        'home.good_morning');
    expect(homeGreeting(DateTime.utc(2026, 1, 1, 10), 'Africa/Cairo'),
        'home.good_afternoon');
    expect(homeGreeting(DateTime.utc(2026, 1, 1, 16), 'Africa/Cairo'),
        'home.good_evening');
    expect(homeGreeting(DateTime.utc(2026, 1, 1, 9), 'unknown'),
        'home.good_morning');
  });
  test('Avatar uses employee initials and handles Arabic and whitespace', () {
    expect(homeInitials('  Ahmed Hassan  '), 'AH');
    expect(homeInitials('أحمد حسن'), 'أح');
    expect(homeInitials('Ahmed'), 'A');
    expect(homeInitials('  '), '');
  });
}
