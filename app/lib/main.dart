import 'package:flutter/cupertino.dart';

import 'native.dart';
import 'pages/configuration_page.dart';
import 'pages/detail_page.dart';
import 'pages/home_page.dart';
import 'pages/log_page.dart';
import 'pages/settings_page.dart';
import 'pages/setup_page.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AutoreplyApp());
}

/// Shared app state. Small enough that a ChangeNotifier beats a state-management
/// package — the native layer is the source of truth and this just caches its answer.
class AppController extends ChangeNotifier {
  AppStatus? _status;
  Object? _error;
  bool _loading = true;

  AppStatus? get status => _status;
  Object? get error => _error;
  bool get loading => _loading;

  Future<void> refresh() async {
    try {
      _status = await Native.status();
      _error = null;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Applies a setting and adopts the status the native layer hands back, so any
  /// side effect it triggered is reflected immediately.
  Future<void> set(String key, String value) async {
    _status = await Native.setSetting(key, value);
    notifyListeners();
  }

  void adopt(AppStatus status) {
    _status = status;
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController super.notifier, required super.child});

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class AutoreplyApp extends StatefulWidget {
  const AutoreplyApp({super.key});

  @override
  State<AutoreplyApp> createState() => _AutoreplyAppState();
}

class _AutoreplyAppState extends State<AutoreplyApp> with WidgetsBindingObserver {
  final AppController _controller = AppController();
  final GlobalKey<_RootTabsState> _tabsKey = GlobalKey<_RootTabsState>();
  String? _pendingRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    Native.listen(
      onNavigate: _handleRoute,
      onPermissionsChanged: () => _controller.refresh(),
    );

    _controller.refresh().then((_) async {
      final route = await Native.takeInitialRoute();
      if (route != null) _handleRoute(route);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from a system settings page or the call screen: re-read everything.
    if (state == AppLifecycleState.resumed) _controller.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  void _handleRoute(String route) {
    final tabs = _tabsKey.currentState;
    if (tabs == null) {
      _pendingRoute = route;
      return;
    }
    tabs.openRoute(route);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: _controller,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final status = _controller.status;
          final platformBrightness = MediaQuery.maybePlatformBrightnessOf(context) ??
              Brightness.light;
          final theme = appTheme(status?.theme ?? 'system', platformBrightness);

          return CupertinoApp(
            title: 'Autoreply',
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: Builder(
              builder: (context) {
                if (_controller.loading) {
                  return const CupertinoPageScaffold(
                    child: Center(child: CupertinoActivityIndicator()),
                  );
                }
                if (status == null) {
                  return _StartupFailure(
                    error: _controller.error,
                    onRetry: _controller.refresh,
                  );
                }
                if (!status.setupComplete) {
                  return SetupPage(onFinished: _controller.refresh);
                }
                return _RootTabs(key: _tabsKey, initialRoute: _takePendingRoute());
              },
            ),
          );
        },
      ),
    );
  }

  String? _takePendingRoute() {
    final route = _pendingRoute;
    _pendingRoute = null;
    return route;
  }
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.exclamationmark_triangle, size: 44, color: colors.warning),
              const SizedBox(height: 14),
              Text('Autoreply could not start',
                  style: AppText.headline.copyWith(color: colors.label)),
              const SizedBox(height: 6),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: AppText.footnote.copyWith(color: colors.secondaryLabel),
              ),
              const SizedBox(height: 20),
              CupertinoButton.filled(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}

/// The four-tab shell. Each tab keeps its own navigation stack, iOS-style.
class _RootTabs extends StatefulWidget {
  const _RootTabs({super.key, this.initialRoute});

  final String? initialRoute;

  @override
  State<_RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<_RootTabs> {
  final CupertinoTabController _tabController = CupertinoTabController();
  final List<GlobalKey<NavigatorState>> _navKeys =
      List.generate(4, (_) => GlobalKey<NavigatorState>());

  int? _logDayFilter;

  @override
  void initState() {
    super.initState();
    final route = widget.initialRoute;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openRoute(route));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Handles the deep links the native notifications use.
  Future<void> openRoute(String route) async {
    final uri = Uri.parse(route);
    final segments = uri.pathSegments;

    if (segments.isEmpty) return;

    if (segments.first == 'log') {
      final day = uri.queryParameters['day'];
      setState(() => _logDayFilter = day == null ? null : int.tryParse(day));
      _tabController.index = 1;

      // ".../log/outbox/42" — open the call that message belongs to.
      if (segments.length >= 3 && segments[1] == 'outbox') {
        final outboxId = int.tryParse(segments[2]);
        if (outboxId == null) return;
        final detail = await Native.entryForOutbox(outboxId);
        if (detail == null || !mounted) return;
        _navKeys[1].currentState?.push(
              CupertinoPageRoute<void>(
                builder: (_) => DetailPage(callId: detail.id),
              ),
            );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return CupertinoTabScaffold(
      controller: _tabController,
      tabBar: CupertinoTabBar(
        backgroundColor: colors.card.withValues(alpha: 0.94),
        activeColor: colors.tint,
        inactiveColor: colors.secondaryLabel,
        border: Border(top: BorderSide(color: colors.separator, width: 0.5)),
        items: const [
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.house_fill), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.list_bullet), label: 'Log'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.slider_horizontal_3), label: 'Rules'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.gear_alt_fill), label: 'Settings'),
        ],
      ),
      tabBuilder: (context, index) => CupertinoTabView(
        navigatorKey: _navKeys[index],
        builder: (context) => switch (index) {
          0 => HomePage(onOpenTab: (i) => _tabController.index = i),
          1 => LogPage(initialDayFilter: _logDayFilter),
          2 => const ConfigurationPage(),
          _ => const SettingsPage(),
        },
      ),
    );
  }
}
