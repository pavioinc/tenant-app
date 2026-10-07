import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'core/push_notifications.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'theme/pavio_theme.dart';

void main() {
  runApp(const PavioTenantApp());
}

class PavioTenantApp extends StatelessWidget {
  const PavioTenantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Pavio', theme: PavioTheme.light(), home: const _SessionGate());
  }
}

/// Checks for a stored session before deciding whether to land on login or home —
/// avoids flashing the login screen for a renter who's already signed in.
class _SessionGate extends StatelessWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context) {
    final auth = AuthRepository();
    return FutureBuilder(
      future: auth.currentSession(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final session = snapshot.data;
        if (session == null) return LoginScreen(authRepository: auth);
        // Re-registers on every cold start with an existing session (not just right
        // after login/signup) — the app's FCM token can rotate independently of the
        // Pavio session, so this is how a rotated token gets picked back up.
        unawaited(PushNotifications().register(session.accessToken));
        return HomeScreen(authRepository: auth);
      },
    );
  }
}
