import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/torrent_service.dart';

final torrentServiceProvider = Provider<TorrentService>((ref) {
  final service = TorrentService();
  ref.onDispose(service.dispose);
  return service;
});

/// Boots the runtime. Await before addTorrent. Seeding is always off
/// — the runtime pauses each torrent on finish.
final torrentRuntimeProvider = FutureProvider<TorrentService>((ref) async {
  final service = ref.watch(torrentServiceProvider);
  await service.start(seedingEnabled: false);
  return service;
});
