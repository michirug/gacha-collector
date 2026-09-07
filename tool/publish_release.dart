// Google Play Developer Publishing API でリリースを配信するスクリプト(2回目以降のアップデート用)。
//
// 前提(初回だけ手作業、手順は tool/PUBLISHING.md):
//   * Play Console 上でアプリが作成済みで、初回リリースは Console から提出済み
//   * サービスアカウントの JSON 鍵があり、Play Console でそのアカウントに「リリース管理」権限が付与されている
//
// 使い方:
//   $env:PLAY_SERVICE_ACCOUNT_JSON = "C:\path\to\service-account.json"   # リポジトリ外に置く
//   dart run tool/publish_release.dart --aab=build/app/outputs/bundle/release/app-release.aab --track=internal
//   dart run tool/publish_release.dart --aab=... --track=production --status=completed --notes=store/release_notes.txt
//   dart run tool/publish_release.dart --listing              # 掲載文(store/store_listing.md)だけ更新
//   dart run tool/publish_release.dart --screenshots          # スクリーンショット(store/assets/screenshots)だけ差し替え
//   --dry-run を付けると commit せずに validate まで行う
//
// track: internal / alpha / beta / production。status: draft(既定) / completed / inProgress(段階的公開、--rollout=0.1)

import 'dart:convert';
import 'dart:io';

import 'package:googleapis/androidpublisher/v3.dart';
import 'package:googleapis_auth/auth_io.dart';

const String kPackageName = 'jp.co.contentsmarketing.gachacollector';
const String kLanguage = 'ja-JP';
const String kListingSource = 'store/store_listing.md';
const String kScreenshotDir = 'store/assets/screenshots';
const String kIconPath = 'store/assets/icon_512.png';
const String kFeatureGraphicPath = 'store/assets/feature_graphic_1024x500.png';

Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);
  final keyPath = Platform.environment['PLAY_SERVICE_ACCOUNT_JSON'];
  if (keyPath == null || !File(keyPath).existsSync()) {
    stderr.writeln('環境変数 PLAY_SERVICE_ACCOUNT_JSON にサービスアカウント鍵(JSON)のパスを設定してください');
    exitCode = 2;
    return;
  }
  final credentials = ServiceAccountCredentials.fromJson(jsonDecode(await File(keyPath).readAsString()));
  final client = await clientViaServiceAccount(credentials, [AndroidPublisherApi.androidpublisherScope]);
  final api = AndroidPublisherApi(client);

  try {
    final edit = await api.edits.insert(AppEdit(), kPackageName);
    final editId = edit.id!;
    stdout.writeln('edit開始: $editId');

    if (opts.aab != null) {
      final file = File(opts.aab!);
      if (!file.existsSync()) throw ArgumentError('AABが見つかりません: ${opts.aab}');
      stdout.writeln('AABアップロード中: ${opts.aab} (${(file.lengthSync() / 1024 / 1024).toStringAsFixed(1)}MB)');
      final bundle = await api.edits.bundles.upload(
        kPackageName,
        editId,
        uploadMedia: Media(file.openRead(), file.lengthSync()),
        uploadOptions: ResumableUploadOptions(),
      );
      final versionCode = bundle.versionCode!;
      stdout.writeln('versionCode=$versionCode');

      final notes = opts.notes != null ? await File(opts.notes!).readAsString() : null;
      final release = TrackRelease(
        status: opts.status,
        versionCodes: ['$versionCode'],
        releaseNotes: notes == null ? null : [LocalizedText(language: kLanguage, text: notes.trim())],
        userFraction: opts.status == 'inProgress' ? opts.rollout : null,
      );
      await api.edits.tracks.update(
        Track(track: opts.track, releases: [release]),
        kPackageName,
        editId,
        opts.track,
      );
      stdout.writeln('トラック ${opts.track} に ${opts.status} で配置');
    }

    if (opts.listing) {
      final listing = _parseListing(await File(kListingSource).readAsString());
      await api.edits.listings.update(
        Listing(
          language: kLanguage,
          title: listing.title,
          shortDescription: listing.short,
          fullDescription: listing.full,
        ),
        kPackageName,
        editId,
        kLanguage,
      );
      stdout.writeln('掲載文を更新: "${listing.title}" (${listing.title.length}字 / 短${listing.short.length}字 / 長${listing.full.length}字)');
    }

    if (opts.screenshots) {
      await _replaceImages(api, editId, 'phoneScreenshots',
          Directory(kScreenshotDir).listSync().whereType<File>().where((f) => f.path.endsWith('.png')).toList()
            ..sort((a, b) => a.path.compareTo(b.path)));
      await _replaceImages(api, editId, 'icon', [File(kIconPath)]);
      await _replaceImages(api, editId, 'featureGraphic', [File(kFeatureGraphicPath)]);
    }

    await api.edits.validate(kPackageName, editId);
    stdout.writeln('validate OK');
    if (opts.dryRun) {
      await api.edits.delete(kPackageName, editId);
      stdout.writeln('--dry-run のため commit せず終了');
      return;
    }
    await api.edits.commit(kPackageName, editId);
    stdout.writeln('commit 完了。Play Console で審査状況を確認してください');
  } finally {
    client.close();
  }
}

