import 'package:flutter/material.dart';
import 'demo_seed.dart';
import 'home_page.dart';
import 'my_page.dart';
import 'theme.dart';

export 'home_page.dart';
export 'my_page.dart';
export 'series_page.dart';

// スクリーンショット撮影用の見本データを投入するフラグ(通常ビルドではfalse)
const bool kDemoMode = bool.fromEnvironment('DEMO_MODE');

Future<void> main() async {
  if (kDemoMode) {
    WidgetsFlutterBinding.ensureInitialized();
    await seedDemoData();
  }
  runApp(const GachaCollectorApp());
}

// アプリ全体の設計図
class GachaCollectorApp extends StatelessWidget {
  const GachaCollectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ガチャ活ポケット',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const MainScreen(),
    );
  }
}

// --- ボトムナビゲーションバーを持つアプリの骨格 ---
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    HomePage(),
    MyPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'マイページ',
          ),
        ],
      ),
    );
  }
}
