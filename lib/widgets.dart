import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'demo_art.dart';
import 'image_policy.dart';
import 'models.dart';
import 'theme.dart';

String formatYen(int amount) {
  final digits = amount.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (match) => '${match[1]},');
  return '$digits円';
}

// 「2026年9月上旬」→「9月上旬」のように年を省いた短い発売時期ラベル
String shortReleaseLabel(GachaSeries series) {
  final text = series.releaseDateText;
  if (text.isEmpty) return '発売時期未定';
  final match = RegExp(r'(\d{1,2})月\s*(上旬|中旬|下旬|第\d週|\d{1,2}日週)?').firstMatch(text);
  if (match == null) return text;
  final now = DateTime.now();
  final yearPrefix = series.releaseDate.year != now.year ? '${series.releaseDate.year}年' : '';
  return '$yearPrefix${match.group(1)}月${match.group(2) ?? ''}';
}

// 商品画像。表示優先順は ユーザー写真(端末内) → 公式画像(直リンク・キャッシュ) → プレースホルダー。
// 公式画像はトリミングせず(contain)全体を表示し、画像内の©表記・メーカーロゴを落とさない。
// ImagePolicy でメーカー単位に非表示指定されている場合は公式画像を出さない。
class GachaImage extends StatelessWidget {
  final String url;
  final Maker? maker;
  final File? localFile;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const GachaImage(
    this.url, {
    super.key,
    this.maker,
    this.localFile,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: ImagePolicy.hiddenMakers,
      builder: (context, _, _) {
        final placeholder = Container(
          width: width,
          height: height,
          color: kBrandPurple.withValues(alpha: 0.06),
          child: Icon(Icons.toys_outlined,
              size: 24, color: kBrandPurple.withValues(alpha: 0.35)),
        );
        Widget image;
        if (localFile != null) {
          // ユーザー写真は自分で撮ったものなので枠を埋める表示(cover)で良い
          image = Image.file(localFile!,
              width: width, height: height, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder);
        } else if (ImagePolicy.useDemoArt && url.isNotEmpty) {
          image = SizedBox(width: width, height: height, child: DemoCapsuleArt(url));
        } else if (url.isEmpty || ImagePolicy.isMakerHidden(maker)) {
          image = placeholder;
        } else {
          image = CachedNetworkImage(
            imageUrl: url,
            width: width,
            height: height,
            fit: fit,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );
        }
        if (borderRadius == null) return image;
        return ClipRRect(borderRadius: borderRadius!, child: image);
      },
    );
  }
}

// 「画像: ○○公式サイト」の出典表記
class ImageCredit extends StatelessWidget {
  final Maker maker;
  const ImageCredit(this.maker, {super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: ImagePolicy.hiddenMakers,
      builder: (context, _, _) {
        if (ImagePolicy.useDemoArt) return const SizedBox.shrink();
        final hidden = ImagePolicy.isMakerHidden(maker);
        return Text(
          hidden ? '公式画像は現在表示していません' : '画像: ${maker.label}公式サイトより(権利は各権利者に帰属)',
          style: TextStyle(fontSize: 10.5, color: Colors.grey[600]),
        );
      },
    );
  }
}

class MakerBadge extends StatelessWidget {
  final Maker maker;
  final bool compact;
  const MakerBadge(this.maker, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: kBrandPurple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        compact ? maker.shortLabel : maker.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: kBrandPurpleDark,
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onMore;
  final String moreLabel;

  const SectionHeader(this.title,
      {super.key, this.subtitle, this.onMore, this.moreLabel = 'すべて見る'});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800, color: kBrandInk)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
          if (onMore != null)
            TextButton(
              onPressed: onMore,
              child: Text(moreLabel, style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

// 横スクロール用のポスター型カード
class SeriesPosterCard extends StatelessWidget {
  final GachaSeries series;
  final VoidCallback onTap;
  final bool isWished;
  final VoidCallback? onWishTap;
  final String? footer;

  const SeriesPosterCard({
    super.key,
    required this.series,
    required this.onTap,
    this.isWished = false,
    this.onWishTap,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  GachaImage(series.mainImage, maker: series.maker, width: 150, height: 150),
                  if (onWishTap != null)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onWishTap,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              isWished ? Icons.star_rounded : Icons.star_outline_rounded,
                              size: 20,
                              color: isWished ? Colors.amber[700] : Colors.grey[500],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(series.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.3)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Flexible(child: MakerBadge(series.maker, compact: true)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      footer ?? '${shortReleaseLabel(series)}・${formatYen(series.price)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 縦リスト用のタイル
class SeriesTile extends StatelessWidget {
  final GachaSeries series;
  final VoidCallback onTap;
  final bool isWished;
  final VoidCallback? onWishTap;
  final int? collected;

  const SeriesTile({
    super.key,
    required this.series,
    required this.onTap,
    this.isWished = false,
    this.onWishTap,
    this.collected,
  });

  @override
  Widget build(BuildContext context) {
    final total = series.items.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              GachaImage(series.mainImage, maker: series.maker,
                  width: 72, height: 72, borderRadius: BorderRadius.circular(12)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(series.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700, height: 1.3)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        MakerBadge(series.maker, compact: true),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${shortReleaseLabel(series)}・${formatYen(series.price)}・全$total種',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (collected != null && total > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: collected! / total,
                                minHeight: 6,
                                backgroundColor: kBrandPurple.withValues(alpha: 0.1),
                                color: collected == total ? Colors.amber[700] : kBrandPurple,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('$collected/$total',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (onWishTap != null)
                IconButton(
                  onPressed: onWishTap,
                  tooltip: 'ウィッシュリスト',
                  icon: Icon(
                    isWished ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isWished ? Colors.amber[700] : Colors.grey[400],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyHint({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBrandPurple.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, color: kBrandPurple.withValues(alpha: 0.5)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}
