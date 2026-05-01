import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/source.dart';
import '../services/sources_service.dart';
import 'api_provider.dart';

final sourcesServiceProvider = Provider<SourcesService>((ref) {
  return SourcesService(ref.watch(romDatabaseProvider));
});

final sourcesProvider = FutureProvider<List<SourceInfo>>((ref) async {
  final service = ref.watch(sourcesServiceProvider);
  return service.listSources();
});
