import 'package:flutter_test/flutter_test.dart';
import 'package:hodour/src/ui/requests/request_detail_widgets.dart';

void main() {
  test('day count is inclusive and rejects bad or backwards ranges', () {
    expect(requestDayCount('2026-11-20', '2026-11-20'), 1);
    expect(requestDayCount('2026-11-20', '2026-11-22'), 3);
    expect(requestDayCount('2026-11-30', '2026-12-02'), 3);
    expect(requestDayCount('2026-11-22', '2026-11-20'), isNull);
    expect(requestDayCount(null, '2026-11-20'), isNull);
    expect(requestDayCount('2026-11-20', null), isNull);
    expect(requestDayCount('not-a-date', '2026-11-20'), isNull);
  });
}
