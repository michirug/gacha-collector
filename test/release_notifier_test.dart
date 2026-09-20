import 'package:flutter_test/flutter_test.dart';
import 'package:gacha_collector/models.dart';
import 'package:gacha_collector/release_notifier.dart';

GachaSeries series(String id, String releaseText) => GachaSeries.fromJson({
      'jan_code': id,
      'category': 'station',
      'title': 'シリーズ$id',
      'price': '300円',
      'release_date': releaseText,
      'items': [{'title': 'a', 'image_url': ''}],
    });

void main() {
  final now = DateTime(2026, 9, 20, 8); // 9:00 前
  final all = [
    series('past', '2026年9月上旬'),      // 9/5 → 過去
    series('today', '2026年9月20日週'),   // 9/20 → 今日(9:00前なので対象)
    series('soon', '2026年10月中旬'),     // 10/15 → 対象
    series('far', '2027年1月上旬'),       // 60日より先
    series('unknown', ''),               // 発売時期なし
    series('notwished', '2026年9月下旬'),
  ];

  test('ウィッシュリストのうち今日〜60日以内に発売時期を迎えるものだけを、日付順に予約する', () {
    final plans = planReleaseNotifications({'past', 'today', 'soon', 'far', 'unknown'}, all, now);
    expect(plans.map((p) => p.seriesId), ['today', 'soon']);
    expect(plans.first.when, DateTime(2026, 9, 20));
    expect(plans.last.when, DateTime(2026, 10, 15));
    expect(plans.last.title, contains('シリーズsoon'));
    expect(plans.last.body, contains('2026年10月中旬'));
    expect(plans.last.body, contains('300円'));
  });

  test('今日が代表日でも 9:00 を過ぎていれば予約しない', () {
    final plans = planReleaseNotifications({'today'}, all, DateTime(2026, 9, 20, 9, 30));
    expect(plans, isEmpty);
  });

  test('通知IDはシリーズIDから決定的に作られ、正の値になる', () {
    expect(notificationIdFor('kitan:owl'), notificationIdFor('kitan:owl'));
    expect(notificationIdFor('kitan:owl'), isNot(notificationIdFor('kitan:cat')));
    expect(notificationIdFor('4570118187086000'), greaterThanOrEqualTo(0));
  });
}
