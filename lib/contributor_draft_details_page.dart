import 'package:material_ui/material_ui.dart';
import 'contributor_api.dart';
import 'contributor_pdf_uploader.dart';
import 'contributor_conversion_page.dart';

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
      if (mounted) setState(() {
        loading = false;
        message = 'Note identifier missing. Reopen this note.';
      });
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
      });
    } catch (_) {
      if (mounted) setState(() {
        pdfExists = null;
        message = 'Unable to check your original PDF. Check your connection and retry.';
      });
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
      if (mounted) setState(() =>
          message = 'Could not remove PDF. Reset converted pages first, or retry.');
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
                    decoration: const InputDecoration(labelText: 'Description')),
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
                  if (t.length < 3 || d.length < 3 || selected == null) {
                    update(() => fieldError = 'Choose a subject and enter a title and description (at least 3 characters).');
                    return;
                  }
                  update(() { saving = true; fieldError = null; });
                  try {
                    await widget.api.updateDraft(noteId, t, d, selected!);
                    await widget.onChanged();
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (mounted) setState(() =>
                        message = 'Draft details updated. Reopen to see the latest title.');
                  } catch (_) {
                    if (dialogContext.mounted) update(() {
                      fieldError = 'Unable to save changes. Please retry.';
                      saving = false;
                    });
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
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() {
        message = 'Draft could not be deleted. Nothing was changed.';
        working = false;
        action = '';
      });
    }
  }

  Widget _step(IconData icon, String title, String subtitle, bool completed) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(completed ? Icons.check_circle : icon,
            color: completed ? colors.primary : colors.onSurfaceVariant),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Note details'), actions: [
        if (isDraft)
          IconButton(
            tooltip: 'Refresh PDF status',
            onPressed: working || loading ? null : _loadStatus,
            icon: const Icon(Icons.refresh)),
      ]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Text(widget.note['title']?.toString() ?? 'Untitled draft',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(widget.note['description']?.toString() ?? '',
              style: TextStyle(color: colors.onSurfaceVariant)),
          const SizedBox(height: 12),
          Chip(
            avatar: Icon(isDraft ? Icons.edit_note : Icons.verified,
                color: colors.primary, size: 18),
            label: Text(isDraft ? 'Private draft' : 'Published note')),
          if (!isDraft) ...[
            const SizedBox(height: 12),
            _step(Icons.check_circle, 'Published',
                'This contribution is available on SMIUNotes.', true),
          ] else ...[
            const SizedBox(height: 16),
            Text('Your progress', style: Theme.of(context)
                .textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _step(Icons.edit_note, '1. Draft saved',
                'Your note details are safely saved.', true),
            _step(Icons.picture_as_pdf, '2. Original PDF',
                loading
                    ? 'Checking private storage…'
                    : pdfExists == true
                        ? 'Uploaded and verified'
                        : pdfExists == false
                            ? 'No PDF uploaded yet'
                            : 'Status unavailable — refresh to retry',
                pdfExists == true),
            _step(Icons.auto_fix_high, '3. Watermarked pages',
                pagesReady
                    ? 'Ready for administrator review'
                    : 'Prepare pages after the PDF is uploaded',
                pagesReady),
            if (loading || working) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
              if (action.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(action)),
            ],
            if (message != null) Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Card(
                color: colors.surfaceContainerHighest,
                child: Padding(padding: const EdgeInsets.all(14),
                  child: Text(message!)),
              ),
            ),
            const SizedBox(height: 18),
            Text('Original PDF', style: Theme.of(context)
              .textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (pdfExists == true) ...[
              Card(child: ListTile(
                leading: Icon(Icons.task_alt, color: colors.primary),
                title: const Text('PDF uploaded successfully'),
                subtitle: Text(uploadedFilename == null
                    ? 'Original PDF is stored privately in SMIUNotes.'
                    : 'File: $uploadedFilename'),
              )),
              const SizedBox(height: 8),
              if (!pagesReady)
                OutlinedButton.icon(
                  onPressed: working || loading ? null : _removePdf,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Remove PDF to upload another'),
                ),
              if (pagesReady)
                const Text('To replace the PDF, reset converted pages first.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: working || loading ? null : _convert,
                icon: Icon(pagesReady ? Icons.visibility : Icons.auto_fix_high),
                label: Text(pagesReady
                    ? 'View watermarked pages'
                    : 'Next: prepare watermarked pages'),
              ),
            ] else ...[
              Card(child: ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('No PDF uploaded yet'),
                subtitle: const Text('Choose a PDF of up to 20 MiB. '
                    'The upload will be verified before you continue.'),
              )),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: pdfExists == false && !loading && !working
                    ? _upload : null,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Choose and upload PDF'),
              ),
            ],
            const SizedBox(height: 20),
            const Divider(),
            Text('Draft settings', style: Theme.of(context)
                .textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: working ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit draft details'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: working ? null : _delete,
              icon: Icon(Icons.delete_outline, color: colors.error),
              label: Text('Delete draft', style: TextStyle(color: colors.error)),
            ),
            const SizedBox(height: 12),
            Text('Only an administrator can publish your finished draft.',
                style: TextStyle(color: colors.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
