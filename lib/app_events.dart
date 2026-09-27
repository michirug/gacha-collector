import 'package:flutter/foundation.dart';

// 端末内のユーザーデータ(コレクション/ウィッシュ/写真共有の設定)が変わったことを、
// IndexedStack で生かしたままの別タブ(ホーム/マイページ)に知らせる。
// ページは自分が開いた画面から戻ったときだけ再読込していたので、
// ホーム→シリーズ詳細で獲得してもマイページが古いままだった(2026-09-27 リリース総点検で発見)。
class AppEvents {
  static final ValueNotifier<int> userDataRevision = ValueNotifier<int>(0);
  static final ValueNotifier<int> selectedTab = ValueNotifier<int>(0);

  static void bumpUserData() => userDataRevision.value++;
}
