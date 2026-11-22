import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'contributor_avatar.dart';
import 'contributor_api.dart';
import 'contributor_challenge.dart';
import 'contributor_pdf_uploader.dart';
import 'contributor_conversion_page.dart';

void main() => runApp(const ContributorsApp());

const blue = Color(0xFF1F527E);
const labels = ['Dashboard', 'Upload', 'Notes', 'Profile', 'Inbox'];
const icons = [
  Icons.dashboard_outlined, Icons.upload_file_outlined,
  Icons.folder_copy_outlined, Icons.person_outline,
  Icons.notifications_none,
];

class ContributorsApp extends StatelessWidget {
  const ContributorsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SMIUNotes Contributors',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: blue),
      scaffoldBackgroundColor: const Color(0xFFF0F5FA),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: const ContributorHome(),
  );
}

class ContributorHome extends StatefulWidget {
  const ContributorHome({super.key});
  @override
  State<ContributorHome> createState() => _ContributorHomeState();
}

class _ContributorHomeState extends State<ContributorHome> {
  final api = ContributorApi();
  bool restoring = true, busy = false, authenticated = false;
  int selected = 0;
  String? error;
  Map<String, dynamic>? workspace;
  Map<String, dynamic>? inbox;
  Future<Uint8List?>? avatarFuture;
  final id = TextEditingController(), password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    id.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final success = await api.restore();
    if (!mounted) return;
    setState(() { restoring = false; authenticated = success; });
    if (success) await _refresh();
  }

  Future<void> _signIn() async {
    if (busy) return;
    if (id.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter Student ID and password.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      if (!await api.isLoginEnabled()) {
        throw StateError('Mobile login is currently disabled on the website.');
      }
      if (!mounted) return;
      final proof = await requestContributorChallenge(context);
      if (proof == null || proof.isEmpty) return;
      await api.signIn(id.text, password.text, proof);
      final result = await api.workspace();
      if (!mounted) return;
      password.clear();
      setState(() { authenticated = true; workspace = result; selected = 0; });
    } catch (e) {
      if (mounted) { setState(() => error = _safeError(e)); }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _safeError(Object error) {
    final message = error.toString().replaceFirst(RegExp(r'^(HttpException|Bad state): ?'), '');
    if (message.contains('Contributor API is not deployed')) {
      return 'Sign-in was accepted, but the Contributors backend is not deployed yet. Please update the app after the server fix.';
    }
    if (message.contains('Approved contributor access required') ||
        message.contains('Contributor access required')) {
      return 'Contributor workspace access requires an approved contributor or site administrator account.';
    }
    if (message.contains('Mobile login is currently disabled')) {
      return 'Mobile sign-in is not enabled on the server.';
    }
    if (message.contains('Invalid credentials') ||
        message.contains('Security verification required')) {
      return 'Sign-in failed. Check your credentials or security challenge.';
    }
    return 'Unable to connect to the Contributors service. Please retry or check availability.';
  }

  Future<void> _refresh() async {
    if (!authenticated || busy) return;
    setState(() { busy = true; error = null; });
    try {
      final result = await api.workspace();
      Map<String, dynamic>? messages;
      if (selected == 4) messages = await api.notifications();
      if (mounted) setState(() { workspace = result; if (messages != null) inbox = messages; });
    } catch (e) {
      if (mounted) setState(() => error = _safeError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _changeTab(int index) async {
    setState(() => selected = index);
    if (index == 4) {
      try {
        final result = await api.notifications();
        if (mounted) setState(() => inbox = result);
      } catch (e) {
        if (mounted) setState(() => error = _safeError(e));
      }
    }
  }

  Future<void> _signOut() async {
    setState(() { busy = true; error = null; });
    try {
      await api.signOut();
    } catch (_) {
      // Local credentials have been cleared even if remote revoke fails.
    } finally {
      if (mounted) {
        setState(() {
          busy = false; authenticated = false; workspace = null;
          inbox = null; avatarFuture = null; selected = 0;
        });
      }
    }
  }

  List<Map<String, dynamic>> _items(String key) {
    final value = workspace?[key];
    return value is List
        ? value.whereType<Map<String, dynamic>>().toList()
        : [];
  }

  @override
  Widget build(BuildContext context) {
    if (restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.auto_stories_rounded, color: blue),
          SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SMIUNotes', style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800)),
              Text('Contributors', style: TextStyle(fontSize: 11)),
            ],
          )),
        ]),
        actions: [
          if (authenticated)
            IconButton(tooltip: 'Refresh', onPressed: busy ? null : _refresh,
                icon: const Icon(Icons.refresh)),
          if (authenticated)
            IconButton(tooltip: 'Sign out', onPressed: busy ? null : _signOut,
                icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          MaterialBanner(
            content: Text(error!),
            actions: [TextButton(onPressed: () => setState(() => error = null),
                child: const Text('Dismiss'))],
          ),
        Expanded(child: authenticated ? _workspaceBody() : _loginBody()),
      ]),
      bottomNavigationBar: authenticated ? NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: _changeTab,
        destinations: [
          for (var i = 0; i < labels.length; i++)
            NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
        ],
      ) : null,
    );
  }

  Widget _loginBody() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: ListView(shrinkWrap: true,
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.verified_user_outlined, color: blue, size: 56),
          const SizedBox(height: 20),
          const Text('Contributor sign in', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Approved contributors only. Use your existing SMIUNotes Student ID and password.',
            textAlign: TextAlign.center),
          const SizedBox(height: 25),
          TextField(controller: id, textCapitalization: TextCapitalization.characters,
            maxLength: 32, decoration: const InputDecoration(
              labelText: 'Student ID', prefixIcon: Icon(Icons.badge_outlined))),
          const SizedBox(height: 12),
          TextField(controller: password, obscureText: true,
            onSubmitted: (_) => _signIn(),
            decoration: const InputDecoration(
              labelText: 'Password', prefixIcon: Icon(Icons.lock_outline))),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: busy ? null : _signIn,
            icon: const Icon(Icons.login), label: const Text('Sign in')),
          const SizedBox(height: 12),
          const Text('Registration and password recovery remain on smiunotes.com.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );

  Widget _workspaceBody() {
    if (workspace == null) {
      return Center(child: OutlinedButton.icon(onPressed: _refresh,
        icon: const Icon(Icons.refresh), label: const Text('Load workspace')));
    }
    switch (selected) {
      case 0: return _dashboard();
      case 1: return _upload();
      case 2: return _notes();
      case 3: return _profile();
      default: return _notifications();
    }
  }

  Widget _scroll(List<Widget> children) => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: children),
  );

  Widget _heading(String title, String detail) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(
        fontSize: 25, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text(detail, style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]),
  );

  Widget _stat(String label, Object value, IconData icon) => Card(
    child: Padding(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: blue),
        const SizedBox(height: 13),
        Text('$value', style: const TextStyle(
          fontSize: 28, fontWeight: FontWeight.w800)),
        Text(label),
      ]),
    ),
  );

  Widget _dashboard() {
    final profile = workspace?['profile'] as Map<String, dynamic>? ?? {};
    final counts = workspace?['counts'] as Map<String, dynamic>? ?? {};
    final notes = _items('notes');
    return _scroll([
      _heading('Your dashboard', 'Welcome, ${profile['student_name'] ?? 'Contributor'}'),
      Row(children: [
        Expanded(child: _stat('Total notes', counts['total'] ?? 0, Icons.library_books_outlined)),
        Expanded(child: _stat('Drafts', counts['drafts'] ?? 0, Icons.edit_note_outlined)),
      ]),
      Row(children: [
        Expanded(child: _stat('Published', counts['published'] ?? 0, Icons.check_circle_outline)),
        Expanded(child: Card(child: ListTile(
          title: const Text('New draft'),
          subtitle: const Text('Start contributing'),
          onTap: () => _changeTab(1),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        ))),
      ]),
      const SizedBox(height: 14),
      const Text('Recent activity', style: TextStyle(fontSize: 19,
        fontWeight: FontWeight.w700)),
      ...notes.take(5).map(_noteTile),
      if (notes.isEmpty) const ListTile(title: Text('No contributions yet')),
    ]);
  }

  Widget _notes() {
    final notes = _items('notes');
    return _scroll([
      _heading('Manage notes', 'Your drafts and published contributions'),
      if (notes.isEmpty) const Card(child:
        ListTile(title: Text('No notes uploaded yet'))),
      ...notes.map(_noteTile),
    ]);
  }

  Widget _noteTile(Map<String, dynamic> note) {
    final status = note['status']?.toString() ?? 'draft';
    return Card(child: ListTile(
      leading: Icon(status == 'published'
          ? Icons.check_circle_outline : Icons.description_outlined,
          color: status == 'published' ? Colors.green : blue),
      title: Text(note['title']?.toString() ?? 'Untitled'),
      subtitle: Text('${status.toUpperCase()} · ${note['updated_at']?.toString().split('T').first ?? ''}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showModalBottomSheet<void>(
        context: context, showDragHandle: true,
        builder: (_) => Padding(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(note['title']?.toString() ?? 'Note',
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text('Status: $status'),
              const SizedBox(height: 8),
              Text(note['description']?.toString() ?? ''),
              const SizedBox(height: 20),
              if (status == 'draft')
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    try {
                      final noteId = note['id']?.toString() ?? '';
                      if (noteId.isEmpty) throw const FormatException('Missing note ID');
                      await ContributorPdfUploader(api).chooseAndUpload(noteId);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Original PDF uploaded and verified. Page conversion is still required before admin review.')));
                      await _refresh();
                    } catch (_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('PDF upload was not completed. Check the file or retry.')));
                      }
                    }
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Choose and upload PDF'),
                ),
              if (status == 'draft') ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => Padding(
                        padding: EdgeInsets.fromLTRB(12, 12, 12,
                          MediaQuery.of(context).viewInsets.bottom + 18),
                        child: SingleChildScrollView(
                          child: _DraftComposer(
                            subjects: _items('subjects'),
                            busy: false,
                            initialTitle: note['title']?.toString() ?? '',
                            initialDescription: note['description']?.toString() ?? '',
                            initialSubject: note['subject_id']?.toString(),
                            onSave: (title, description, subject) async {
                              await api.updateDraft(note['id'].toString(),
                                title, description, subject);
                              if (!mounted) return;
                              Navigator.of(context).pop();
                              await _refresh();
                            },
                          ),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit draft details'),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Delete private draft?'),
                        content: const Text('This will permanently remove your draft and associated media. Published notes cannot be deleted.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                            child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('Delete draft')),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    try {
                      await api.deleteDraft(note['id'].toString());
                      await _refresh();
                    } catch (_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Draft could not be deleted. No further action taken.')));
                      }
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete draft'),
                ),
              ],
              if (status == 'draft') ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ContributorConversionPage(
                          noteId: note['id'].toString(),
                          noteTitle: note['title']?.toString() ?? 'Draft',
                          api: api,
                        ),
                      ),
                    );
                    if (mounted) await _refresh();
                  },
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Prepare watermarked pages'),
                ),
              ],
              const SizedBox(height: 10),
              const Text('All uploaded PDFs must be converted into private, watermarked pages before admin review.'),
            ]),
        ),
      ),
    ));
  }

  Widget _upload() {
    final scope = workspace?['upload_scope'] as Map<String, dynamic>? ?? {};
    final subjects = _items('subjects');
    return _scroll([
      _heading('Upload notes', 'Create a private draft for your subject'),
      Card(child: Padding(padding: const EdgeInsets.all(14),
        child: Text('Assigned department: ${scope['department'] ?? '-'} · Semester ${scope['semester'] ?? '-'}'))),
      const SizedBox(height: 12),
      if (scope['eligible'] != true)
        const Card(child: ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('Upload permission not assigned'),
          subtitle: Text('Ask an administrator to verify your department and semester.'),
        ))
      else if (subjects.isEmpty)
        const Card(child: ListTile(title: Text('No subjects available in your semester')))
      else
        _DraftComposer(subjects: subjects, busy: busy,
          onSave: (title, description, subject) async {
            await api.createDraft(title, description, subject);
            await _refresh();
            if (mounted) _changeTab(2);
          }),
      const SizedBox(height: 18),
      const Text('After creating a draft, open it in Manage Notes to upload the original PDF. Watermarked page conversion remains a separate review step.'),
    ]);
  }

  Widget _profile() {
    final profile = workspace?['profile'] as Map<String, dynamic>? ?? {};
    final scope = workspace?['upload_scope'] as Map<String, dynamic>? ?? {};
    return _scroll([
      _heading('Contributor profile', 'Your verified SMIUNotes identity'),
      Center(child: FutureBuilder<Uint8List?>(
        future: avatarFuture ??= ContributorAvatar(api).load(),
        builder: (context, snapshot) {
          final picture = snapshot.data;
          return CircleAvatar(radius: 40,
            backgroundImage: picture != null && picture.isNotEmpty
              ? MemoryImage(picture) : null,
            child: picture == null || picture.isEmpty
              ? Text(
                  (profile['student_name']?.toString().isNotEmpty == true
                    ? profile['student_name'].toString()[0] : 'C').toUpperCase(),
                  style: const TextStyle(fontSize: 30))
              : null,
          );
        },
      )),
      const SizedBox(height: 16),
      for (final data in <(String, String)>[
        ('Name', profile['student_name']?.toString() ?? '-'),
        ('Student ID', profile['student_id']?.toString() ?? '-'),
        ('Department', profile['department']?.toString() ?? '-'),
        ('Semester', scope['semester']?.toString() ?? '-'),
        ('Role', scope['role'] == 'admin' ? 'Administrator' : 'Approved contributor'),
      ])
        Card(child: ListTile(title: Text(data.$1),
          subtitle: Text(data.$2))),
      const SizedBox(height: 12),
      const Text('Contribution history', style: TextStyle(
        fontSize: 19, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      ..._items('notes').take(10).map(_noteTile),
      if (_items('notes').isEmpty)
        const Card(child: ListTile(title: Text('No contributions yet'))),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: _signOut,
        icon: const Icon(Icons.logout), label: const Text('Sign out')),
    ]);
  }

  Widget _notifications() {
    final items = inbox?['items'];
    final notifications = items is List
        ? items.whereType<Map<String, dynamic>>().toList() : <Map<String, dynamic>>[];
    return _scroll([
      _heading('Notifications', 'Approval decisions and important account activity'),
      if (notifications.isNotEmpty)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: busy ? null : () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Clear notifications?'),
                  content: const Text('This clears your own inbox. The action cannot be undone.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel')),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Clear inbox')),
                  ],
                ),
              );
              if (confirmed != true) {
                return;
              }
              try {
                await api.clearNotifications();
                final refreshed = await api.notifications();
                if (mounted) {
                  setState(() => inbox = refreshed);
                }
              } catch (_) {
                if (mounted) {
                  setState(() => error =
                      'Could not clear notifications. Please retry.');
                }
              }
            },
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Clear inbox')),
        ),
      if (inbox == null)
        Center(child: FilledButton.icon(onPressed: () => _changeTab(4),
          icon: const Icon(Icons.refresh), label: const Text('Load inbox')))
      else if (notifications.isEmpty)
        const Card(child: ListTile(title: Text('No notifications yet')))
      else
        ...notifications.map((n) => Card(child: ListTile(
          title: Text(n['title']?.toString() ?? 'Notification'),
          subtitle: Text(n['message']?.toString() ?? ''),
          trailing: n['read_at'] == null
            ? TextButton(onPressed: () async {
                try {
                  await api.markRead(n['id'].toString());
                  await _changeTab(4);
                } catch (_) {
                  if (mounted) setState(() => error = 'Could not update notification.');
                }
              }, child: const Text('Read')) : const Icon(Icons.done),
        ))),
    ]);
  }
}

