import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/models.dart';
import '../data/repositories/album_repository.dart';
import 'library_controller.dart';
import 'providers.dart';

final Provider<AlbumRepository> albumRepositoryProvider =
    Provider<AlbumRepository>(
        (Ref ref) => AlbumRepository(ref.watch(supabaseClientProvider)));

final FutureProvider<List<RecipeAlbum>> albumsProvider =
    FutureProvider<List<RecipeAlbum>>((Ref ref) async {
  final String? libraryId = ref.watch(activeLibraryIdProvider);
  if (libraryId == null) return const <RecipeAlbum>[];
  return ref.watch(albumRepositoryProvider).list(libraryId);
});
