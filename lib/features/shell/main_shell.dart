import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Coquille des 4 onglets principaux (Accueil, Historique, Ma carte, Profil).
class MainShell extends StatelessWidget {
  const MainShell({required this.navigationShell, super.key});
  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    (Symbols.home_rounded, 'Accueil'),
    (Symbols.history_rounded, 'Historique'),
    (Symbols.credit_card_rounded, 'Ma carte'),
    (Symbols.person_rounded, 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
        destinations: [
          for (final (icon, label) in _tabs)
            NavigationDestination(
              key: Key('tab-$label'),
              icon: Icon(icon),
              selectedIcon: Icon(icon, fill: 1),
              label: label,
            ),
        ],
      ),
    );
  }
}
