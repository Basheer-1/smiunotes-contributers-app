import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'contributor_avatar.dart';
import 'contributor_api.dart';
import 'contributor_challenge.dart';
import 'contributor_draft_details_page.dart';

void main() => runApp(const ContributorsApp());

const blue = Color(0xFF1F527E);
const labels = ['Workspace', 'New Draft'];
const icons = [Icons.folder_open_rounded, Icons.add_circle_outline_rounded];

class ContributorsApp extends StatefulWidget {
  const ContributorsApp({super.key});

  @override
  State<ContributorsApp> createState() => _ContributorsAppState();
}

class _ContributorsAppState extends State<ContributorsApp> {
  static const _vault = FlutterSecureStorage();
  static const _themeKey = 'smiunotes.theme.v1';
  bool darkMode = true;

  @override
  void initState() {
    super.initState();
    _restoreTheme();
  }

  Future<void> _restoreTheme() async {
    try {
      final saved = await _vault.read(key: _themeKey);
      if (mounted && (saved == 'dark' || saved == 'light')) {
        setState(() => darkMode = saved == 'dark');
      }
    } catch (_) {
      // Keep light theme usable if device storage is temporarily unavailable.
    }
  }

  void _toggleTheme() {
    setState(() => darkMode = !darkMode);
    _vault.write(key: _themeKey, value: darkMode ? 'dark' : 'light')
        .catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SMIUNotes Contributors',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF183C68)),
      scaffoldBackgroundColor: const Color(0xFFF0F5FA),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF87B9F8),
        brightness: Brightness.dark,
        surface: const Color(0xFF101B29),
      ).copyWith(
        primary: const Color(0xFF8EC5FF),
        onPrimary: const Color(0xFF09213C),
        primaryContainer: const Color(0xFF18395B),
        onPrimaryContainer: const Color(0xFFD9EAFD),
        secondary: const Color(0xFFACD7F7),
        surface: const Color(0xFF101B29),
        onSurface: const Color(0xFFEAF3FF),
        onSurfaceVariant: const Color(0xFFB7C9DE),
        outlineVariant: const Color(0xFF324862),
      ),
      scaffoldBackgroundColor: const Color(0xFF0D1723),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
    home: ContributorHome(
      darkMode: darkMode, onThemeToggle: _toggleTheme,
    ),
  );
}

class ContributorHome extends StatefulWidget {
  const ContributorHome({super.key, required this.darkMode,
      required this.onThemeToggle});
  final bool darkMode;
  final VoidCallback onThemeToggle;

  @override
  State<ContributorHome> createState() => _ContributorHomeState();
}