class _DraftComposer extends StatefulWidget {
  const _DraftComposer({required this.subjects, required this.onSave,
    required this.busy, this.initialTitle = '', this.initialDescription = '',
    this.initialSubject});
  final List<Map<String, dynamic>> subjects;
  final bool busy;
  final String initialTitle, initialDescription;
  final String? initialSubject;
  final Future<void> Function(String, String, String) onSave;
  @override
  State<_DraftComposer> createState() => _DraftComposerState();
}

class _DraftComposerState extends State<_DraftComposer> {
  late final TextEditingController title, description;
  String? subject, error;
  bool submitting = false;
  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.initialTitle);
    description = TextEditingController(text: widget.initialDescription);
    subject = widget.initialSubject;
  }
  @override
  void dispose() {
    title.dispose(); description.dispose(); super.dispose();
  }
  Future<void> submit() async {
    if (submitting) return;
    if (title.text.trim().length < 3 || description.text.trim().length < 3 ||
        subject == null) {
      setState(() => error = 'Enter title, description, and subject.');
      return;
    }
    setState(() { submitting = true; error = null; });
    try {
      await widget.onSave(title.text.trim(), description.text.trim(), subject!);
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to create draft. Please retry.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          initialValue: subject,
          decoration: const InputDecoration(labelText: 'Subject'),
          items: widget.subjects.map((s) => DropdownMenuItem(
            value: s['id'] as String,
            child: Text('${s['code']} · ${s['name']}', overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) => setState(() => subject = v),
        ),
        const SizedBox(height: 12),
        TextField(controller: title, maxLength: 150,
          decoration: const InputDecoration(labelText: 'Note title')),
        const SizedBox(height: 12),
        TextField(controller: description, maxLength: 2000,
          minLines: 3, maxLines: 5,
          decoration: const InputDecoration(labelText: 'Description')),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: submitting || widget.busy ? null : submit,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Create private draft')),
      ]),
    ),
  );
}
