import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'pages/buttons_page.dart';
import 'pages/console_page.dart';
import 'pages/controller_page.dart';
import 'pages/settings_page.dart';
import 'state/app_state.dart';
import 'widgets/control_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
  runApp(ChangeNotifierProvider.value(value: state, child: const EspControlApp()));
}

class EspControlApp extends StatelessWidget {
  const EspControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: b),
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'ESP Control',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomeShell(),
    );
  }
}

class _PageDef {
  const _PageDef(this.title, this.icon, {this.landscape = false});
  final String title;
  final IconData icon;
  final bool landscape;
}

const _pages = [
  _PageDef('Controller', Icons.sports_esports, landscape: true),
  _PageDef('Buttons', Icons.grid_view),
  _PageDef('Console', Icons.terminal),
  _PageDef('Settings', Icons.settings),
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _applyOrientation();
  }

  void _select(int i) {
    setState(() => _index = i);
    _applyOrientation();
  }

  void _applyOrientation() {
    SystemChrome.setPreferredOrientations(_pages[_index].landscape
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : []);
    SystemChrome.setEnabledSystemUIMode(
        _pages[_index].landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final page = _pages[_index];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: page.landscape ? 44 : null,
        title: Text('${page.title} · ${state.active.name}', overflow: TextOverflow.ellipsis),
        actions: const [ConnectionButton(), SizedBox(width: 8)],
      ),
      drawer: NavigationDrawer(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          Navigator.pop(context);
          _select(i);
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 16, 10),
            child: Text('ESP Control', style: Theme.of(context).textTheme.titleLarge),
          ),
          for (final p in _pages) NavigationDrawerDestination(icon: Icon(p.icon), label: Text(p.title)),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: [
            const ControllerPage(),
            ButtonsPage(onOpenSettings: () => _select(3)),
            const ConsolePage(),
            const SettingsPage(),
          ],
        ),
      ),
    );
  }
}
