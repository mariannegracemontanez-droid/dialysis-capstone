import 'package:donation_app/services/public_donation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('publicFeedToDisplay', () {
    test('renders only name, date and amount, as the landing page always has', () {
      final display = publicFeedToDisplay([
        {'display_name': 'Juan Dela Cruz', 'donated_at': '2026-10-01T08:00:00Z', 'amount': 500},
        {'display_name': 'Anonymous', 'donated_at': '2026-09-30T08:00:00Z', 'amount': '1250.50'},
      ]);

      expect(display.first['name'], 'Juan Dela Cruz');
      expect(display.first['amount'], '₱ 500');
      expect(display.first['status'], 'Verified');
      expect(display.first['date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(display[1]['name'], 'Anonymous');
      for (final row in display) {
        expect(row.keys, unorderedEquals(['name', 'date', 'amount', 'status']));
      }
    });

    test('blank or missing names fall back to Anonymous', () {
      final display = publicFeedToDisplay([
        {'display_name': '  ', 'donated_at': null, 'amount': 20},
        {'donated_at': null, 'amount': 20},
      ]);
      expect(display.map((r) => r['name']), ['Anonymous', 'Anonymous']);
      expect(display.first['date'], '');
    });
  });

  test('publicTotalsFromRows', () {
    expect(publicTotalsFromRows([
      {'donation_count': 3, 'total_amount': '4500.50'},
    ]), (count: 3, total: 4500.5));
    expect(publicTotalsFromRows(const []), (count: 0, total: 0.0));
  });

  test('pollEvery emits immediately, keeps going after an error', () async {
    var calls = 0;
    final events = <Object>[];
    final sub = pollEvery<int>(const Duration(milliseconds: 5), () async {
      calls++;
      if (calls == 2) throw StateError('network down');
      return calls;
    }).listen(events.add, onError: (Object e) => events.add('error'));

    await Future<void>.delayed(const Duration(milliseconds: 60));
    await sub.cancel();

    expect(events.take(3), [1, 'error', 3]);
  });
}
