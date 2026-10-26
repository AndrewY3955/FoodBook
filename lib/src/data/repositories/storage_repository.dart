import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/failure.dart';
import '../models/models.dart';

/// Lowercase v4 UUID; the storage path check only accepts lowercase hex.
String _uuidV4() {
  final Random random = Random.secure();
  final List<int> b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final String hex =
      b.map((int v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Recipe cover images.
///
/// The bucket is private. Reads go through a signed URL with a short
/// life, which means a link pasted into a group chat stops working
/// rather than becoming a permanent public handle on the object.
class StorageRepository {
  StorageRepository(this._client);

  final SupabaseClient _client;

  StorageFileApi get _bucket => _client.storage.from(Env.coverBucket);

  /// The object key the storage policies parse. Changing the shape here
  /// without changing public.is_valid_cover_path breaks every upload.
  static String coverPath({
    required String libraryId,
    required String recipeId,
  }) =>
      '$libraryId/$recipeId/cover.jpg';

  /// Re-encodes before upload. Three reasons, in order of importance:
  /// it strips EXIF, which on a phone photo carries GPS coordinates of
  /// the user's library; it guarantees the bytes really are an image
  /// rather than a renamed file; and it cuts a 4 MB photo to ~200 KB.
  Uint8List _encode(Uint8List bytes) {
    if (bytes.lengthInBytes > 20 * 1024 * 1024) {
      throw const Failure('That image is too large. Pick one under 20 MB.');
    }

    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const Failure('That file is not an image we can read.');
    }

    final img.Image resized = decoded.width >= decoded.height
        ? img.copyResize(decoded,
            width: decoded.width > Env.coverMaxEdge
                ? Env.coverMaxEdge
                : decoded.width)
        : img.copyResize(decoded,
            height: decoded.height > Env.coverMaxEdge
                ? Env.coverMaxEdge
                : decoded.height);

    // encodeJpg writes a fresh file from pixel data. No metadata from
    // the original survives this step.
    return img.encodeJpg(resized, quality: Env.coverJpegQuality);
  }

  Future<void> _put(String path, Uint8List jpeg) => _bucket.uploadBinary(
        path,
        jpeg,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
          cacheControl: '3600',
        ),
      );

  static String backgroundPath({
    required String libraryId,
    required String recipeId,
  }) =>
      '$libraryId/$recipeId/background.jpg';

  static String photoPath({
    required String libraryId,
    required String recipeId,
    required String photoId,
  }) =>
      '$libraryId/$recipeId/photo-$photoId.jpg';

  Future<String> uploadCover({
    required String libraryId,
    required String recipeId,
    required Uint8List bytes,
  }) async {
    final Uint8List jpeg = _encode(bytes);
    final String path = coverPath(
      libraryId: libraryId,
      recipeId: recipeId,
    );

    try {
      await _put(path, jpeg);

      await _client.from('recipes').update(
          <String, dynamic>{'cover_image_path': path}).eq('id', recipeId);

      return path;
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<String> uploadBackground({
    required String libraryId,
    required String recipeId,
    required Uint8List bytes,
  }) async {
    final Uint8List jpeg = _encode(bytes);
    final String path =
        backgroundPath(libraryId: libraryId, recipeId: recipeId);
    try {
      await _put(path, jpeg);
      await _client.from('recipes').update(
          <String, dynamic>{'background_image_path': path}).eq('id', recipeId);
      return path;
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> removeBackground({
    required String recipeId,
    required String path,
  }) async {
    try {
      await _bucket.remove(<String>[path]);
      await _client.from('recipes').update(
          <String, dynamic>{'background_image_path': null}).eq('id', recipeId);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> addPhoto({
    required String libraryId,
    required String recipeId,
    required Uint8List bytes,
    required int sortOrder,
    String? caption,
  }) async {
    final Uint8List jpeg = _encode(bytes);
    final String photoId = _uuidV4();
    final String path = photoPath(
      libraryId: libraryId,
      recipeId: recipeId,
      photoId: photoId,
    );
    try {
      await _put(path, jpeg);
      await _client.from('recipe_images').insert(<String, dynamic>{
        'recipe_id': recipeId,
        'library_id': libraryId,
        'storage_path': path,
        'caption': caption,
        'sort_order': sortOrder,
      });
    } catch (error) {
      throw Failure.from(error);
    }
  }

  Future<void> removePhoto(RecipeImage image) async {
    try {
      await _client.from('recipe_images').delete().eq('id', image.id);
      await _bucket.remove(<String>[image.storagePath]);
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// Copies the source recipe's cover, background and photos into the
  /// fork's own storage prefix so the fork never depends on the source's
  /// files. Returns how many images could not be copied; the fork itself
  /// is kept regardless.
  Future<int> copyImagesForFork({
    required String sourceRecipeId,
    required String newRecipeId,
    required String libraryId,
  }) async {
    int failed = 0;
    try {
      final Map<String, dynamic>? src = await _client
          .from('recipes')
          .select('cover_image_path, background_image_path')
          .eq('id', sourceRecipeId)
          .maybeSingle();
      if (src == null) return 0;

      Future<String?> copy(String? from, String to) async {
        if (from == null || from.isEmpty) return null;
        try {
          await _put(to, await _bucket.download(from));
          return to;
        } catch (_) {
          failed++;
          return null;
        }
      }

      final String? cover = await copy(src['cover_image_path'] as String?,
          coverPath(libraryId: libraryId, recipeId: newRecipeId));
      final String? background = await copy(
          src['background_image_path'] as String?,
          backgroundPath(libraryId: libraryId, recipeId: newRecipeId));
      final Map<String, dynamic> patch = <String, dynamic>{
        if (cover != null) 'cover_image_path': cover,
        if (background != null) 'background_image_path': background,
      };
      if (patch.isNotEmpty) {
        await _client.from('recipes').update(patch).eq('id', newRecipeId);
      }

      final List<Map<String, dynamic>> photos = await _client
          .from('recipe_images')
          .select('storage_path, caption, sort_order')
          .eq('recipe_id', sourceRecipeId)
          .order('sort_order');
      for (final Map<String, dynamic> p in photos) {
        final String? to = await copy(
            p['storage_path'] as String?,
            photoPath(
                libraryId: libraryId,
                recipeId: newRecipeId,
                photoId: _uuidV4()));
        if (to == null) continue;
        await _client.from('recipe_images').insert(<String, dynamic>{
          'recipe_id': newRecipeId,
          'library_id': libraryId,
          'storage_path': to,
          'caption': p['caption'],
          'sort_order': p['sort_order'],
        });
      }
    } catch (_) {
      failed++;
    }
    return failed;
  }

  /// Removes the user's files, then their account and everything it owns.
  /// Copies other people hold (forks, saved recipes) are untouched.
  Future<void> deleteAccount() async {
    try {
      final List<dynamic> paths = (await _client
              .rpc<dynamic>('account_storage_paths') as List<dynamic>?) ??
          <dynamic>[];
      final List<String> names = paths.cast<String>();
      for (int i = 0; i < names.length; i += 100) {
        await _bucket.remove(names.sublist(i, min(i + 100, names.length)));
      }
      await _client.rpc<dynamic>('delete_my_account');
      await _client.auth.signOut();
    } catch (error) {
      throw Failure.from(error);
    }
  }

  /// Short-lived read URL. One hour is long enough to render a screen
  /// and short enough that a leaked link is not a lasting exposure.
  Future<String?> signedCoverUrl(String? path, {int expiresIn = 3600}) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await _bucket.createSignedUrl(path, expiresIn);
    } catch (_) {
      // A missing object is not worth an error dialog; the card falls
      // back to its placeholder.
      return null;
    }
  }

  Future<void> removeCover({
    required String recipeId,
    required String path,
  }) async {
    try {
      await _bucket.remove(<String>[path]);
      await _client.from('recipes').update(
          <String, dynamic>{'cover_image_path': null}).eq('id', recipeId);
    } catch (error) {
      throw Failure.from(error);
    }
  }
}
