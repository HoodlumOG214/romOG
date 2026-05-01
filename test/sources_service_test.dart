import 'package:flutter_test/flutter_test.dart';
import 'package:romgi/models/source.dart';
import 'package:romgi/services/rom_database_service.dart';
import 'package:romgi/services/sources_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _InMemoryRomDb extends RomDatabaseService {
  _InMemoryRomDb(this._db);
  final Database _db;

  @override
  Future<Database> get database async => _db;
}

Future<Database> _seed() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE sources (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      homepage TEXT,
      kind TEXT NOT NULL,
      auth_required INTEGER NOT NULL DEFAULT 0,
      priority INTEGER NOT NULL DEFAULT 0,
      manifest_json TEXT NOT NULL DEFAULT '{}'
    )
  ''');
  await db.execute('''
    CREATE TABLE source_health (
      source_id TEXT PRIMARY KEY,
      status TEXT NOT NULL,
      last_checked INTEGER NOT NULL,
      reason TEXT,
      entry_count INTEGER,
      link_count INTEGER
    )
  ''');
  await db.insert('sources', {
    'id': 'minerva',
    'name': 'MiNERVA Archive',
    'homepage': 'https://minerva-archive.org',
    'kind': 'catalog',
    'auth_required': 0,
    'priority': 200,
    'manifest_json': '{}',
  });
  await db.insert('sources', {
    'id': 'internet_archive',
    'name': 'Internet Archive',
    'homepage': 'https://archive.org',
    'kind': 'catalog',
    'auth_required': 0,
    'priority': 50,
    'manifest_json': '{}',
  });
  await db.insert('sources', {
    'id': 'mariocube',
    'name': 'MarioCube',
    'homepage': 'https://archive.mariocube.com',
    'kind': 'catalog',
    'auth_required': 0,
    'priority': 70,
    'manifest_json': '{}',
  });
  await db.insert('source_health', {
    'source_id': 'minerva',
    'status': 'ok',
    'last_checked': 1700000000,
    'reason': null,
    'entry_count': 1234,
    'link_count': 5678,
  });
  await db.insert('source_health', {
    'source_id': 'internet_archive',
    'status': 'down',
    'last_checked': 1700000000,
    'reason': 'connection refused',
    'entry_count': 0,
    'link_count': 0,
  });
  // mariocube intentionally has no source_health row.
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SourcesService service;

  setUp(() async {
    db = await _seed();
    service = SourcesService(_InMemoryRomDb(db));
  });

  tearDown(() async {
    await db.close();
  });

  test('returns sources ordered by priority desc', () async {
    final sources = await service.listSources();
    expect(sources.map((s) => s.id), [
      'minerva', // 200
      'mariocube', // 70
      'internet_archive', // 50
    ]);
  });

  test('joins health rows when present', () async {
    final sources = await service.listSources();
    final minerva = sources.firstWhere((s) => s.id == 'minerva');
    expect(minerva.status, SourceStatus.ok);
    expect(minerva.entryCount, 1234);
    expect(minerva.linkCount, 5678);
    expect(minerva.lastChecked, isNotNull);
  });

  test('surfaces down status with the reason text', () async {
    final ia = (await service.listSources())
        .firstWhere((s) => s.id == 'internet_archive');
    expect(ia.status, SourceStatus.down);
    expect(ia.statusReason, 'connection refused');
  });

  test('treats absent health rows as unknown', () async {
    final mariocube = (await service.listSources())
        .firstWhere((s) => s.id == 'mariocube');
    expect(mariocube.status, SourceStatus.unknown);
    expect(mariocube.lastChecked, isNull);
    expect(mariocube.entryCount, isNull);
  });
}
