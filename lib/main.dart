import 'package:flutter/material.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'theme/nivasa_theme.dart';

void main() {
  runApp(const NivasaOSTenantApp());
}

class NivasaOSTenantApp extends StatelessWidget {
  const NivasaOSTenantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'NivasaOS', theme: NivasaTheme.light(), home: const _SessionGate());
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
        return snapshot.data != null ? HomeScreen(authRepository: auth) : LoginScreen(authRepository: auth);
      },
    );
  }
}