class _ContributorHomeState extends State<ContributorHome> {
  final api = ContributorApi();
  bool restoring = true, busy = false, authenticated = false;
  int selected = 0;
  String notesQuery = '';
  String notesStatus = 'all';
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
    try {
      final success = await api.restore();
      if (!mounted) return;
      setState(() { restoring = false; authenticated = success; });
      if (success) await _refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        restoring = false;
        authenticated = api.session != null;
        error = 'Saved session is temporarily unavailable. Retry to reconnect.';
      });
    }
  }

  Future<void> _signIn() async {
    if (busy) return;
    if (id.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter Student ID and password.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final proof = await requestContributorChallenge(context);
      if (proof == null || proof.isEmpty) return;
      await api.signIn(id.text, password.text, proof);
      final result = await api.workspace();
      if (!mounted) return;
      password.clear();
      setState(() { authenticated = true; workspace = result; selected = 0; });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = _safeError(e);
          if (api.session != null) {
            // Authentication succeeded. A temporary workspace outage must
            // not force another password login or consume a new device slot.
            authenticated = true;
            workspace = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _safeError(Object error) => contributorAuthError(error);

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
    if (!authenticated || index < 0 || index > 4) return;
    setState(() => selected = index);
    // Refresh from the shared website backend whenever a tab is visited.
    // This avoids requiring a full app restart after a new note is published.
    await _refresh();
  }

  Future<void> _signOut() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      await api.signOut();
      if (mounted) {
        setState(() {
          authenticated = false; workspace = null;
          inbox = null; avatarFuture = null; selected = 0;
        });
      }
    } catch (_) {
      // Keep the encrypted session and the workspace visible. Retrying a
      // failed remote sign-out must not strand a fifth-device slot.
      if (mounted) {
        setState(() => error =
            'Device sign-out could not be confirmed. Check your connection '
            'and retry. Your login has been kept on this device.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
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
        toolbarHeight: 53,
        titleSpacing: 12,
        title: Row(children: [
          const Text('SMIU', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const Text('Contributor', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          if (authenticated) Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFF192D40),
              borderRadius: BorderRadius.circular(12)),
            child: Text(((workspace?['upload_scope'] as Map?)?['role'] ?? 'Staff')
              .toString().toUpperCase(),
              style: const TextStyle(fontSize: 9, color: Color(0xFFA3CDE5))),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: widget.darkMode ? 'Switch to light theme' : 'Switch to dark theme',
            onPressed: widget.onThemeToggle,
            icon: Icon(widget.darkMode ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined, size: 19),
          ),
          if (authenticated) IconButton(
            key: const Key('contributor-header-notifications'),
            tooltip: 'Notifications', onPressed: () => _changeTab(4),
            icon: const Icon(Icons.notifications_none_rounded, size: 20)),
          if (authenticated) InkWell(
            key: const Key('contributor-header-avatar'),
            onTap: () => _changeTab(3),
            child: const Padding(padding: EdgeInsets.symmetric(horizontal: 10),
              child: CircleAvatar(radius: 15, backgroundColor: Color(0xFF386D89),
                child: Icon(Icons.person_outline, size: 17))),
          ),
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
        height: 65,
        backgroundColor: const Color(0xFF122234),
        selectedIndex: selected == 1 ? 1 : 0,
        onDestinationSelected: _changeTab,
        destinations: [
          for (var i = 0; i < labels.length; i++)
            NavigationDestination(icon: Icon(icons[i], size: 20), label: labels[i]),
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
          const Icon(Icons.verified_user_outlined, size: 56),
          const SizedBox(height: 20),
          const Text('Contributor sign in', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Approved contributors and administrators. Both open the same Contributor Workspace using their SMIUNotes Student ID and password.',
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
    child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
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
        Icon(icon, color: Theme.of(context).colorScheme.primary),
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
    final allNotes = _items('notes');
    final query = notesQuery.trim().toLowerCase();
    final notes = allNotes.where((note) {
      final status = note['status']?.toString() ?? 'draft';
      if (notesStatus != 'all' && notesStatus != status) return false;
      if (query.isEmpty) return true;
      final subject = _items('subjects').where(
        (s) => s['id'] == note['subject_id']).toList();
      final course = subject.isEmpty ? '' :
        "${subject.first['code'] ?? ''} ${subject.first['name'] ?? ''}";
      return '${note['title'] ?? ''} ${note['description'] ?? ''} $course'
        .toLowerCase().contains(query);
    }).toList();
    return _scroll([
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Staff workspace', style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w800)),
            Text(profile['student_name']?.toString() ?? 'Contributor',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11,
                color: Color(0xFF9DB3C9))),
          ])),
        FilledButton.icon(
          key: const Key('new-draft-shortcut'),
          onPressed: () => _changeTab(1),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('New draft')),
      ]),
      const SizedBox(height: 13),
      TextField(
        key: const Key('workspace-search'),
        onChanged: (value) => setState(() => notesQuery = value),
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 18),
          hintText: 'Search by note title or course...',
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        for (final entry in [
          ('all', 'All', counts['total'] ?? allNotes.length),
          ('draft', 'Drafts', counts['drafts'] ?? 0),
          ('published', 'Published', counts['published'] ?? 0),
        ])
          Expanded(child: Padding(padding: const EdgeInsets.only(right: 4),
            child: ChoiceChip(
              key: Key('workspace-filter-${entry.$1}'),
              label: Text('${entry.$2} (${entry.$3})',
                style: const TextStyle(fontSize: 10)),
              selected: notesStatus == entry.$1,
              onSelected: (_) => setState(() => notesStatus = entry.$1),
            ))),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        const Expanded(child: Text('Your notes',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
        Text('Showing ${notes.length} of ${allNotes.length}',
          style: const TextStyle(fontSize: 10, color: Color(0xFF9DB3C9))),
        IconButton(
          tooltip: 'Refresh workspace',
          onPressed: busy ? null : _refresh,
          icon: const Icon(Icons.refresh_rounded, size: 18)),
      ]),
      const SizedBox(height: 5),
      if (notes.isEmpty) Card(child: ListTile(
        title: Text(allNotes.isEmpty ? 'No contributions yet' : 'No matching notes'),
        subtitle: const Text('Create a draft or adjust your filters.')))
      else
        ...notes.map(_noteTile),
    ]);
  }

  Widget _notes() {
    final allNotes = _items('notes');
    final query = notesQuery.trim().toLowerCase();
    final notes = allNotes.where((note) {
      final status = (note['status'] ?? '').toString().toLowerCase();
      if (notesStatus != 'all' && status != notesStatus) {
        return false;
      }
      if (query.isEmpty) return true;
      return (note['title'] ?? '').toString().toLowerCase().contains(query) ||
          (note['description'] ?? '').toString().toLowerCase().contains(query);
    }).toList();
    return _scroll([
      _heading('Manage notes', 'Search and filter your own contributions'),
      TextField(
        onChanged: (value) => setState(() => notesQuery = value),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          labelText: 'Search notes',
          hintText: 'Title or description',
        ),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        for (final status in const ['all', 'draft', 'published'])
          ChoiceChip(
            label: Text(status == 'all' ? 'All' :
              status == 'draft' ? 'Drafts' : 'Published'),
            selected: notesStatus == status,
            onSelected: (_) => setState(() => notesStatus = status),
          ),
      ]),
      const SizedBox(height: 10),
      Text('${notes.length} of ${allNotes.length} notes'),
      const SizedBox(height: 10),
      if (notes.isEmpty)
        Card(child: ListTile(
          title: Text(allNotes.isEmpty
            ? 'No notes uploaded yet' : 'No matching notes'),
          subtitle: Text(allNotes.isEmpty
            ? 'Create a private draft from the Upload tab.'
            : 'Try a different search or status filter.'),
        )),
      ...notes.map(_noteTile),
    ]);
  }

  Widget _noteTile(Map<String, dynamic> note) {
    final status = note['status']?.toString() ?? 'draft';
    final subjectMatches = _items('subjects').where(
      (item) => item['id'] == note['subject_id']).toList();
    final subject = subjectMatches.isEmpty ? null : subjectMatches.first;
    return Card(
      margin: const EdgeInsets.only(bottom: 3),
      color: const Color(0xFF18293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF2B4055))),
      child: ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${subject?['code'] ?? 'Course'} · Sem ${subject?['semester'] ?? '-'}',
            style: const TextStyle(fontSize: 10, color: Color(0xFFA4CEE8))),
          const SizedBox(width: 7),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: status == 'published'
                ? const Color(0xFF173E36) : const Color(0xFF334154),
              borderRadius: BorderRadius.circular(8)),
            child: Text(status == 'published' ? 'Published' : 'Draft',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: status == 'published'
                  ? const Color(0xFF83DEBC) : const Color(0xFFC5D6E8)))),
        ]),
        const SizedBox(height: 4),
        Text(note['title']?.toString() ?? 'Untitled',
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
      ]),
      subtitle: Text(
        '${subject?['name'] ?? ''} · ${note['updated_at']?.toString().split('T').first ?? ''}',
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10)),
      trailing: const Icon(Icons.chevron_right, size: 17),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ContributorDraftDetailsPage(
            api: api,
            note: note,
            subjects: _items('subjects'),
            onChanged: () async {
              if (mounted) await _refresh();
            },
          ),
        ));
        if (mounted) await _refresh();
      },
    ));
  }

  Widget _upload() {
    final scope = workspace?['upload_scope'] as Map<String, dynamic>? ?? {};
    final subjects = _items('subjects');
    return _scroll([
      Row(children: [
        TextButton.icon(
          onPressed: () => _changeTab(0),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Workspace')),
        const Spacer(),
        const Chip(label: Text('Step 1 of 3', style: TextStyle(fontSize: 10))),
      ]),
      const SizedBox(height: 8),
      const _ContributorSteps(current: 1, ready: false),
      const SizedBox(height: 17),
      const Text('Create a draft', style: TextStyle(
        fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text('Add note details first, then upload your PDF. Drafts stay private until published.',
        style: TextStyle(color: Color(0xFFA9BDD0), fontSize: 12)),
      const SizedBox(height: 14),
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
            final draftId = await api.createDraft(title, description, subject);
            await _refresh();
            if (!mounted) return;
            final created = _items('notes').where((n) => n['id'] == draftId).toList();
            if (created.isNotEmpty) {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ContributorDraftDetailsPage(
                  api: api, note: created.first,
                  subjects: _items('subjects'), onChanged: _refresh)));
            }
            if (mounted) _changeTab(0);
          }),
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

class _ContributorSteps extends StatelessWidget {
  const _ContributorSteps({required this.current, required this.ready});
  final int current;
  final bool ready;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFF192A3C),
      borderRadius: BorderRadius.circular(11)),
    child: Row(children: [
      for (final step in [
        (1, '1. Details'), (2, '2. Prepare PDF'), (3, '3. Review'),
      ])
        Expanded(child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: current == step.$1 ? const Color(0xFF386B87) : Colors.transparent,
            borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Text(
            step.$1 < current || (ready && step.$1 <= 2)
              ? '✓ ${step.$2.substring(3)}' : step.$2,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10,
              color: current == step.$1 ? Colors.white : const Color(0xFFAABDD1),
              fontWeight: current == step.$1 ? FontWeight.w800 : FontWeight.w500)),
        )),
    ]),
  );
}

