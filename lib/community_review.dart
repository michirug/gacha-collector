import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'community_photos.dart';
import 'community_service.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

// みんなの図鑑: 他ユーザーの審査中写真を「この写真は合ってる?」と1タップで確認するカード。
// 3人の承認で採用(approve_photo RPC)。「違う」は wrong_item の通報として扱い、3件で保留になる。
// 表示条件: Supabase 設定済み かつ 写真共有に参加している(同意済み/サインイン済み)ユーザーのみ。
class PhotoReviewCard extends StatefulWidget {
  final GachaSeries series;
  const PhotoReviewCard({super.key, required this.series});

  @override
  State<PhotoReviewCard> createState() => _PhotoReviewCardState();
}

class _PhotoReviewCardState extends State<PhotoReviewCard> {
  List<PendingPhoto> _queue = const [];
  bool _loaded = false;
  bool _busy = false;
  int _judged = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!await CommunityService.canReview()) return;
    try {
      final photos = await CommunityService.pendingPhotosForReview(widget.series.id);
      if (!mounted) return;
      setState(() {
        _queue = photos;
        _loaded = true;
      });
    } catch (_) {}
  }

  String _itemName(PendingPhoto photo) {
    for (final item in widget.series.items) {
      if (item.id == photo.itemId) return item.name;
    }
    return photo.itemLabel?.split(' / ').last ?? photo.itemId.split('::').last;
  }

  Future<void> _act(Future<void> Function() action, String doneMessage) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(doneMessage), duration: const Duration(seconds: 1)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('送信できませんでした: $e')));
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _judged++;
      if (_queue.isNotEmpty) _queue = _queue.sublist(1);
    });
  }

  void _skip() => setState(() => _queue = _queue.isEmpty ? _queue : [..._queue.sublist(1), _queue.first]);

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _queue.isEmpty) return const SizedBox.shrink();
    final photo = _queue.first;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      color: kBrandPurple.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.how_to_vote_outlined, size: 18, color: kBrandPurpleDark),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('みんなの図鑑: この写真は合ってる?',
                      style: TextStyle(fontWeight: FontWeight.w800, color: kBrandInk)),
                ),
                Text('残り${_queue.length}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                PopupMenuButton<String>(
                  tooltip: 'その他',
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'skip') _skip();
                    if (value == 'report') _report(photo);
                    if (value == 'block') _block(photo);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'skip', child: Text('あとで')),
                    PopupMenuItem(value: 'report', child: Text('通報する')),
                    PopupMenuItem(value: 'block', child: Text('この投稿者を表示しない')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: photo.url,
                    width: 110,
                    height: 110,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(width: 110, height: 110, color: Colors.white),
                    errorWidget: (_, _, _) => Container(
                        width: 110, height: 110, color: Colors.white,
                        child: const Icon(Icons.broken_image_outlined, color: Colors.grey)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_itemName(photo),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('他のユーザーが投稿した写真です。このアイテムの写真として正しければ「合ってる」を押してください。3人の承認で図鑑に採用されます。',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey[700], height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _act(
                        () => CommunityService.reportPhoto(photo.id, 'wrong_item'), '「違う」を送りました'),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('違う'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _act(
                        () => CommunityService.approvePhoto(photo.id), '承認しました。ありがとう!'),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('合ってる'),
                  ),
                ),
              ],
            ),
            if (_judged > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('このシリーズで$_judged件チェックしました',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _report(PendingPhoto photo) async {
    final reason = await showReportReasonSheet(context);
    if (reason == null) return;
    await _act(() => CommunityService.reportPhoto(photo.id, reason), '通報しました。確認します');
  }

  Future<void> _block(PendingPhoto photo) async {
    final ok = await confirmBlockPoster(context);
    if (ok != true) return;
    await _act(() => CommunityService.blockPoster(photo.posterId), 'この投稿者の写真を表示しないようにしました');
    if (mounted) setState(() => _queue = _queue.where((p) => p.posterId != photo.posterId).toList());
  }
}

// 通報理由の選択シート。戻り値は kReportReasons の code
Future<String?> showReportReasonSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('この写真を通報する', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('通報は匿名で送られ、3件で写真は非表示になり運営が確認します。',
                style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          ),
          for (final reason in kReportReasons)
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(reason.label),
              onTap: () => Navigator.pop(sheetContext, reason.code),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<bool?> confirmBlockPoster(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('この投稿者を表示しない'),
      content: const Text('この投稿者の写真を、あなたの端末では今後表示しません(みんなの図鑑・承認の候補の両方)。マイページから解除できます。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('キャンセル')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('表示しない')),
      ],
    ),
  );
}

// 採用写真への「いいね」。押した直後は端末側で件数を補正して即時反映する
class CommunityLikeButton extends StatelessWidget {
  final CommunityPhoto photo;
  final bool compact;
  const CommunityLikeButton(this.photo, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final photoId = photo.photoId;
    if (photoId == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([CommunityPhotos.likedPhotos, CommunityPhotos.likeAdjust]),
      builder: (context, _) {
        final liked = CommunityPhotos.isLiked(photoId);
        final count = CommunityPhotos.likeCount(photo);
        return TextButton.icon(
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: liked ? kBrandPinkDark : Colors.grey[700],
          ),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              await CommunityService.toggleLike(photoId);
            } catch (e) {
              messenger.showSnackBar(SnackBar(content: Text('送信できませんでした: $e')));
            }
          },
          icon: Icon(liked ? Icons.favorite : Icons.favorite_border, size: compact ? 16 : 18),
          label: Text(count > 0 ? '$count' : 'いいね', style: TextStyle(fontSize: compact ? 11 : 12)),
        );
      },
    );
  }
}

// 採用済み写真(みんなの図鑑)に対する操作メニュー: いいね / 通報 / 投稿者をブロック
Future<void> showCommunityPhotoMenu(BuildContext context,
    {required String? photoId, required String? posterId, CommunityPhoto? photo}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              const Expanded(child: Text('みんなの図鑑の写真', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              if (photo != null) CommunityLikeButton(photo),
            ]),
          ),
          if (photo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(communityCreditText(photo, myUserId: CommunityService.currentUserId),
                  style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            ),
          if (photoId != null)
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('この写真を通報する'),
              onTap: () => Navigator.pop(sheetContext, 'report'),
            ),
          if (posterId != null)
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('この投稿者を表示しない'),
              onTap: () => Navigator.pop(sheetContext, 'block'),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (action == 'report') {
      final reason = await showReportReasonSheet(context);
      if (reason == null) return;
      await CommunityService.reportPhoto(photoId!, reason);
      messenger.showSnackBar(const SnackBar(content: Text('通報しました。確認します')));
    } else if (action == 'block') {
      final ok = await confirmBlockPoster(context);
      if (ok != true) return;
      await CommunityService.blockPoster(posterId!);
      messenger.showSnackBar(const SnackBar(content: Text('この投稿者の写真を表示しないようにしました')));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('送信できませんでした: $e')));
  }
}
