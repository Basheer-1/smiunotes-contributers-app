import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'contributor_api.dart';
import 'contributor_challenge.dart';

/// Same Student ID, linked-email OTP and new-password checks as SMIUNotes web.
String? validateResetStudentId(String input) {
  final id = input.trim().toUpperCase();
  if (!RegExp(r'^[A-Z0-9][A-Z0-9-]{0,31}$').hasMatch(id)) {
    return 'Enter a valid Student ID.';
  }
  return null;
}

String? validateResetPassword(String password, String confirmation) {
  if (password.length < 12 || password.length > 128) {
    return 'Use a password of 12–128 characters.';
  }
  if (password != confirmation) return 'Passwords do not match.';
  return null;
}

/// This screen does not ask for email or an explanation. OTP is delivered
/// only to the mailbox already associated with the Student ID on the server.
class ContributorRecoveryPage extends StatefulWidget {
  const ContributorRecoveryPage({super.key, required this.api});
  final ContributorApi api;

  @override
  State<ContributorRecoveryPage> createState() => _ContributorRecoveryPageState();
}

class _ContributorRecoveryPageState extends State<ContributorRecoveryPage> {
  final studentId = TextEditingController();
  final code = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  String? challenge;
  String? error;
  bool submitting = false;
  bool completed = false;

  @override
  void dispose() {
    studentId.dispose();
    code.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (submitting) return;
    final validation = validateResetStudentId(studentId.text);
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    setState(() { submitting = true; error = null; });
    try {
      final proof = await requestContributorChallenge(context);
      if (!mounted || proof == null || proof.isEmpty) return;
      final value = await widget.api.sendPasswordResetCode(studentId.text, proof);
      if (!mounted) return;
      setState(() { challenge = value; error = null; });
    } on ContributorApiException catch (e) {
      if (!mounted) return;
      setState(() => error = e.status == 403
        ? 'Security verification failed. Please try again.'
        : e.status == 429
          ? 'Too many requests. Please retry later.'
          : 'Could not send the code. Please retry later.');
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to connect. Check your internet.');
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _resetPassword() async {
    if (submitting || challenge == null) return;
    if (!RegExp(r'^\d{6}$').hasMatch(code.text.trim())) {
      setState(() => error = 'Enter the 6-digit verification code.');
      return;
    }
    final validation = validateResetPassword(
      newPassword.text, confirmPassword.text);
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    setState(() { submitting = true; error = null; });
    try {
      await widget.api.resetPasswordWithCode(
        challenge!, code.text.trim(), newPassword.text);
      if (!mounted) return;
      newPassword.clear();
      confirmPassword.clear();
      code.clear();
      setState(() { completed = true; challenge = null; });
    } on ContributorApiException catch (e) {
      if (!mounted) return;
      setState(() => error = e.status == 400 || e.status == 401
        ? 'Code is invalid or expired. Request a new code if needed.'
        : e.status == 409
          ? 'This reset created an active session. Sign out before retrying.'
          : 'Could not complete password reset. Try again later.');
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to complete password reset. Try again.');
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          Icon(completed ? Icons.verified_outlined
                : Icons.lock_reset_outlined,
            size: 48, color: colors.primary),
          const SizedBox(height: 16),
          Text(completed ? 'Password updated' : 'Reset your password',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(completed
            ? 'You can now sign in with your Student ID and new password.'
            : challenge == null
              ? 'Enter your existing Student ID. We will send a code only '
                'to your linked email so you can securely reset your password.'
              : 'Enter the verification code sent to your linked email, '
                'then choose your new password.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant)),
          const SizedBox(height: 28),
          if (completed) ...[
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.login),
              label: const Text('Back to sign in'),
            ),
          ] else if (challenge == null) ...[
            TextField(
              controller: studentId,
              enabled: !submitting,
              textCapitalization: TextCapitalization.characters,
              maxLength: 32,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _sendCode(),
              decoration: const InputDecoration(
                labelText: 'Student ID',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: submitting ? null : _sendCode,
              icon: const Icon(Icons.mail_outline),
              label: Text(submitting ? 'Sending…' : 'Send verification code'),
            ),
          ] else ...[
            TextField(
              controller: code,
              enabled: !submitting,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              autofillHints: const [AutofillHints.oneTimeCode],
              decoration: const InputDecoration(
                labelText: '6-digit verification code',
                prefixIcon: Icon(Icons.password),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: newPassword,
              enabled: !submitting,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'New password (12–128 characters)',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: confirmPassword,
              enabled: !submitting,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: submitting ? null : _resetPassword,
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(submitting ? 'Updating…' : 'Verify code and reset password'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: submitting ? null : () => setState(() {
                challenge = null;
                error = null;
                code.clear();
              }),
              child: const Text('Request a new code'),
            ),
          ],
          if (submitting) const Padding(
            padding: EdgeInsets.only(top: 14),
            child: LinearProgressIndicator(),
          ),
          if (error != null) Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
        ],
      )),
    );
  }
}
