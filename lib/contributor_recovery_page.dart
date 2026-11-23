import 'package:material_ui/material_ui.dart';

import 'contributor_api.dart';
import 'contributor_challenge.dart';

/// Same validation and private administrator-review flow as smiunotes.com/recover.
/// This is not a password reset, and never establishes account ownership.
String? validateContributorRecovery(
    String studentId, String email, String details) {
  final normalizedId = studentId.trim().toUpperCase();
  final normalizedEmail = email.trim().toLowerCase();
  final explanation = details.trim();
  if (!RegExp(r'^[A-Z0-9][A-Z0-9-]{0,31}$').hasMatch(normalizedId)) {
    return 'Enter your Student ID in the correct format.';
  }
  if (normalizedEmail.length > 254 ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalizedEmail)) {
    return 'Enter a valid contact email address.';
  }
  if (explanation.length < 10 || explanation.length > 2000 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(explanation)) {
    return 'Explain the issue in 10–2,000 characters.';
  }
  return null;
}

class ContributorRecoveryPage extends StatefulWidget {
  const ContributorRecoveryPage({super.key, required this.api});
  final ContributorApi api;

  @override
  State<ContributorRecoveryPage> createState() =>
      _ContributorRecoveryPageState();
}

class _ContributorRecoveryPageState extends State<ContributorRecoveryPage> {
  final studentId = TextEditingController();
  final email = TextEditingController();
  final explanation = TextEditingController();
  bool submitting = false;
  String? error;
  String? confirmation;

  @override
  void dispose() {
    studentId.dispose();
    email.dispose();
    explanation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (submitting) return;
    final validation = validateContributorRecovery(
      studentId.text, email.text, explanation.text);
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      // The same production Turnstile widget used for native sign-in.
      final token = await requestContributorChallenge(context);
      if (!mounted || token == null || token.isEmpty) return;
      final response = await widget.api.requestAccountRecovery(
        studentId.text, email.text, explanation.text, token);
      if (!mounted) return;
      setState(() {
        confirmation = response;
        error = null;
      });
    } on ContributorApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.status == 403
            ? 'Security verification expired or failed. Please retry.'
            : e.status == 400
                ? 'Check your Student ID, email and explanation, then retry.'
                : e.status == 429
                    ? 'Too many requests. Please try again later.'
                    : 'Recovery request could not be submitted. Please retry later.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Could not connect to SMIUNotes. Check your internet and retry.');
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Account recovery')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text('Recover your student access',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
            'Lost your email, or someone claimed your Student ID? '
            'Request a private administrator review.',
            style: TextStyle(color: colors.onSurfaceVariant)),
          const SizedBox(height: 24),
          if (confirmation != null) ...[
            Card(child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.mark_email_read_outlined,
                    size: 36, color: colors.primary),
                  const SizedBox(height: 12),
                  const Text('Request submitted',
                    style: TextStyle(fontWeight: FontWeight.w800,
                        fontSize: 19)),
                  const SizedBox(height: 10),
                  Text(confirmation!),
                  const SizedBox(height: 12),
                  const Text('Your account has not been changed. '
                    'The team will review eligible requests privately.'),
                ],
              ),
            )),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to sign in')),
          ] else ...[
            TextField(
              controller: studentId,
              enabled: !submitting,
              maxLength: 32,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Student ID',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: email,
              enabled: !submitting,
              maxLength: 254,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Contact email',
                prefixIcon: Icon(Icons.alternate_email),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: explanation,
              enabled: !submitting,
              maxLength: 2000,
              minLines: 4,
              maxLines: 7,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: 'Explain the lost mailbox or disputed claim',
                hintText: 'Describe what happened and how we can reach you.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: colors.surfaceContainerLow,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.privacy_tip_outlined, size: 22),
                    SizedBox(width: 12),
                    Expanded(child: Text(
                      'Do not send passwords, OTPs or copies of identity '
                      'documents. Submitting this request does not verify '
                      'Student ID ownership or change the account.')),
                  ],
                ),
              ),
            ),
            if (error != null) Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(error!, style: TextStyle(color: colors.error)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: submitting ? null : _submit,
              icon: submitting
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_outlined),
              label: Text(submitting ? 'Submitting…' : 'Request review'),
            ),
          ],
        ],
      )),
    );
  }
}
