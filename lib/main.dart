import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'contributor_avatar.dart';
import 'contributor_api.dart';
import 'contributor_challenge.dart';
import 'contributor_draft_details_page.dart';
import 'contributor_glass.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermission();
    });
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await const MethodChannel('smiunotes/contributor_notifications')
          .invokeMethod<bool>('requestPermission');
    } on MissingPluginException {
      // Non-Android runtime: permission bridge unavailable.
    } on PlatformException {
      // Denying notifications must never block contributor sign-in.
    }
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
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF183C68),
        brightness: Brightness.light,
        surface: const Color(0xFFF8FBFF),
      ).copyWith(
        primary: const Color(0xFF234C76),
        onPrimary: Colors.white,
        surface: const Color(0xFFF8FBFF),
        onSurface: const Color(0xFF142D43),
        onSurfaceVariant: const Color(0xFF405B70),
        outlineVariant: const Color(0xFFA9BED0),
      ),
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xEFF8FBFF),
        foregroundColor: Color(0xFF142D43),
        surfaceTintColor: Colors.transparent),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFFF3F8FC),
        indicatorColor: const Color(0xFFCEE2F2),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(color: Color(0xFF243E58),
            fontSize: 12, fontWeight: FontWeight.w700)),
      ),
      cardTheme: CardThemeData(color: const Color(0xFFF8FBFF),
        elevation: 0, shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14))),
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
        primary: const Color(0xFF79B5D1),
        onPrimary: const Color(0xFF071B2A),
        primaryContainer: const Color(0xFF18395B),
        onPrimaryContainer: const Color(0xFFD9EAFD),
        secondary: const Color(0xFFACD7F7),
        surface: const Color(0xFF101B29),
        onSurface: const Color(0xFFEAF3FF),
        onSurfaceVariant: const Color(0xFFB7C9DE),
        outlineVariant: const Color(0xFF324862),
      ),
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xE60C1B29),
        surfaceTintColor: Colors.transparent),
      cardTheme: CardThemeData(color: const Color(0xD91A2B3D), elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: darkMode
          ? const [Color(0xFF091522), Color(0xFF122B3A), Color(0xFF091522)]
          : const [Color(0xFFF4FAFF), Color(0xFFE7F1FA), Color(0xFFF4FAFF)],
        stops: const [0, .55, 1],
      )),
      child: child ?? const SizedBox.shrink(),
    ),
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

