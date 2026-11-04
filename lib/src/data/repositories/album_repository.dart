import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failure.dart';
import '../../core/security/input_sanitizer.dart';
import '../models/models.dart';

class AlbumRepository {
  AlbumRepository(this._client);

  final SupabaseClient _client;

  Future<List<RecipeAlbum>> list(String libraryId) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('recipe_albums')
          .select('id, library_id, name')
          .eq('library_id', libraryId)
          .order('sort_order')
          .order('created_at');
      return rows.map(RecipeAlbum.fromJson).toList(growable: false);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  String _cleanName(String raw) {
    final String name = InputSanitizer.singleLine(raw, maxLength: 60);
    if (name.isEmpty) throw const Failure('Give the album a name.');
    return name;
  }

  Future<void> create(String libraryId, String name) async {
    final String clean = _cleanName(name);
    try {
      await _client
          .from('recipe_albums')
          .insert(<String, dynamic>{'library_id': libraryId, 'name': clean});
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> rename(String albumId, String name) async {
    final String clean = _cleanName(name);
    try {
      await _client
          .from('recipe_albums')
          .update(<String, dynamic>{'name': clean}).eq('id', albumId);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// Recipes in the album move to the cookbook's first remaining album.
  Future<void> delete(String albumId) async {
    try {
      await _client.rpc<void>(
        'delete_recipe_album',
        params: <String, dynamic>{'p_album_id': albumId},
      );
    } catch (error) {
      throw Failure.from(error);
    }
  }
}
