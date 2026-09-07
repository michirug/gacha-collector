import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'my_page.dart' show kTermsOfServiceUrl, kPrivacyPolicyUrl;
import 'theme.dart';

// 写真共有の初回同意ダイアログ。Google Play UGC ポリシーが求める「利用規約への同意」をここで取る。
// 戻り値: true=同意して共有、false/null=共有しない
Future<bool?> showCommunityConsentDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.public, color: kBrandPurple),
          SizedBox(width: 8),
          Expanded(child: Text('みんなの図鑑に写真を共有')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'あなたが撮った写真を、他のユーザーの図鑑画像としても使えるようにします。',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 12),
            _rule(Icons.check_circle_outline, '自分で撮った写真だけを共有できます(公式画像や他人の写真の転載は不可)'),
            _rule(Icons.check_circle_outline, '人物の顔や個人情報が写った写真は共有しないでください'),
            _rule(Icons.check_circle_outline, '写真は縮小され、位置情報などのメタデータは送信前に削除されます'),
            _rule(Icons.check_circle_outline, '内容の確認(自動判定と他のユーザーの承認)を経てから表示されます'),
            _rule(Icons.check_circle_outline, '共有はいつでも取り消せます。氏名などの個人情報は送信されません'),
            const SizedBox(height: 12),
            Text(
              '共有した写真は、アプリ内での表示・縮小・トリミング・配信のために利用者から当方へ無償で利用が許諾されます。詳しくは利用規約・プライバシーポリシーをご確認ください。',
              style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5),
            ),
            Wrap(
              children: [
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(kTermsOfServiceUrl), mode: LaunchMode.externalApplication),
                  child: const Text('利用規約', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(kPrivacyPolicyUrl), mode: LaunchMode.externalApplication),
                  child: const Text('プライバシーポリシー', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('共有しない'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('同意して共有する'),
        ),
      ],
    ),
  );
}

Widget _rule(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: kBrandPurple),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
        ],
      ),
    );
