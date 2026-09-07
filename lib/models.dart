// --- ガチャの種類を定義 ---
enum GachaType {
  station('ガチャポン'),
  flat('フラットガシャポン'),
  premium('プレミアムガシャポン'),
  other('その他');

  const GachaType(this.label);
  final String label;
}

// --- メーカー(データ提供元) ---
enum Maker {
  bandai('bandai', 'バンダイ', 'バンダイ'),
  takaratomyArts('takaratomy_arts', 'タカラトミーアーツ', 'T-ARTS'),
  kitan('kitan', 'キタンクラブ', 'キタンクラブ'),
  bushiroad('bushiroad', 'ブシロードクリエイティブ', 'ブシロード'),
  sota('sota', 'SO-TA', 'SO-TA'),
  other('other', 'その他', 'その他');

  const Maker(this.code, this.label, this.shortLabel);
  final String code;
  final String label;
  // バッジ等の狭い場所で使う短い表記
  final String shortLabel;

  static Maker fromCode(String? code) {
    if (code == null || code.isEmpty) return Maker.bandai;
    return Maker.values.firstWhere((m) => m.code == code,
        orElse: () => Maker.other);
  }
}

// 「2014年03月下旬」「2026年11月未定」「2026年8月第5週」などの表記をDateTimeに変換する
DateTime? parseJapaneseReleaseDate(String text) {
  final yearMonthMatch = RegExp(r'(\d{4})年\s*(\d{1,2})月').firstMatch(text);
  if (yearMonthMatch == null) {
    final yearMatch = RegExp(r'(\d{4})年').firstMatch(text);
    if (yearMatch == null) return null;
    return DateTime(int.parse(yearMatch.group(1)!));
  }
  final year = int.parse(yearMonthMatch.group(1)!);
  final month = int.parse(yearMonthMatch.group(2)!);
  if (month < 1 || month > 12) {
    return DateTime(year);
  }
  int day = 1;
  if (text.contains('上旬')) {
    day = 5;
  } else if (text.contains('中旬')) {
    day = 15;
  } else if (text.contains('下旬')) {
    day = 25;
  } else {
    final weekMatch = RegExp(r'第(\d)週').firstMatch(text);
    // 「2026年8月（8月31日週発売）」「9月14日週」のような日付付き表記
    final dayMatch = RegExp(r'(\d{1,2})月\s*(\d{1,2})日').firstMatch(text);
    if (weekMatch != null) {
      day = ((int.parse(weekMatch.group(1)!) - 1) * 7 + 1).clamp(1, 28);
    } else if (dayMatch != null &&
        int.parse(dayMatch.group(1)!) == month) {
      day = int.parse(dayMatch.group(2)!).clamp(1, 28);
    }
  }
  return DateTime(year, month, day);
}

// 「300円」「300円(税込)」「1回400円」「¥500」などから金額(円)を抜き出す
int parsePriceYen(String? text) {
  if (text == null) return 0;
  final match = RegExp(r'(\d[\d,]*)\s*円').firstMatch(text) ??
      RegExp(r'[¥￥]\s*(\d[\d,]*)').firstMatch(text);
  if (match == null) return int.tryParse(text.replaceAll(',', '')) ?? 0;
  return int.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
}

class GachaSeries {
  final String id;
  final String name;
  final GachaType gachaType;
  final Maker maker;
  final DateTime releaseDate;
  final String releaseDateText;
  final int price;
  final String mainImage;
  final String? numTypes;
  final String? targetAge;
  final String sourceUrl;
  // 公式サイトにラインナップ名が無く、「No.1」等の仮の名前でアイテムを生成している
  final bool lineupUnknown;
  final List<GachaItem> items;

  GachaSeries({
    required this.id,
    required this.name,
    required this.gachaType,
    this.maker = Maker.bandai,
    required this.releaseDate,
    this.releaseDateText = '',
    required this.price,
    required this.mainImage,
    this.numTypes,
    this.targetAge,
    this.sourceUrl = '',
    this.lineupUnknown = false,
    required this.items,
  });

