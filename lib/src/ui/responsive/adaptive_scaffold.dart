import 'package:flutter/material.dart';

import 'breakpoints.dart';

class AdaptiveDestination {
  const AdaptiveDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int badgeCount;
}

/// One navigation shell, three shapes.
///
///   phone    bottom navigation bar
///   tablet   left icon rail
///   desktop  left full sidebar, always expanded
///
/// The same destination list drives all three, so a new section is
/// added once rather than in three places that then drift.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.title,
    this.actions = const <Widget>[],
    this.floatingActionButton,
    this.leadingSidebar,
    super.key,
  });

  final List<AdaptiveDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final String? title;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  /// Rendered above the sidebar items on desktop and tablet — the
  /// library switcher lives here.
  final Widget? leadingSidebar;

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (BuildContext context, LayoutScope scope) {
        switch (scope.formFactor) {
          case FormFactor.phone:
            return _phone(context);
          case FormFactor.tablet:
            return _tablet(context);
          case FormFactor.desktop:
            return _desktop(context);
        }
      },
    );
  }

  Widget _badged(AdaptiveDestination d, IconData icon) {
    final Widget raw = Icon(icon);
    if (d.badgeCount <= 0) return raw;
    return Badge.count(count: d.badgeCount, child: raw);
  }

  Widget _phone(BuildContext context) {
    return Scaffold(
      appBar:
          title == null ? null : AppBar(title: Text(title!), actions: actions),
      body: SafeArea(child: body),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations
            .map((AdaptiveDestination d) => NavigationDestination(
                  icon: _badged(d, d.icon),
                  selectedIcon: _badged(d, d.selectedIcon),
                  label: d.label,
                ))
            .toList(growable: false),
      ),
    );
  }

  Widget _tablet(BuildContext context) {
    return Scaffold(
      appBar:
          title == null ? null : AppBar(title: Text(title!), actions: actions),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Row(
          children: <Widget>[
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              leading: leadingSidebar == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      child: leadingSidebar,
                    ),
              destinations: destinations
                  .map((AdaptiveDestination d) => NavigationRailDestination(
                        icon: _badged(d, d.icon),
                        selectedIcon: _badged(d, d.selectedIcon),
                        label: Text(d.label),
                      ))
                  .toList(growable: false),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _desktop(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 260,
              child: Material(
                color: theme.colorScheme.surfaceContainerLow,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (leadingSidebar != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: leadingSidebar,
                      ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: destinations.length,
                        itemBuilder: (BuildContext context, int index) {
                          final AdaptiveDestination d = destinations[index];
                          final bool selected = index == selectedIndex;
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            child: ListTile(
                              selected: selected,
                              selectedTileColor:
                                  theme.colorScheme.secondaryContainer,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: _badged(
                                d,
                                selected ? d.selectedIcon : d.icon,
                              ),
                              title: Text(d.label),
                              onTap: () => onDestinationSelected(index),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: Column(
                children: <Widget>[
                  if (title != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              title!,
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                          ...actions,
                        ],
                      ),
                    ),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centres and caps very wide content so lines stay readable.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    required this.child,
    this.maxWidth = Breakpoints.maxContentWidth,
    super.key,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}
