import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failure.dart';
import '../../core/security/input_sanitizer.dart';
import '../models/enums.dart';
import '../models/models.dart';

class InvitationToken {
  const InvitationToken({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;
}

class LibraryRepository {
  LibraryRepository(this._client);

  final SupabaseClient _client;

  /// Libraries the signed-in user belongs to. RLS on library_members
  /// already restricts this to their own rows; the explicit user_id
  /// filter is there so the query uses the partial index rather than
  /// relying on the planner to push the policy predicate down.
  Future<List<Library>> myLibraries() async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null) return const <Library>[];

    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('library_members')
          .select('member_role, libraries(id, name)')
          .eq('user_id', userId)
          .isFilter('revoked_at', null);

      return rows
          .map(Library.fromMembershipJson)
          .where((Library k) => k.id.isNotEmpty)
          .toList(growable: false);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<List<Profile>> members(String libraryId) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('library_members')
          .select(
              'profiles!library_members_profile_fkey(id, display_name, avatar_path)')
          .eq('library_id', libraryId)
          .isFilter('revoked_at', null);

      return rows
          .map((Map<String, dynamic> row) {
            final Object? p = row['profiles'];
            return p is Map<String, dynamic> ? Profile.fromJson(p) : null;
          })
          .whereType<Profile>()
          .toList(growable: false);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// Creates a library and claims ownership of it. Two statements, in
  /// this order: the library row records created_by, which is what
  /// can_claim_library() checks before allowing the owner membership.
  Future<Library> create(String name) async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const Failure('Sign in first.', isAuth: true);
    }
    final String clean = InputSanitizer.singleLine(name, maxLength: 80);
    if (clean.isEmpty) {
      throw const Failure('Give the library a name.');
    }

    try {
      final Map<String, dynamic> library = await _client
          .from('libraries')
          .insert(<String, dynamic>{'name': clean, 'created_by': userId})
          .select('id, name')
          .single();

      await _client.from('library_members').insert(<String, dynamic>{
        'library_id': library['id'],
        'user_id': userId,
        'member_role': 'owner',
      });

      return Library(
        id: library['id'] as String,
        name: library['name'] as String,
        role: MemberRole.owner,
      );
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> rename(String libraryId, String name) async {
    final String clean = InputSanitizer.singleLine(name, maxLength: 80);
    if (clean.isEmpty) throw const Failure('Give the library a name.');
    try {
      await _client
          .from('libraries')
          .update(<String, dynamic>{'name': clean}).eq('id', libraryId);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// Creates a single-use invitation. The returned token is shown once;
  /// the database keeps only its hash.
  Future<InvitationToken> createInvitation(
    String libraryId, {
    MemberRole role = MemberRole.member,
    String? email,
    int ttlHours = 168,
  }) async {
    final String cleanEmail = (email ?? '').trim();
    try {
      final dynamic result = await _client.rpc(
        'create_library_invitation',
        params: <String, dynamic>{
          'p_library_id': libraryId,
          'p_role': role == MemberRole.admin ? 'admin' : 'member',
          'p_email': cleanEmail.isEmpty ? null : cleanEmail,
          'p_ttl_hours': ttlHours,
        },
      );
      final Map<String, dynamic> row =
          (result is List ? result.first : result) as Map<String, dynamic>;
      return InvitationToken(
        token: row['token'] as String,
        expiresAt: DateTime.parse(row['expires_at'] as String),
      );
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// Redeems an invitation token and returns the joined library's id.
  Future<String> acceptInvitation(String token) async {
    final String clean = token.trim();
    if (clean.isEmpty) throw const Failure('Enter an invitation code.');
    try {
      final dynamic id = await _client.rpc(
        'accept_library_invitation',
        params: <String, dynamic>{'p_token': clean},
      );
      return id as String;
    } catch (error) {
      final Failure failure = Failure.from(error);
      if (failure.isAuth) throw failure;
      throw const Failure(
        'That invitation code is not valid. It may have expired, been '
        'used already, or been issued to a different email address.',
      );
    }
  }

  Future<void> leave(String libraryId) async {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _client
          .from('library_members')
          .delete()
          .eq('library_id', libraryId)
          .eq('user_id', userId);
    } catch (error) {
      throw Failure.from(error);
    }
  }
}