  factory GachaSeries.fromJson(Map<String, dynamic> json) {
    final seriesId =
        json['id']?.toString() ?? json['jan_code']?.toString() ?? '';
    final itemsListFromJson = json['items'] as List<dynamic>? ?? [];
    final itemsList = itemsListFromJson
        .map((itemJson) =>
            GachaItem.fromJson(itemJson as Map<String, dynamic>, seriesId))
        .toList();
    GachaType type;
    switch (json['category']?.toString().toLowerCase()) {
      case 'station':
        type = GachaType.station;
        break;
      case 'flat':
        type = GachaType.flat;
        break;
      case 'premium':
        type = GachaType.premium;
        break;
      default:
        type = GachaType.other;
    }
    final releaseDateText = json['release_date']?.toString() ?? '';
    final maker = Maker.fromCode(json['maker']?.toString());
    var sourceUrl = json['source_url']?.toString() ?? '';
    // 旧データ(バンダイ)はsource_urlを持たないのでJANコードから組み立てる
    if (sourceUrl.isEmpty && maker == Maker.bandai && seriesId.isNotEmpty) {
      sourceUrl = 'https://gashapon.jp/products/detail.php?jan_code=$seriesId';
    }
    return GachaSeries(
      id: seriesId,
      name: json['title']?.toString() ?? '名前なし',
      gachaType: type,
      maker: maker,
      releaseDate: parseJapaneseReleaseDate(releaseDateText) ?? DateTime(1900),
      releaseDateText: releaseDateText,
      price: parsePriceYen(json['price']?.toString()),
      mainImage: json['image_url']?.toString() ?? '',
      numTypes: json['num_types']?.toString() ?? '',
      targetAge: json['target_age']?.toString() ?? '',
      sourceUrl: sourceUrl,
      lineupUnknown: json['lineup_unknown'] == true,
      items: itemsList,
    );
  }
}

class GachaItem {
  final String id;
  final String name;
  final String image;
  bool isFound;

  GachaItem({
    required this.id,
    required this.name,
    required this.image,
    this.isFound = false,
  });

  factory GachaItem.fromJson(Map<String, dynamic> json, String seriesId) {
    final rawId = (json['jan_code'] ?? json['title'])?.toString() ?? '';
    return GachaItem(
      id: '$seriesId::$rawId',
      name: json['title']?.toString() ?? '名前なし',
      image: json['image_url']?.toString() ?? '',
    );
  }
}

// --- 変更点：シンプル化 ---
// 保有数をなくし、「お気に入り」フラグだけを持つようにする
// このデータが存在すること自体が「保有している」ことを意味する
class CollectionEntry {
  final String itemId;
  bool isFavorite;
  DateTime? acquiredAt;
  int? paidPrice;
  int count;
  // ユーザーが撮った写真のファイル名(端末内 photos/ 配下)。バックアップJSONには含まれるが写真本体は含まれない
  String? photoPath;
  // みんなの図鑑に共有した場合の投稿ID(サーバー側 photos.id)。未共有なら null
  String? sharedPhotoId;

  CollectionEntry({
    required this.itemId,
    this.isFavorite = false,
    this.acquiredAt,
    this.paidPrice,
    this.count = 1,
    this.photoPath,
    this.sharedPhotoId,
  });

  factory CollectionEntry.fromJson(Map<String, dynamic> json) {
    return CollectionEntry(
      itemId: json['itemId']?.toString() ?? '',
      isFavorite: json['isFavorite'] == true,
      acquiredAt: json['acquiredAt'] != null
          ? DateTime.tryParse(json['acquiredAt'].toString())
          : null,
      paidPrice: int.tryParse(json['paidPrice']?.toString() ?? ''),
      count: int.tryParse(json['count']?.toString() ?? '') ?? 1,
      photoPath: json['photoPath']?.toString(),
      sharedPhotoId: json['sharedPhotoId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'isFavorite': isFavorite,
        if (acquiredAt != null) 'acquiredAt': acquiredAt!.toIso8601String(),
        if (paidPrice != null) 'paidPrice': paidPrice,
        'count': count,
        if (photoPath != null) 'photoPath': photoPath,
        if (sharedPhotoId != null) 'sharedPhotoId': sharedPhotoId,
      };
}