class _ContributorHomeState extends State<ContributorHome> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    id.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && authenticated && !busy) {
      _refresh();
    }
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
      id.clear();
      setState(() { authenticated = true; workspace = result; avatarFuture = null; selected = 0; });
      try {
        final messages = await api.notifications();
        if (mounted) setState(() => inbox = messages);
      } catch (_) { /* Workspace is available even when inbox is offline. */ }
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
      try {
        messages = await api.notifications();
      } catch (_) { /* Preserve notes when inbox cannot be reached. */ }
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
        // The title owns only the space remaining after the action icons.
        // Avoid role chips in this narrow app bar: on smaller phones those
        // would overflow into the theme and notification controls.
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SMIUNotes',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text('Contributor workspace',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          if (authenticated && selected == 4)
            IconButton(key: const Key('return-to-workspace'),
              tooltip: 'Back to workspace',
              onPressed: () => _changeTab(0),
              icon: const Icon(Icons.arrow_back_rounded)),
          IconButton(
            tooltip: widget.darkMode ? 'Switch to light theme' : 'Switch to dark theme',
            onPressed: widget.onThemeToggle,
            icon: Icon(widget.darkMode ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined, size: 19),
          ),
          if (authenticated) IconButton(
            key: const Key('contributor-header-notifications'),
            tooltip: 'Notifications', onPressed: () => _changeTab(4),
            icon: (inbox?['unread'] is int && (inbox!['unread'] as int) > 0)
              ? Badge.count(count: (inbox!['unread'] as int).clamp(1, 99),
                  child: const Icon(Icons.notifications_none_rounded, size: 20))
              : const Icon(Icons.notifications_none_rounded, size: 20)),
          if (authenticated) InkWell(
            key: const Key('contributor-header-avatar'),
            onTap: _openProfile,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
              child: FutureBuilder<Uint8List?>(
                future: avatarFuture ??= ContributorAvatar(api).load(),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  final profile = workspace?['profile'] as Map<String, dynamic>? ?? {};
                  final name = profile['student_name']?.toString() ?? '';
                  return CircleAvatar(
                    radius: 15,
                    backgroundColor: const Color(0xFF386D89),
                    backgroundImage: bytes != null && bytes.isNotEmpty
                      ? MemoryImage(bytes) : null,
                    child: bytes != null && bytes.isNotEmpty ? null :
                      Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                        style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  );
                },
              )),
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
        backgroundColor: Theme.of(context).colorScheme.surface,
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
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 32),
        children: [
          const Center(child: CircleAvatar(
            radius: 30, backgroundColor: Color(0xFF244A66),
            child: Icon(Icons.folder_shared_outlined,
              color: Color(0xFFB9DEF2), size: 29))),
          const SizedBox(height: 18),
          const Text('Contributor workspace',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, height: 1.22,
              letterSpacing: -.35, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Sign in with your SMIUNotes Student ID. '
            'Approved contributors and administrators use the same secure workspace.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          ContributorGlass(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Student ID', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              TextField(
                key: const Key('contributor-student-id'),
                controller: id,
                textCapitalization: TextCapitalization.characters,
                maxLength: 32,
                decoration: const InputDecoration(
                  hintText: 'Enter your Student ID',
                  prefixIcon: Icon(Icons.badge_outlined, size: 20))),
              const SizedBox(height: 15),
              const Text('Password', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              TextField(
                key: const Key('contributor-password'),
                controller: password,
                obscureText: true,
                onSubmitted: (_) => _signIn(),
                decoration: const InputDecoration(
                  hintText: 'Your SMIUNotes password',
                  prefixIcon: Icon(Icons.lock_outline, size: 20))),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('contributor-login'),
                onPressed: busy ? null : _signIn,
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Sign in to Workspace')),
            ]),
          ),
          const SizedBox(height: 19),
          Text('Registration and password recovery remain on '
            'smiunotes.com. Two-factor security verification is required.',
            style: TextStyle(fontSize: 11, height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center),
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
    child: ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 88),
      children: children),
  );

  Widget _heading(String title, String detail) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(
        fontSize: 22, height: 1.18, letterSpacing: -.4,
         fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text(detail, style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]),
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
              style: TextStyle(fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
        FilledButton.icon(
          key: const Key('new-draft-shortcut'),
          onPressed: () => _changeTab(1),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('New draft')),
      ]),
      const SizedBox(height: 16),
      TextField(
        key: const Key('workspace-search'),
        onChanged: (value) => setState(() => notesQuery = value),
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 18),
          hintText: 'Search by note title or course...',
        ),
      ),
      const SizedBox(height: 14),
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
      const SizedBox(height: 22),
      Row(children: [
        const Expanded(child: Text('Your notes',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
        Text('Showing ${notes.length} of ${allNotes.length}',
          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
    return ContributorGlass(
      margin: const EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.zero,
      radius: 12,
      child: ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${subject?['code'] ?? 'Course'} · Sem ${subject?['semester'] ?? '-'}',
            style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(width: 7),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: status == 'published'
                ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF173E36) : const Color(0xFFD5F3E7))
                : Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8)),
            child: Text(status == 'published' ? 'Published' : 'Draft',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: status == 'published'
                  ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF83DEBC) : const Color(0xFF126244))
                  : Theme.of(context).colorScheme.onSurface))),
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
      Text('Add note details first, then upload your PDF. Drafts stay private until published.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
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
          onSave: (title, description, subject, verifiedOnly) async {
            final draftId = await api.createDraft(title, description, subject,
              verifiedOnly: verifiedOnly);
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

  Future<void> _openProfile() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF102032),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SizedBox(height: MediaQuery.sizeOf(sheetContext).height * .78,
          child: Column(children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                const Expanded(child: Text('Contributor profile',
                  style: TextStyle(fontWeight: FontWeight.w800))),
                IconButton(
                  key: const Key('close-contributor-profile'),
                  tooltip: 'Close profile',
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close)),
              ])),
            Expanded(child: _profile()),
          ])),
      ),
    );
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
        ContributorGlass(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(data.$1.toUpperCase(), style: TextStyle(
              fontSize: 10, letterSpacing: 1.05, fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 5),
            Text(data.$2, style: const TextStyle(
              fontSize: 14, height: 1.35, fontWeight: FontWeight.w600)),
          ])),
      const SizedBox(height: 20),
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
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(11)),
    child: Row(children: [
      for (final step in [
        (1, '1. Details'), (2, '2. Prepare PDF'), (3, '3. Review'),
      ])
        Expanded(child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: current == step.$1 ? Theme.of(context).colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Text(
            step.$1 < current || (ready && step.$1 <= 2)
              ? '✓ ${step.$2.substring(3)}' : step.$2,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10,
              color: current == step.$1 ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurfaceVariant,
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
  final Future<void> Function(String, String, String, bool) onSave;
  @override
  State<_DraftComposer> createState() => _DraftComposerState();
}

class _DraftComposerState extends State<_DraftComposer> {
  late final TextEditingController title, description;
  String? subject, error;
  bool submitting = false;
  bool verifiedOnly = false;
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
    if (title.text.trim().length < 3 ||
        (description.text.trim().isNotEmpty && description.text.trim().length < 3) ||
        subject == null) {
      setState(() => error = 'Select a subject and enter a title. Description is optional.');
      return;
    }
    setState(() { submitting = true; error = null; });
    try {
      await widget.onSave(title.text.trim(), description.text.trim(), subject!, verifiedOnly);
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
          decoration: const InputDecoration(hintText: 'Select a subject', isDense: true),
          items: widget.subjects.map((s) => DropdownMenuItem(
            value: s['id'] as String,
            child: Text('${s['code']} · ${s['name']}',
               maxLines: 1, overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) => setState(() => subject = v),
        ),
        const SizedBox(height: 12),
        ContributorGlass(padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Who can open this note?', style: TextStyle(
              fontWeight: FontWeight.w800, fontSize: 12)),
            CheckboxListTile(
              key: const Key('verified-students-checkbox'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: verifiedOnly,
              onChanged: submitting ? null : (value) =>
                setState(() => verifiedOnly = value == true),
              title: const Text('Verified students only',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              subtitle: const Text('Only Student Card-approved SMIU accounts '
                'can open the published pages. Private drafts stay restricted.',
                style: TextStyle(fontSize: 11)),
            ),
          ])),
        const SizedBox(height: 12),
        const Text('Description (optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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
