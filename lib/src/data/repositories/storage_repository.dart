import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/failure.dart';

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
  Future<String> uploadCover({
    required String libraryId,
    required String recipeId,
    required Uint8List bytes,
  }) async {
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
    final Uint8List jpeg =
        img.encodeJpg(resized, quality: Env.coverJpegQuality);

    final String path = coverPath(
      libraryId: libraryId,
      recipeId: recipeId,
    );

    try {
      await _bucket.uploadBinary(
        path,
        jpeg,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
          cacheControl: '3600',
        ),
      );

      await _client.from('recipes').update(
          <String, dynamic>{'cover_image_path': path}).eq('id', recipeId);

      return path;
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
