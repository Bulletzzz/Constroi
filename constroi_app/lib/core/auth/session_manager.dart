import 'package:flutter/foundation.dart';

import 'session.dart';
import 'token_storage.dart';

class SessionManager extends ChangeNotifier {
  SessionManager(this._storage);

  final TokenStorage _storage;
  AppSession? _session;

  AppSession? get session => _session;
  String? get accessToken => _session?.accessToken;
  bool get isSignedIn => _session != null;

  Future<void> restore() async {
    final token = await _storage.read();
    _session = token == null || token.isEmpty
        ? null
        : AppSession(accessToken: token);
    notifyListeners();
  }

  Future<void> start(AppSession session) async {
    if (session.accessToken.trim().isEmpty) {
      throw ArgumentError.value(session.accessToken, 'accessToken');
    }
    await _storage.write(session.accessToken);
    _session = session;
    notifyListeners();
  }

  Future<void> signOut() async {
    await _storage.delete();
    _session = null;
    notifyListeners();
  }

  Future<void> expireIfCurrent(String token) async {
    if (_session?.accessToken == token) {
      await signOut();
    }
  }
}
