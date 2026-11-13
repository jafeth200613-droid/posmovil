import 'package:flutter_test/flutter_test.dart';
import 'package:pos_inventory_app/password_reset_link.dart';

void main() {
  group('extractPasswordResetCode', () {
    test('extracts code from a Firebase Hosting app link', () {
      final link = Uri.parse(
        'https://posmovil-app.firebaseapp.com/__/auth/links'
        '?link=${Uri.encodeComponent('https://posmovil-app.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=abc123')}',
      );

      expect(extractPasswordResetCode(link), 'abc123');
    });

    test('accepts a direct Firebase action link on the Hosting path', () {
      final link = Uri.parse(
        'https://posmovil-app.firebaseapp.com/__/auth/links'
        '?mode=resetPassword&oobCode=direct-code',
      );

      expect(extractPasswordResetCode(link), 'direct-code');
    });

    test('ignores links for another host or another action', () {
      expect(
        extractPasswordResetCode(
          Uri.parse(
            'https://example.com/__/auth/links?mode=resetPassword&oobCode=abc',
          ),
        ),
        isNull,
      );
      expect(
        extractPasswordResetCode(
          Uri.parse(
            'https://posmovil-app.firebaseapp.com/__/auth/links'
            '?mode=verifyEmail&oobCode=abc',
          ),
        ),
        isNull,
      );
    });
  });
}
