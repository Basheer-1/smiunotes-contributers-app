import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'contributor_navigation.dart';

void main() => runApp(const ContributorsApp());

const _blue = Color(0xFF1F527E);
const _ink = Color(0xFF132E49);
const _pages = <String>[
  '/staff',
  '/staff/notes/new',
  '/staff?status=draft',
  '/profile',
  '/notifications',
];

class ContributorsApp extends StatelessWidget {
  const ContributorsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SMIUNotes Contributors',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _blue),
      scaffoldBackgroundColor: const Color(0xFFF0F5F9),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Color(0xFFF0F5F9),
        foregroundColor: _ink,
      ),
    ),
    home: const ContributorWorkspace(),
  );
}

class ContributorWorkspace extends StatefulWidget {
  const ContributorWorkspace({super.key});

  @override
  State<ContributorWorkspace> createState() => _ContributorWorkspaceState();
}

class _ContributorWorkspaceState extends State<ContributorWorkspace> {
  late final WebViewController _controller;
  int selected = 0;
  bool _loading = true;
  String? _error;
  int _progress = 0;
  bool _loginMode = true;

  Uri get _start => Uri.https('smiunotes.com', '/verify');

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF0F5F9))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          if (!mounted) return;
          final path = Uri.tryParse(url)?.path ?? '';
          setState(() {
            _loading = true;
            _error = null;
            _loginMode = path == '/verify' || path == '/login' ||
                path.startsWith('/auth/');
          });
        },
        onProgress: (percent) {
          if (mounted) setState(() => _progress = percent);
        },
        onPageFinished: (url) {
          if (!mounted) return;
          setState(() => _loading = false);
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() {
              _loading = false;
              _error = error.description;
            });
          }
        },
        onNavigationRequest: (request) {
          final decision = ContributorNavigation.classify(request.url);
          if (decision == ContributorDestination.internal) {
            return NavigationDecision.navigate;
          }
          if (decision == ContributorDestination.external) {
            final uri = Uri.tryParse(request.url);
            if (uri != null) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(_start);
    if (_controller.platform is AndroidWebViewController) {
      final android = _controller.platform as AndroidWebViewController;
      android.setOnShowFileSelector((params) async {
        try {
          final selected = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: const ['pdf'],
            allowMultiple: params.mode == FileSelectorMode.openMultiple,
            withData: false,
          );
          if (selected == null) return const <String>[];
          return selected.files
              .where((file) => file.path != null &&
                  file.extension?.toLowerCase() == 'pdf')
              .map((file) => Uri.file(file.path!).toString())
              .toList(growable: false);
        } catch (_) {
          return const <String>[];
        }
      });
    }
  }

  Future<void> _openTab(int index) async {
    if (index < 0 || index >= _pages.length) return;
    setState(() { selected = index; _error = null; });
    await _controller.loadRequest(Uri.https('smiunotes.com', _pages[index].split('?').first,
      _pages[index].contains('?') ? {'status': 'draft'} : null));
  }

  Future<void> _back() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else {
      await _openTab(0);
    }
  }

  Future<void> _refresh() => _controller.reload();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 14,
          title: const Row(children: [
            Icon(Icons.auto_stories_rounded, color: _blue, size: 25),
            SizedBox(width: 9),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SMIUNotes', style: TextStyle(fontSize: 19,
                    fontWeight: FontWeight.w800)),
                Text('Contributors Workspace',
                    style: TextStyle(fontSize: 10, color: Color(0xFF64778A))),
              ],
            )),
          ]),
          actions: [
            IconButton(
              tooltip: 'Open login',
              onPressed: () => _controller.loadRequest(_start),
              icon: const Icon(Icons.account_circle_outlined),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Stack(children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(
                value: _progress > 0 && _progress < 100
                    ? _progress / 100 : null,
              ),
            ),
          if (_error != null)
            ColoredBox(
              color: const Color(0xFFF0F5F9),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.cloud_off_outlined,
                        color: colors.onSurfaceVariant, size: 50),
                    const SizedBox(height: 14),
                    const Text('Unable to load SMIUNotes',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
        bottomNavigationBar: _loginMode ? null : NavigationBar(
          height: 72,
          selectedIndex: selected,
          onDestinationSelected: _openTab,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
            NavigationDestination(icon: Icon(Icons.upload_file_outlined),
                selectedIcon: Icon(Icons.upload_file), label: 'Upload'),
            NavigationDestination(icon: Icon(Icons.folder_copy_outlined),
                selectedIcon: Icon(Icons.folder_copy), label: 'Notes'),
            NavigationDestination(icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person), label: 'Profile'),
            NavigationDestination(icon: Icon(Icons.notifications_none),
                selectedIcon: Icon(Icons.notifications), label: 'Inbox'),
          ],
        ),
      ),
    );
  }
}
