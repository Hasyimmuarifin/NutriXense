import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nutrixense/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService Session Persistence Tests', () {
    test('AuthService.init loads saved session from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'auth_is_logged_in': true,
        'auth_user_id': 'usr_test_123',
        'auth_user_name': 'Ahmad Hasyim',
        'auth_user_email': 'ahmad@nutrixense.com',
      });

      final auth = AuthService.instance;
      await auth.init();

      expect(auth.isLoggedIn, isTrue);
      expect(auth.currentUser, isNotNull);
      expect(auth.currentUser!.uid, 'usr_test_123');
      expect(auth.userName, 'Ahmad Hasyim');
      expect(auth.userEmail, 'ahmad@nutrixense.com');
    });

    test('AuthService.logout clears saved session', () async {
      SharedPreferences.setMockInitialValues({
        'auth_is_logged_in': true,
        'auth_user_id': 'usr_test_123',
        'auth_user_name': 'Ahmad Hasyim',
        'auth_user_email': 'ahmad@nutrixense.com',
      });

      final auth = AuthService.instance;
      await auth.init();
      expect(auth.isLoggedIn, isTrue);

      await auth.logout();
      expect(auth.isLoggedIn, isFalse);
      expect(auth.currentUser, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auth_is_logged_in'), isNull);
      expect(prefs.getString('auth_user_id'), isNull);
    });
  });
}
