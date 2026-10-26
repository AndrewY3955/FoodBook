import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/models.dart';
import 'providers.dart';

/// The libraries this user belongs to.
final FutureProvider<List<Library>> myLibrariesProvider =
    FutureProvider<List<Library>>((Ref ref) async {
  // Rebuilds on sign-in and sign-out. Without this dependency the list
  // would survive a sign-out and the next user would briefly see the
  // previous user's library names.
  ref.watch(sessionProvider);
  return ref.watch(libraryRepositoryProvider).myLibraries();
});

/// Which library the UI is currently pointed at.
///
/// Note what this is NOT: it is not an access control decision. Setting
/// it to another library's id does not grant anything — every query
/// still passes through RLS, and a non-member gets an empty result or a
/// 42501. It exists so the user can switch context.
class ActiveLibraryController extends Notifier<String?> {
  @override
  String? build() {
    final AsyncValue<List<Library>> libraries =
        ref.watch(myLibrariesProvider);

    return libraries.maybeWhen(
      data: (List<Library> list) {
        if (list.isEmpty) return null;
        final String? held = stateOrNull;
        // Keep the current selection if it is still one of theirs.
        if (held != null && list.any((Library k) => k.id == held)) {
          return held;
        }
        return list.first.id;
      },
      orElse: () => stateOrNull,
    );
  }

  @override
  String? get stateOrNull {
    try {
      return state;
    } catch (_) {
      // Reading state during the first build() throws; that is expected
      // on the initial pass and means "nothing selected yet".
      return null;
    }
  }

  void select(String libraryId) {
    state = libraryId;
  }

  Future<void> create(String name) async {
    final Library created =
        await ref.read(libraryRepositoryProvider).create(name);
    await _reloadLibraries();
    state = created.id;
  }

  /// Waits for the refreshed list so the new selection isn't discarded
  /// by build() while the list is still loading.
  Future<void> _reloadLibraries() async {
    final List<Library> _ = await ref.refresh(myLibrariesProvider.future);
  }

  Future<void> rename(String libraryId, String name) async {
    await ref.read(libraryRepositoryProvider).rename(libraryId, name);
    ref.invalidate(myLibrariesProvider);
  }

  Future<void> leave(String libraryId) async {
    await ref.read(libraryRepositoryProvider).leave(libraryId);
    if (state == libraryId) state = null;
    ref.invalidate(myLibrariesProvider);
  }

  Future<void> joinWithInvitation(String token) async {
    final String libraryId =
        await ref.read(libraryRepositoryProvider).acceptInvitation(token);
    ref.invalidate(libraryMembersProvider(libraryId));
    await _reloadLibraries();
    state = libraryId;
  }
}

final NotifierProvider<ActiveLibraryController, String?> activeLibraryProvider =
    NotifierProvider<ActiveLibraryController, String?>(
        ActiveLibraryController.new);

/// Sugar for the many providers that need the id and cannot proceed
/// without one.
final Provider<String?> activeLibraryIdProvider =
    Provider<String?>((Ref ref) => ref.watch(activeLibraryProvider));

final Provider<Library?> activeLibraryRecordProvider =
    Provider<Library?>((Ref ref) {
  final String? id = ref.watch(activeLibraryIdProvider);
  if (id == null) return null;
  return ref.watch(myLibrariesProvider).maybeWhen(
        data: (List<Library> list) {
          for (final Library k in list) {
            if (k.id == id) return k;
          }
          return null;
        },
        orElse: () => null,
      );
});

final FutureProviderFamily<List<Profile>, String> libraryMembersProvider =
    FutureProvider.family<List<Profile>, String>(
  (Ref ref, String libraryId) =>
      ref.watch(libraryRepositoryProvider).members(libraryId),
);
