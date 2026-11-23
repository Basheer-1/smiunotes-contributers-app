import 'package:flutter_test/flutter_test.dart';
import 'package:smiunotes_contributers_app/contributor_recovery_page.dart';

void main() {
  test('Password reset accepts the same Student ID format as website', () {
    expect(validateResetStudentId('csc-26f-027'), isNull);
    expect(validateResetStudentId(''), isNotNull);
    expect(validateResetStudentId('A' * 33), isNotNull);
    expect(validateResetStudentId('CSC_26F_027'), isNotNull);
  });

  test('Password reset requires website-matching password length', () {
    expect(validateResetPassword('a' * 12, 'a' * 12), isNull);
    expect(validateResetPassword('a' * 11, 'a' * 11), contains('12'));
    expect(validateResetPassword('a' * 129, 'a' * 129), contains('128'));
  });

  test('Password reset requires password confirmation', () {
    expect(validateResetPassword('a' * 12, 'b' * 12),
        'Passwords do not match.');
  });
}
