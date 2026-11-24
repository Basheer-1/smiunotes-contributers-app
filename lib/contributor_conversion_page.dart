import 'package:material_ui/material_ui.dart';
import 'contributor_api.dart';
import 'contributor_page_converter.dart';

class ContributorConversionPage extends StatefulWidget {
  const ContributorConversionPage({super.key, required this.noteId,
      required this.noteTitle, required this.api});
  final String noteId, noteTitle;
  final ContributorApi api;

  @override
  State<ContributorConversionPage> createState() => _ContributorConversionPageState();
}

class _ContributorConversionPageState extends State<ContributorConversionPage> {
  late final ContributorPageConverter converter = ContributorPageConverter(widget.api);
  Map<String, dynamic>? render;
  bool busy = true, converting = false;
  int done = 0, total = 0, previewPage = 1;
  String stage = '', error = '';
  String? previewUrl;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus({bool preserveError = false}) async {
    setState(() {
      busy = true;
      if (!preserveError) error = '';
    });
    try {
      final response = await converter.status(widget.noteId);
      if (!mounted) return;
      setState(() {
        render = response['render'] is Map<String, dynamic>
            ? response['render'] as Map<String, dynamic> : null;
      });
    } on ContributorApiException catch (e) {
      if (mounted) {
        setState(() => error = e.status == 404
            ? 'Native PDF conversion is awaiting a server update. Your draft is safe.'
            : 'Unable to fetch conversion status. Retry when online.');
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to fetch conversion status.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _prepare() async {
    if (busy || converting) return;
    setState(() { converting = true; error = ''; done = 0; total = 0; stage = 'Opening PDF'; });
    try {
      await converter.convert(widget.noteId, (current, pages, message) {
        if (!mounted) return;
        setState(() { done = current; total = pages; stage = message; });
      });
      await _checkStatus();
    } on ContributorApiException catch (e) {
      if (mounted) {
        setState(() => error = e.status == 404
          ? 'Native PDF conversion is awaiting a server update. Your draft is safe.'
          : 'Could not finish conversion. Reset partial pages before retrying.');
      }
      await _checkStatus(preserveError: true);
    } catch (_) {
      if (mounted) {
        setState(() => error =
          'Conversion was not completed. The already-uploaded original remains private. '
          'If interrupted, reset the conversion before retrying.');
      }
      await _checkStatus(preserveError: true);
    } finally {
      if (mounted) setState(() => converting = false);
    }
  }

  Future<void> _reset() async {
    if (busy || converting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Reset converted pages?'),
        content: const Text('This removes generated pages but keeps the original PDF. Use this when a conversion was interrupted or incorrect.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Reset pages')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { busy = true; error = ''; });
    try {
      await converter.reset(widget.noteId);
      if (!mounted) return;
      setState(() { render = null; previewUrl = null; previewPage = 1; });
    } catch (_) {
      if (mounted) setState(() => error = 'Reset could not be completed. Retry later.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _showPreview(int page) async {
    if (busy) return;
    setState(() { busy = true; error = ''; });
    try {
      final response = await widget.api.request('/api/mobile/v1/contributor-render',
        body: {'op': 'preview', 'id': widget.noteId, 'page': page});
      final url = response['url'];
      final uri = Uri.tryParse(url is String ? url : '');
      if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
        throw const FormatException('Invalid preview URL');
      }
      if (mounted) setState(() { previewUrl = uri.toString(); previewPage = page; });
    } catch (_) {
      if (mounted) setState(() => error = 'Preview unavailable. Please retry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = render?['state']?.toString() ?? '';
    final pages = render?['page_count'] is int
        ? render!['page_count'] as int : 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workspace', style: TextStyle(fontSize: 14)),
        actions: [Chip(label: const Text('Step 2 of 3',
          style: TextStyle(fontSize: 10)))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 35),
        children: [
        Container(padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: const Color(0xFF192A3C),
            borderRadius: BorderRadius.circular(11)),
          child: Row(children: [
            for (final step in [(1, '✓ Details'), (2, '2. Prepare PDF'),
                                (3, '3. Review')])
              Expanded(child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: step.$1 == 2 ? const Color(0xFF396D89) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8)),
                child: Text(step.$2, style: const TextStyle(fontSize: 10)))),
          ])),
        const SizedBox(height: 15),
        Text(widget.noteTitle, style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Prepare protected watermarked WebP pages. The existing '
          'PDF fingerprint and page verification checks remain enforced.',
          style: TextStyle(fontSize: 12, color: Color(0xFFB1C4D6))),
        const SizedBox(height: 16),
        if (busy || converting) const LinearProgressIndicator(),
        if (error.isNotEmpty) Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(error, style: TextStyle(
            color: Theme.of(context).colorScheme.error)),
        ),
        if (converting) Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(stage, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: total > 0 ? done / total : null),
            if (total > 0) Text('$done / $total pages'),
            const SizedBox(height: 8),
            const Text('Keep this screen open until server verification finishes.'),
          ]),
        )),
        if (!converting && render == null) ...[
          FilledButton.icon(
            onPressed: busy ? null : _prepare,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Prepare pages for publishing →'),
          ),
          const SizedBox(height: 8),
          const Text('The already-uploaded original PDF is fetched securely and converted automatically. No second file selection is needed.'),
        ],
        if (render != null) ...[
          Card(child: ListTile(
            leading: Icon(status == 'ready' ? Icons.verified_outlined
                : Icons.pending_actions_outlined),
            title: Text(status == 'ready' ? 'Watermarked pages ready for review'
              : 'Conversion status: $status'),
            subtitle: Text('$pages pages'),
          )),
          const SizedBox(height: 10),
          if (status == 'ready') ...[
            SizedBox(width: double.infinity, child: FilledButton.icon(
              key: const Key('conversion-continue-step3'),
              onPressed: busy ? null : () => Navigator.pop(context, true),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continue to Step 3 · Review'))),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: busy ? null : () => _showPreview(1),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview watermarked pages'),
            ),
            if (previewUrl != null) ...[
              const SizedBox(height: 16),
              Row(children: [
                IconButton(
                  key: const Key('conversion-close-preview'),
                  tooltip: 'Close preview',
                  onPressed: () => setState(() => previewUrl = null),
                  icon: const Icon(Icons.close)),
                IconButton(
                  onPressed: previewPage > 1 && !busy
                      ? () => _showPreview(previewPage - 1) : null,
                  icon: const Icon(Icons.chevron_left)),
                Expanded(child: Text('Page $previewPage of $pages',
                  textAlign: TextAlign.center)),
                IconButton(
                  onPressed: previewPage < pages && !busy
                      ? () => _showPreview(previewPage + 1) : null,
                  icon: const Icon(Icons.chevron_right)),
              ]),
              Image.network(previewUrl!, fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Text('Image expired; reopen preview.')),
            ],
            const SizedBox(height: 8),
            const Text('The Contributors App prepares pages. Publishing is handled by authorized administrators.'),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : _reset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset conversion'),
          ),
        ],
      ]),
    );
  }
}
