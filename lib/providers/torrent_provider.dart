import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/torrent_service.dart';
import 'settings_provider.dart';

final torrentServiceProvider = Provider<TorrentService>((ref) {
  final service = TorrentService();
  ref.onDispose(service.dispose);
  return service;
});

/// Boots the runtime once settings have loaded. Await before addTorrent.
final torrentRuntimeProvider = FutureProvider<TorrentService>((ref) async {
  final service = ref.watch(torrentServiceProvider);
  final settings = ref.watch(settingsProvider);
  await service.start(seedingEnabled: settings.seedingEnabled);
  return service;
});
