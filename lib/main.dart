import 'package:material_ui/material_ui.dart';

import 'home_page.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DocStore();
  await store.load();
  runApp(LembarApp(store: store));
}

class LembarApp extends StatelessWidget {
  const LembarApp({super.key, required this.store});
  final DocStore store;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F6F6B), brightness: b),
        );
    return MaterialApp(
      title: 'Lembar',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: HomePage(store: store),
    );
  }
}
