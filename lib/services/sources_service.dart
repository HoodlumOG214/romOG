import 'package:sqflite/sqflite.dart';

import '../models/source.dart';
import 'rom_database_service.dart';

/// Read-only access to the catalog DB's `sources` + `source_health` tables.
/// Builds [SourceInfo] joined across both, ordered by priority desc.
class SourcesService {
  SourcesService(this._db);

  final RomDatabaseService _db;

  Future<List<SourceInfo>> listSources() async {
    final db = await _db.database;
    return _buildFromDb(db);
  }

  Future<List<SourceInfo>> _buildFromDb(Database db) async {
    final rows = await db.rawQuery('''
      SELECT s.id, s.name, s.homepage, s.kind, s.auth_required, s.priority,
             h.status, h.last_checked, h.reason, h.entry_count, h.link_count
      FROM sources s
      LEFT JOIN source_health h ON h.source_id = s.id
      ORDER BY s.priority DESC, s.id ASC
    ''');
    return rows.map(_rowToInfo).toList();
  }

  static SourceInfo _rowToInfo(Map<String, Object?> row) {
    final lastChecked = row['last_checked'] as int?;
    return SourceInfo(
      id: row['id'] as String,
      name: row['name'] as String,
      homepage: row['homepage'] as String?,
      kind: row['kind'] as String,
      authRequired: (row['auth_required'] as int? ?? 0) != 0,
      priority: row['priority'] as int? ?? 0,
      status: SourceStatusParse.fromDb(row['status'] as String?),
      lastChecked: lastChecked == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastChecked * 1000, isUtc: true),
      statusReason: row['reason'] as String?,
      entryCount: row['entry_count'] as int?,
      linkCount: row['link_count'] as int?,
    );
  }
}
