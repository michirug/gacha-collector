// --- ガチャの種類を定義 ---
enum GachaType {
  station('ガチャポン'),
  flat('フラットガシャポン'),
  premium('プレミアムガシャポン'),
  other('その他');

  const GachaType(this.label);
  final String label;
}

class GachaSeries {
  final String id;
  final String name;
  final GachaType gachaType;
  final DateTime releaseDate;
  final int price;
  final String mainImage;
  final String? description;
  final String? numTypes;
  final String? targetAge;
  final List<GachaItem> items;

  GachaSeries({
    required this.id,
    required this.name,
    required this.gachaType,
    required this.releaseDate,
    required this.price,
    required this.mainImage,
    this.description,
    this.numTypes,
    this.targetAge,
    required this.items,
  });

  factory GachaSeries.fromJson(Map<String, dynamic> json) {
    final seriesId = json['jan_code']?.toString() ?? '';
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
    return GachaSeries(
      id: seriesId,
      name: json['title']?.toString() ?? '名前なし',
      gachaType: type,
      releaseDate: DateTime.now(),
      price: int.tryParse(json['price']?.toString().replaceAll('円', '') ?? '') ?? 0,
      mainImage: json['image_url']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      numTypes: json['num_types']?.toString() ?? '',
      targetAge: json['target_age']?.toString() ?? '',
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

  CollectionEntry({
    required this.itemId,
    this.isFavorite = false,
    this.acquiredAt,
    this.paidPrice,
  });

  factory CollectionEntry.fromJson(Map<String, dynamic> json) {
    return CollectionEntry(
      itemId: json['itemId']?.toString() ?? '',
      isFavorite: json['isFavorite'] == true,
      acquiredAt: json['acquiredAt'] != null
          ? DateTime.tryParse(json['acquiredAt'].toString())
          : null,
      paidPrice: int.tryParse(json['paidPrice']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'isFavorite': isFavorite,
        if (acquiredAt != null) 'acquiredAt': acquiredAt!.toIso8601String(),
        if (paidPrice != null) 'paidPrice': paidPrice,
      };
}