Future<void> _replaceImages(AndroidPublisherApi api, String editId, String imageType, List<File> files) async {
  await api.edits.images.deleteall(kPackageName, editId, kLanguage, imageType);
  for (final file in files) {
    await api.edits.images.upload(
      kPackageName,
      editId,
      kLanguage,
      imageType,
      uploadMedia: Media(file.openRead(), file.lengthSync(), contentType: 'image/png'),
    );
    stdout.writeln('画像アップロード: $imageType ← ${file.path}');
  }
}

// store/store_listing.md の「### アプリ名」「### 簡単な説明」「### 詳しい説明」直後のコードブロックを掲載文として読む
({String title, String short, String full}) _parseListing(String markdown) {
  String block(String heading) {
    final start = markdown.indexOf(heading);
    if (start < 0) throw StateError('見出しが見つかりません: $heading');
    final open = markdown.indexOf('```', start);
    final close = markdown.indexOf('```', open + 3);
    return markdown.substring(open + 3, close).trim();
  }
  final title = block('### アプリ名');
  final short = block('### 簡単な説明');
  final full = block('### 詳しい説明');
  if (title.length > 30) throw StateError('アプリ名が30字を超えています(${title.length})');
  if (short.length > 80) throw StateError('簡単な説明が80字を超えています(${short.length})');
  if (full.length > 4000) throw StateError('詳しい説明が4000字を超えています(${full.length})');
  return (title: title, short: short, full: full);
}

class _Options {
  String? aab;
  String track = 'internal';
  String status = 'draft';
  double rollout = 0.1;
  String? notes;
  bool listing = false;
  bool screenshots = false;
  bool dryRun = false;
}

_Options _parseArgs(List<String> args) {
  final o = _Options();
  for (final a in args) {
    if (a.startsWith('--aab=')) {
      o.aab = a.substring(6);
    } else if (a.startsWith('--track=')) {
      o.track = a.substring(8);
    } else if (a.startsWith('--status=')) {
      o.status = a.substring(9);
    } else if (a.startsWith('--rollout=')) {
      o.rollout = double.parse(a.substring(10));
    } else if (a.startsWith('--notes=')) {
      o.notes = a.substring(8);
    } else if (a == '--listing') {
      o.listing = true;
    } else if (a == '--screenshots') {
      o.screenshots = true;
    } else if (a == '--dry-run') {
      o.dryRun = true;
    } else {
      stderr.writeln('不明な引数: $a');
      exit(2);
    }
  }
  if (o.aab == null && !o.listing && !o.screenshots) {
    stderr.writeln('--aab=, --listing, --screenshots のいずれかを指定してください');
    exit(2);
  }
  return o;
}
