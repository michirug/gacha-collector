import 'package:flutter_test/flutter_test.dart';

import '../tool/crawl_gashapon.dart';

const _html = '''
<html><head><meta property="og:image" content="https://img.example/main.jpg"></head><body>
<h1 class="pg-heading">テスト ディスク01</h1>
<dl class="pg-detailDefinition"><dt>発売時期</dt><dd>2026年10月中旬</dd></dl>
<dl class="pg-detailDefinition"><dt>価格</dt><dd>300円</dd></dl>
<dl class="pg-detailDefinition"><dt>種類数</dt><dd>全6種</dd></dl>
<ul>
<li class="pg-detail__thumb swiper-slide"><img src="https://img.example/1.jpg" title="" alt=""></li>
<li class="pg-detail__thumb swiper-slide"><img src="https://img.example/2.jpg" title="孫悟空" alt=""></li>
<li class="pg-detail__thumb swiper-slide"><img src="" title="ベジータ" alt=""></li>
<li class="pg-detail__thumb swiper-slide"><img src="https://img.example/3.jpg" title="孫悟空" alt=""></li>
</ul>
</body></html>
''';

void main() {
  test('バンダイ: 個別画像の src が空でも名前があれば収録し、全N種に足りない分は No.k で埋める', () {
    final entry = parseDetailPage(_html, '4549660000000000', 'station')!;
    expect(entry['num_types'], '全6種');
    final items = (entry['items'] as List).cast<Map<String, String>>();
    expect(items.map((i) => i['title']).toList(), ['孫悟空', 'ベジータ', 'No.3', 'No.4', 'No.5', 'No.6']);
    expect(items[1]['image_url'], 'https://img.example/main.jpg'); // src 空 → メイン画像
    expect(items[2]['image_url'], 'https://img.example/main.jpg');
  });

  test('padItemsToTypeCount は種類数が不明・100超・既に足りている場合は何もしない', () {
    final items = [{'title': 'A', 'image_url': ''}];
    padItemsToTypeCount(items, '', 'm');
    padItemsToTypeCount(items, '全1種', 'm');
    padItemsToTypeCount(items, '全500種', 'm');
    expect(items.length, 1);
  });
}
