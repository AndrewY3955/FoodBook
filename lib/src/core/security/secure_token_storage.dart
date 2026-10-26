import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Session persistence backed by the platform keystore.
///
/// supabase_flutter defaults to SharedPreferences, which on Android is
/// a world-readable-to-root XML file and on web is localStorage. The
/// refresh token in that file is a long-lived bearer credential: anyone
/// who reads it can mint access tokens until it is revoked. Moving it
/// into the keychain costs one class.
///
/// Web is the exception and is handled honestly below rather than
/// pretended away.
class SecureTokenStorage extends LocalStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  static const String _sessionKey = 'supabase.session.v1';

  @override
  Future<void> initialize() async {
    // Nothing to warm up. Kept so the contract is explicit rather than
    // inherited by accident.
  }

  @override
  Future<String?> accessToken() => _storage.read(key: _sessionKey);

  @override
  Future<bool> hasAccessToken() async {
    final String? value = await _storage.read(key: _sessionKey);
    return value != null && value.isNotEmpty;
  }

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _sessionKey, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _sessionKey);
}

/// Notes on the platform matrix, so nobody has to rediscover this:
///
/// iOS / macOS  Keychain. `first_unlock_this_device` keeps the item off
///              iCloud Keychain and out of device backups.
/// Android      EncryptedSharedPreferences with a Keystore-held master
///              key. Requires minSdk 23; below that the plugin silently
///              degrades, which is why minSdk is pinned in the Gradle
///              config rather than left at the Flutter default.
/// Windows      DPAPI, scoped to the user account.
/// Linux        libsecret. Requires libsecret-1-dev at build time and a
///              running secret service at run time; on a headless box
///              there is none and writes fail.
/// Web          There is no keystore in a browser. flutter_secure_storage
///              falls back to an encrypted localStorage entry whose key
///              also lives in the browser, which is obfuscation, not
///              protection. Treat the web build as a session that ends
///              with the tab: see `AppConfig.webAuthOptions` in app.dart,
///              which disables session persistence there entirely.
