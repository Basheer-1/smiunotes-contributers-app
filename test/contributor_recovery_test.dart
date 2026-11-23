import 'package:flutter_test/flutter_test.dart';
import 'package:smiunotes_contributers_app/contributor_recovery_page.dart';

void main() {
  test('Website-equivalent account recovery accepts valid data', () {
    expect(validateContributorRecovery(
      'csc-26f-027',
      'example.student@example.com',
      'I no longer have access to my previous contact mailbox.',
    ), isNull);
  });

  test('Rejects invalid student ID, email, and short explanation', () {
    expect(validateContributorRecovery(
      '', 'example@student.com', 'A detailed account recovery explanation',
    ), contains('Student ID'));
    expect(validateContributorRecovery(
      'CSC-26F-027', 'invalid-email', 'A detailed account recovery explanation',
    ), contains('email'));
    expect(validateContributorRecovery(
      'CSC-26F-027', 'example@student.com', 'Too short',
    ), contains('10'));
  });

  test('Blocks control characters and overlong explanations', () {
    expect(validateContributorRecovery(
      'CSC-26F-027', 'example@student.com',
      'This has a prohibited control character.\nLine 2',
    ), isNotNull);
    expect(validateContributorRecovery(
      'CSC-26F-027', 'example@student.com', 'a' * 2001,
    ), isNotNull);
  });

  test('Student ID length matches website validation', () {
    expect(validateContributorRecovery(
      'A' * 33, 'example@student.com', 'A sufficiently detailed explanation',
    ), contains('Student ID'));
  });
}
