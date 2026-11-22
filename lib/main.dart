import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp(const ContributorsApp());

/// Authentication and contributor authorization must be enforced by the
/// production website. Client-side navigation is not a security boundary.
class ContributorsApp extends StatelessWidget {
  const ContributorsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMIUNotes Contributors',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF326B8C)),
        scaffoldBackgroundColor: const Color(0xFF111E2C),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF182B3D),
          foregroundColor: Colors.white,
        ),
      ),
      home: const ContributorWorkspace(),
    );
  }
}

class ContributorWorkspace extends StatefulWidget {
  const ContributorWorkspace({super.key});

  @override
  State<ContributorWorkspace> createState() => _ContributorWorkspaceState();
}

class _ContributorWorkspaceState extends State<ContributorWorkspace> {
  static final Uri workspace = Uri.https('smiunotes.com', '/staff');
  late final WebViewController _controller;
  bool _loading = true;
  String? _loadError;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF142436))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() { _loading = true; _loadError = null; });
        },
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() { _loading = false; _loadError = error.description; });
          }
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          if (uri.scheme == 'https' &&
              (uri.host == 'smiunotes.com' || uri.host == 'www.smiunotes.com')) {
            final path = uri.path;
            if (path == '/staff' || path.startsWith('/staff/') ||
                path == '/login' || path.startsWith('/login/') ||
                path.startsWith('/auth/') || path.startsWith('/auth/') ||
                path.startsWith('/account-recovery') ||
                path.startsWith('/profile') || path.startsWith('/privacy')) {
              return NavigationDecision.navigate;
            }
          }
          if (uri.scheme == 'https' || uri.scheme == 'mailto') {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(workspace);
  }

  Future<void> _back() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else {
      await _controller.loadRequest(workspace);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SMIUNotes Contributors',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: 'Workspace home',
              icon: const Icon(Icons.space_dashboard_outlined),
              onPressed: () => _controller.loadRequest(workspace),
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () => _controller.reload(),
            ),
          ],
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(
                  value: _progress > 0 && _progress < 100 ? _progress / 100 : null,
                ),
              ),
            if (_loadError != null)
              ColoredBox(
                color: const Color(0xFF111E2C),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off, color: Colors.white70, size: 44),
                        const SizedBox(height: 12),
                        const Text('Could not open the contributor workspace',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text(_loadError!, textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => _controller.reload(),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
