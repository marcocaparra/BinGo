import 'package:bingo_app/pages/dashboard/home_tab.dart';
import 'package:bingo_app/pages/dashboard/missions_tab.dart';
import 'package:bingo_app/pages/dashboard/profile_tab.dart';
import 'package:bingo_app/pages/dashboard/ranking_tab.dart';
import 'package:bingo_app/pages/dashboard/rewards_tab.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const Color _activeColor = Color(0xFF3765FF);
  static const Color _inactiveColor = Color(0xFF8AA4C8);
  static const Color _pageBackgroundColor = Color(0xFFF4F4F4);

  int _selectedIndex = 2;

  static const List<String> _titles = [
    'Ranking',
    'Miss\u00f5es',
    'Dashboard',
    'Recompensas',
    'Perfil',
  ];

  static const List<Widget> _tabs = [
    RankingTab(),
    MissionsTab(),
    HomeTab(),
    RewardsTab(),
    ProfileTab(),
  ];

  static const List<_NavBarDestination> _destinations = [
    _NavBarDestination(
      icon: Icons.leaderboard_outlined,
      activeIcon: Icons.leaderboard,
      label: 'Ranking',
    ),
    _NavBarDestination(
      icon: Icons.flag_outlined,
      activeIcon: Icons.flag,
      label: 'Miss\u00f5es',
    ),
    _NavBarDestination(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Dashboard',
    ),
    _NavBarDestination(
      icon: Icons.card_giftcard_outlined,
      activeIcon: Icons.card_giftcard,
      label: 'Recompensas',
    ),
    _NavBarDestination(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Perfil',
    ),
  ];

  void _onTabSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackgroundColor,
      appBar: AppBar(title: Text(_titles[_selectedIndex])),
      body: _tabs[_selectedIndex],
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
        child: SizedBox(
          height: 110,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: CurvedNavigationBar(
                    index: _selectedIndex,
                    height: 70,
                    color: Colors.white,
                    buttonBackgroundColor: Colors.white,
                    backgroundColor: _pageBackgroundColor,
                    animationCurve: Curves.easeOutCubic,
                    animationDuration: const Duration(milliseconds: 350),
                    items: List.generate(_destinations.length, (index) {
                      final destination = _destinations[index];
                      final isSelected = _selectedIndex == index;

                      return _NavBarIcon(
                        icon: destination.icon,
                        activeIcon: destination.activeIcon,
                        isSelected: isSelected,
                      );
                    }),
                    onTap: _onTabSelected,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: IgnorePointer(
                    child: Row(
                      children: List.generate(_destinations.length, (index) {
                        final destination = _destinations[index];
                        final isSelected = _selectedIndex == index;

                        return Expanded(
                          child: _NavBarLabel(
                            label: destination.label,
                            isSelected: isSelected,
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarDestination {
  const _NavBarDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _NavBarIcon extends StatelessWidget {
  const _NavBarIcon({
    required this.icon,
    required this.activeIcon,
    required this.isSelected,
  });

  final IconData icon;
  final IconData activeIcon;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? _DashboardPageState._activeColor
        : _DashboardPageState._inactiveColor;

    return SizedBox(
      width: 54,
      height: 50,
      child: Center(
        child: Padding(
          padding: EdgeInsets.only(top: isSelected ? 0 : 6),
          child: Icon(
            isSelected ? activeIcon : icon,
            color: color,
            size: isSelected ? 30 : 25,
          ),
        ),
      ),
    );
  }
}

class _NavBarLabel extends StatelessWidget {
  const _NavBarLabel({required this.label, required this.isSelected});

  final String label;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? _DashboardPageState._activeColor
        : _DashboardPageState._inactiveColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
