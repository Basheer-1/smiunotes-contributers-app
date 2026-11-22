import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Production Turnstile widget hosted on SMIUNotes itself.
/// The backend verifies token action, hostname, and expiry.
Future<String?> requestContributorChallenge(BuildContext context) async {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ChallengeDialog(),
  );
}

class _ChallengeDialog extends StatefulWidget {
  const _ChallengeDialog();
  @override
  State<_ChallengeDialog> createState() => _ChallengeDialogState();
}

class _ChallengeDialogState extends State<_ChallengeDialog> {
  late final WebViewController controller;
  String? error;
  bool completed = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri != null && uri.scheme == 'https' &&
              (uri.host == 'smiunotes.com' ||
                  uri.host == 'challenges.cloudflare.com')) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
        onWebResourceError: (value) {
          if (value.isForMainFrame == true && mounted) {
            setState(() => error = 'Security challenge could not load.');
          }
        },
      ))
      ..addJavaScriptChannel('TurnstileBridge',
        onMessageReceived: (message) {
          final token = message.message;
          if (!completed && mounted && token.length >= 10 &&
              token.length <= 2048) {
            completed = true;
            Navigator.of(context).pop(token);
          }
        })
      ..loadRequest(Uri.https('smiunotes.com', '/api/mobile/v1/challenge'));
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            const Expanded(child: Text('Security verification',
                style: TextStyle(fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ]),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
          Expanded(child: WebViewWidget(controller: controller)),
        ]),
      ),
    ),
  );
}
