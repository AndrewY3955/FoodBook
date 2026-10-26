import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/failure.dart';
import '../../core/security/input_sanitizer.dart';
import '../models/models.dart';

/// Calls the import-recipe Edge Function.
///
/// The device never fetches the pasted URL itself. If it did, the app
/// would be a fetch-anything proxy running on the user's network, and
/// a pasted link to a router admin page would be requested from inside
/// their LAN. The Edge Function runs in an isolate with its own egress
/// and its own allowlist.
class ImportRepository {
  ImportRepository(this._client);

  final SupabaseClient _client;

  Future<ParsedImport> parse(String rawUrl) async {
    final String? url = InputSanitizer.importUrl(rawUrl);
    if (url == null) {
      throw const Failure(
        'Paste a full https link, for example https://www.instagram.com/reel/...',
      );
    }

    try {
      final FunctionResponse response = await _client.functions.invoke(
        'import-recipe',
        body: <String, dynamic>{'url': url},
      );

      if (response.status == 422) {
        throw const Failure(
          'That page did not contain a recipe we could read. '
          'You can still paste the text in by hand.',
        );
      }
      if (response.status == 429) {
        throw const Failure('Too many imports just now. Try again shortly.');
      }
      if (response.status != 200) {
        throw const Failure('The import service could not read that link.');
      }

      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const Failure(
            'The import service returned something unexpected.');
      }

      final ParsedImport parsed = ParsedImport.fromJson(data);
      if (parsed.isEmpty) {
        throw const Failure(
          'Nothing recipe-shaped was found at that link. '
          'You can still paste the text in by hand.',
        );
      }
      return parsed;
    } catch (error) {
      throw Failure.from(error);
    }
  }
}
