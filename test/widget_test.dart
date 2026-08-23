// アプリが起動してボトムナビゲーションが表示されることを確認するスモークテスト

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gacha_collector/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const GachaCollectorApp());
    await tester.pump();

    expect(find.text('ホーム'), findsOneWidget);
    expect(find.text('マイページ'), findsOneWidget);
  });
}
