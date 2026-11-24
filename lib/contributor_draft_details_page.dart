import 'package:material_ui/material_ui.dart';
import 'contributor_api.dart';
import 'contributor_pdf_uploader.dart';
import 'contributor_conversion_page.dart';
import 'contributor_glass.dart';

/// A dedicated, beginner-friendly draft workflow. All media state comes from
/// the server; the UI never assumes that an original PDF exists.
class ContributorDraftDetailsPage extends StatefulWidget {
  const ContributorDraftDetailsPage({
    super.key,
    required this.api,
    required this.note,
    required this.subjects,
    required this.onChanged,
  });

  final ContributorApi api;
  final Map<String, dynamic> note;
  final List<Map<String, dynamic>> subjects;
  final Future<void> Function() onChanged;

  @override
  State<ContributorDraftDetailsPage> createState() =>
      _ContributorDraftDetailsPageState();
}

class _ContributorDraftDetailsPageState
    extends State<ContributorDraftDetailsPage> {
  late final ContributorPdfUploader uploader = ContributorPdfUploader(widget.api);
  bool loading = true;
  bool working = false;
  bool? pdfExists;
  bool pagesReady = false;
  int activeStep = 2;
  bool reviewedPages = false;
  bool finishedReview = false;
  String? message;
  String? uploadedFilename;
  String action = '';

  String get noteId => widget.note['id']?.toString() ?? '';
  bool get isDraft => widget.note['status'] == 'draft';

  @override
  void initState() {
    super.initState();
    if (isDraft) {
      _loadStatus();
    } else {
      loading = false;
    }
  }

  Future<void> _loadStatus() async {
    if (noteId.isEmpty) {
      if (mounted) {
        setState(() {
          loading = false;
          message = 'Note identifier missing. Reopen this note.';
        });
      }
      return;
    }
    if (mounted) setState(() { loading = true; message = null; });
    try {
      final present = await uploader.originalExists(noteId);
      bool ready = false;
      if (present) {
        try {
          final status = await widget.api.request(
            '/api/mobile/v1/contributor-render',
            body: {'op': 'status', 'id': noteId},
          );
          final render = status['render'];
          ready = render is Map<String, dynamic> &&
              render['state'] == 'ready';
        } catch (_) {
          // The PDF exists; page status may be checked again later.
        }
      }
      if (!mounted) return;
      setState(() {
        pdfExists = present;
        pagesReady = ready;
        if (ready) activeStep = 3;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          pdfExists = null;
          message = 'Unable to check your original PDF. Check your connection and retry.';
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _upload() async {
    if (loading || working || pdfExists != false) return;
    setState(() {
      working = true;
      action = 'Uploading PDF to private storage and verifying it…';
      message = null;
    });
    try {
      final uploaded = await uploader.chooseAndUpload(noteId);
      if (!mounted) return;
      if (!uploaded) {
        setState(() => action = '');
        return;
      }
      // A successful uploader result means that server-side verification
      // accepted the private PDF. Keep the user on this page.
      setState(() {
        pdfExists = true;
        pagesReady = false;
        uploadedFilename = uploader.lastUploadedFileName;
        action = '';
        message = 'PDF uploaded and verified successfully. Next: prepare its pages.';
      });
      await widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(() {
          action = '';
          message = e is ContributorApiException && e.status == 409
              ? 'This draft already has a PDF. Refresh the status before continuing.'
              : 'Upload did not finish. Your draft is safe. Check the PDF and retry.';
        });
      }
      await _loadStatus();
    } finally {
      if (mounted) setState(() { working = false; action = ''; });
    }
  }

  Future<void> _removePdf() async {
    if (loading || working || pdfExists != true || pagesReady) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove uploaded PDF?'),
        content: const Text(
          'This only removes your original PDF. Your draft stays saved. '
          'You can select another PDF afterward.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove PDF')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      working = true;
      action = 'Removing original PDF…';
      message = null;
    });
    try {
      await uploader.removeOriginal(noteId);
      if (!mounted) return;
      setState(() {
        pdfExists = false;
        pagesReady = false;
        uploadedFilename = null;
        message = 'PDF removed. Upload your new PDF below.';
      });
      await widget.onChanged();
    } catch (_) {
      if (mounted) {
        setState(() => message =
            'Could not remove PDF. Reset converted pages first, or retry.');
      }
      await _loadStatus();
    } finally {
      if (mounted) setState(() { working = false; action = ''; });
    }
  }

  Future<void> _convert() async {
    if (working || pdfExists != true) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ContributorConversionPage(
        noteId: noteId,
        noteTitle: widget.note['title']?.toString() ?? 'Draft',
        api: widget.api,
      ),
    ));
    if (!mounted) return;
    await _loadStatus();
    await widget.onChanged();
  }

  Future<void> _edit() async {
    if (working || !isDraft) return;
    final title = TextEditingController(
        text: widget.note['title']?.toString() ?? '');
    final description = TextEditingController(
        text: widget.note['description']?.toString() ?? '');
    String? selected = widget.note['subject_id']?.toString();
    bool saving = false;
    bool verifiedOnly = widget.note['is_sensitive'] == true;
    String? fieldError;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, update) => AlertDialog(
            title: const Text('Edit draft details'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: widget.subjects.any(
                    (s) => s['id'] == selected) ? selected : null,
                  decoration: const InputDecoration(labelText: 'Subject'),
                  items: widget.subjects.map((s) => DropdownMenuItem<String>(
                    value: s['id'].toString(),
                    child: Text('${s['code']} · ${s['name']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: saving ? null : (value) =>
                      update(() => selected = value),
                ),
                const SizedBox(height: 12),
                TextField(controller: title, maxLength: 150,
                    decoration: const InputDecoration(labelText: 'Title')),
                TextField(controller: description, maxLength: 2000,
                    minLines: 2, maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Description (optional)')),
                CheckboxListTile(
                  value: verifiedOnly,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Verified students only'),
                  onChanged: saving ? null : (value) =>
                    update(() => verifiedOnly = value == true),
                ),
                if (fieldError != null)
                  Text(fieldError!, style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.error)),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
              FilledButton(
                onPressed: saving ? null : () async {
                  final t = title.text.trim(), d = description.text.trim();
                  if (t.length < 3 || (d.isNotEmpty && d.length < 3) || selected == null) {
                    update(() => fieldError = 'Choose a subject and enter a title (at least 3 characters).');
                    return;
                  }
                  update(() { saving = true; fieldError = null; });
                  try {
                    await widget.api.updateDraft(noteId, t, d, selected!,
                      verifiedOnly: verifiedOnly);
                    await widget.onChanged();
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                    if (mounted) {
                      setState(() => message =
                          'Draft details updated. Reopen to see the latest title.');
                    }
                  } catch (_) {
                    if (dialogContext.mounted) {
                      update(() {
                        fieldError = 'Unable to save changes. Please retry.';
                        saving = false;
                      });
                    }
                  }
                },
                child: Text(saving ? 'Saving…' : 'Save changes')),
            ],
          ),
        ),
      );
    } finally {
      title.dispose();
      description.dispose();
    }
  }

  Future<void> _delete() async {
    if (working || !isDraft) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete this draft?'),
        content: const Text(
          'The draft and associated files will be permanently deleted. '
          'This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep draft')),
          TextButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Delete draft')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { working = true; action = 'Deleting draft…'; message = null; });
    try {
      await widget.api.deleteDraft(noteId);
      await widget.onChanged();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          message = 'Draft could not be deleted. Nothing was changed.';
          working = false;
          action = '';
        });
      }
    }
  }

  Widget _panel(Widget child) => ContributorGlass(
    padding: const EdgeInsets.all(13), child: child,
  );

  Widget _progress() => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(11)),
    child: Row(children: [
      for (final entry in [(1, 'Details'), (2, 'Prepare PDF'), (3, 'Review')])
        Expanded(child: InkWell(
          key: Key('draft-step-${entry.$1}'),
          onTap: entry.$1 == 1 ? _edit :
              entry.$1 == 2 || pagesReady
                ? () => setState(() => activeStep = entry.$1) : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: activeStep == entry.$1
                ? Theme.of(context).colorScheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(8)),
            child: Text(
              entry.$1 == 1 || (entry.$1 == 2 && pagesReady)
                ? '✓ ${entry.$2}' : '${entry.$1}. ${entry.$2}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10,
                color: activeStep == entry.$1
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: activeStep == entry.$1
                  ? FontWeight.w800 : FontWeight.w500)),
          ),
        )),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workspace', style: TextStyle(fontSize: 14)),
        actions: [
          Chip(label: Text('Step $activeStep of 3',
            style: const TextStyle(fontSize: 10))),
          IconButton(
            tooltip: 'Refresh PDF status',
            onPressed: working || loading ? null : _loadStatus,
            icon: const Icon(Icons.refresh_rounded, size: 18)),
        ],
      ),
      body: ListView(
        key: const Key('contributor-three-step-workflow'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 95),
        children: [
          _progress(),
          const SizedBox(height: 17),
          Text('Draft · ${widget.note['title'] ?? 'Untitled'}',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11, fontWeight: FontWeight.w700),
            maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          if (!isDraft)
            _panel(const ListTile(
              leading: Icon(Icons.verified_rounded),
              title: Text('Published'),
              subtitle: Text('This note is already live on SMIUNotes.')))
          else if (activeStep == 2) ...[
            const Text('Prepare PDF pages', style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (loading || working) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 7),
              Text(action.isNotEmpty ? action : 'Checking private PDF status…'),
            ],
            if (message != null) ...[
              const SizedBox(height: 9),
              _panel(Text(message!)),
            ],
            if (pdfExists == true) ...[
              _panel(Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.check_circle, color: Color(0xFF4CCFAA), size: 18),
                    SizedBox(width: 6),
                    Text('PDF uploaded', style: TextStyle(
                      color: Color(0xFF4CCFAA), fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 7),
                  Text(uploadedFilename == null
                    ? 'Your original PDF stays private. Readers see only protected pages.'
                    : 'Uploaded: $uploadedFilename',
                    style: TextStyle(fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  if (!pagesReady) Align(alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: working || loading ? null : _removePdf,
                      child: const Text('Replace PDF'))),
                ])),
              const SizedBox(height: 11),
              _panel(Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('NEXT STEP · REQUIRED',
                    style: TextStyle(fontSize: 10,
                      color: Color(0xFF9FC6DE), fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(pagesReady ? 'Watermarked pages ready' :
                    'Prepare your PDF for viewing', style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 7),
                  const Text('Convert your uploaded PDF into protected WebP pages. '
                    'Page verification must finish before administrator review.',
                    style: TextStyle(fontSize: 12,
                      color: Color(0xFFA6BACD))),
                  const SizedBox(height: 12),
                  const Text('1. Generate protected pages\n'
                    '2. Preview and verify every converted page\n'
                    '3. Administrator approves and publishes',
                    style: TextStyle(fontSize: 11, height: 1.7)),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity,
                    child: FilledButton(
                      onPressed: working || loading ? null : _convert,
                      child: Text(pagesReady ? 'View prepared PDF pages' :
                        'Prepare pages for review →'))),
                ])),
              const SizedBox(height: 10),
              if (pagesReady) FilledButton(
                key: const Key('contributor-next-review'),
                onPressed: () => setState(() => activeStep = 3),
                child: const Text('Next: Review pages')),
            ] else ...[
              _panel(const ListTile(
                leading: Icon(Icons.picture_as_pdf_outlined),
                title: Text('Upload your original PDF'),
                subtitle: Text('Choose a PDF up to 20 MiB. '
                  'The private upload is verified before continuing.'))),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('contributor-upload-pdf'),
                onPressed: pdfExists == false && !loading && !working
                  ? _upload : null,
                icon: const Icon(Icons.upload_file),
                label: const Text('Choose and upload PDF')),
            ],
          ] else if (activeStep == 3) ...[
            const Text('Review & submit for publishing',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            _panel(Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(pagesReady ? Icons.check_circle_outline
                      : Icons.pending_actions_outlined,
                    color: pagesReady ? const Color(0xFF4CCFAA) : Colors.amber,
                    size: 20),
                  const SizedBox(width: 7),
                  Expanded(child: Text(pagesReady
                    ? 'Watermarked pages prepared'
                    : 'Page preparation incomplete',
                    style: const TextStyle(fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 8),
                const Text('Preview every converted page to confirm readability '
                  'before the administrator publishes this contribution.',
                  style: TextStyle(fontSize: 12)),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: pagesReady && !working ? _convert : null,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Review prepared pages')),
              ])),
            const SizedBox(height: 12),
            _panel(CheckboxListTile(
              key: const Key('contributor-review-confirmation'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: reviewedPages,
              onChanged: pagesReady ? (value) => setState(() {
                reviewedPages = value == true;
                finishedReview = false;
              }) : null,
              title: const Text('I reviewed the converted pages'),
              subtitle: const Text('Publishing remains administrator-controlled.',
                style: TextStyle(fontSize: 11)),
            )),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              key: const Key('contributor-finish-review'),
              onPressed: pagesReady && reviewedPages
                ? () => setState(() => finishedReview = true) : null,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(finishedReview ? 'Review completed' :
                'Finish contributor review'),
            )),
            const SizedBox(height: 9),
            if (pagesReady && finishedReview)
              _panel(const ListTile(
                leading: Icon(Icons.verified_outlined,
                  color: Color(0xFF4CCFAA)),
                title: Text('Ready for administrator review'),
                subtitle: Text('The draft and prepared pages are ready for the website administrator. '
                  'This review confirmation is local to the app; it does not '
                  'publish or submit a new server status.')))
            else
              const Text('Finish PDF preparation and review each page.',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() => activeStep = 2),
              child: const Text('Back to PDF preparation')),
          ],
          if (isDraft) ...[
            const SizedBox(height: 18),
            const Divider(),
            OutlinedButton.icon(
              onPressed: working ? null : _edit,
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('Edit draft details')),
            const SizedBox(height: 7),
            TextButton.icon(
              onPressed: working ? null : _delete,
              icon: const Icon(Icons.delete_outline, size: 17),
              label: const Text('Delete draft and PDF')),
          ],
        ],
      ),
    );
  }
}