class _DraftComposer extends StatefulWidget {
  const _DraftComposer({required this.subjects, required this.onSave,
    required this.busy});
  final List<Map<String, dynamic>> subjects;
  final bool busy;
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
    title = TextEditingController();
    description = TextEditingController();
    subject = widget.subjects.isNotEmpty
        ? widget.subjects.first['id']?.toString() : null;
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: title, maxLength: 150,
          decoration: const InputDecoration(labelText: 'Title',
            hintText: 'e.g. ICT Notes (Lecture 7)')),
        const SizedBox(height: 10),
        const Text('Subject', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: subject,
          decoration: const InputDecoration(labelText: 'Subject'),
          items: widget.subjects.map((s) => DropdownMenuItem(
            value: s['id'] as String,
            child: Text('${s['code']} · ${s['name']}',
               maxLines: 1, overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) => setState(() => subject = v),
        ),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Who can open this note?', style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(height: 8),
            const Text('Access follows the website’s verified-student rules. '
              'Private drafts are visible only to their owner and authorized staff.',
              style: TextStyle(fontSize: 11, color: Color(0xFFA5BED1))),
          ]))),
        const SizedBox(height: 12),
        const Text('Description', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(controller: description, maxLength: 2000,
          minLines: 3, maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Topics covered, lecture dates, or exam tips...')),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('create-draft-and-continue'),
          onPressed: submitting || widget.busy ? null : submit,
          icon: const Icon(Icons.arrow_forward, size: 17),
          label: Text(submitting ? 'Creating draft...' : 'Create draft & continue to PDF')),
      ],
  );
}
