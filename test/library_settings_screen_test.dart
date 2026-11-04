import 'package:cookistrybook/src/data/models/enums.dart';
import 'package:cookistrybook/src/data/models/models.dart';
import 'package:cookistrybook/src/state/library_controller.dart';
import 'package:cookistrybook/src/ui/screens/library_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cookistrybook/src/state/providers.dart';
import 'package:cookistrybook/src/data/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

class _FakeAuth implements AuthRepository {
  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget buildScreen(MemberRole role) => ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(_FakeAuth()),
          activeLibraryRecordProvider.overrideWith(
            (Ref ref) => Library(
              id: 'library-1',
              name: 'Family cookbook',
              role: role,
            ),
          ),
          libraryMembersProvider('library-1').overrideWith(
            (Ref ref) async => const <Profile>[
              Profile(id: 'user-1', displayName: 'Alex Cook'),
            ],
          ),
        ],
        child: const MaterialApp(home: LibrarySettingsScreen()),
      );

  testWidgets('shows library members and current role',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildScreen(MemberRole.owner));
    await tester.pumpAndSettle();

    expect(find.text('Family cookbook'), findsOneWidget);
    expect(find.text('Your role: Owner'), findsOneWidget);
    expect(find.text('Alex Cook'), findsOneWidget);
    expect(find.text('Invite someone'), findsOneWidget);
    expect(find.text('Rename library'), findsOneWidget);
  });

  testWidgets('does not offer rename to a regular member',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildScreen(MemberRole.member));
    await tester.pumpAndSettle();

    expect(find.text('Your role: Member'), findsOneWidget);
    expect(find.text('Rename library'), findsNothing);
    expect(find.text('Invite someone'), findsNothing);
  });
}
