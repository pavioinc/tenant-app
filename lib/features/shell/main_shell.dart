import 'package:flutter/material.dart';
import '../../theme/pavio_colors.dart';
import '../../theme/pavio_text_styles.dart';
import '../auth/auth_repository.dart';
import '../complaints/complaints_screen.dart';
import '../home/home_tab.dart';
import '../payments/payments_screen.dart';
import '../profile/me_tab.dart';

/// Persistent bottom-tab spine for a connected renter — design review option "1a" of the
/// `Pavio Mobile Wireframes` doc ("Bottom tab bar · familiar, 4 fixed tabs"), chosen over
/// the hub-grid Resident Hub it replaces. Four fixed destinations per the doc: Home · Pay
/// · Help · Me, labels always shown (never icon-only), with renewal folded under Me (via
/// the Lease row) rather than getting its own tab. HomeScreen still owns the
/// connected/unconnected gate and only ever builds this once a renter is connected.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.authRepository});

  final AuthRepository? authRepository;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late final AuthRepository _auth = widget.authRepository ?? AuthRepository();
  int _index = 0;

  void _goToPay() => setState(() => _index = 1);

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps every tab's state (scroll position, in-flight loads) alive
    // across switches instead of rebuilding the destination from scratch each tap.
    final tabs = [
      HomeTab(authRepository: _auth, onGoToPay: _goToPay),
      PaymentsScreen(authRepository: _auth),
      ComplaintsScreen(authRepository: _auth),
      MeTab(authRepository: _auth),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 64,
          backgroundColor: PavioColors.white,
          indicatorColor: PavioColors.primary50,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              size: 22,
              color: selected ? PavioColors.primary700 : PavioColors.ink500,
            );
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return PavioText.caption.copyWith(
              color: selected ? PavioColors.primary700 : PavioColors.ink500,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Pay',
            ),
            NavigationDestination(
              icon: Icon(Icons.build_outlined),
              selectedIcon: Icon(Icons.build),
              label: 'Help',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Me',
            ),
          ],
        ),
      ),
    );
  }
}
