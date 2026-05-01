import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/internet_archive_auth_manager.dart';

final internetArchiveAuthProvider = Provider<IAAuthManager>((ref) {
  return IAAuthManager();
});

final iaLoggedInProvider = FutureProvider<bool>((ref) async {
  final auth = ref.watch(internetArchiveAuthProvider);
  await auth.migrateFromV1IfNeeded();
  // Background re-validate; ensureFresh is a no-op if recently checked.
  unawaited(auth.ensureFresh());
  return auth.isLoggedIn();
});

final iaUsernameProvider = FutureProvider<String?>((ref) async {
  final auth = ref.watch(internetArchiveAuthProvider);
  return auth.getUsername();
});

final iaSessionStatusProvider = FutureProvider<IAValidationStatus>((ref) async {
  final auth = ref.watch(internetArchiveAuthProvider);
  final session = await auth.currentSession();
  return session?.lastValidationStatus ?? IAValidationStatus.unverified;
});
