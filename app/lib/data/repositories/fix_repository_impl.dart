import 'package:drift/drift.dart' show Value, OrderingTerm;
import 'package:uuid/uuid.dart';
import 'package:highlight_creator/data/database/database.dart';
import 'package:highlight_creator/domain/entities/fix_record.dart';
import 'package:highlight_creator/domain/repositories/fix_repository.dart';

/// Drift-backed implementation of FixRepository.
/// Persists fix records to the SQLite database so they survive app restarts.
class FixRepositoryImpl implements FixRepository {
  final AppDatabase _db;
  final Uuid _uuid = const Uuid();

  FixRepositoryImpl(this._db);

  @override
  Future<FixRecord> create(FixRecord record) async {
    final id = record.id.isEmpty ? _uuid.v4() : record.id;
    final resolvedAt = record.resolvedAt;
    await _db.into(_db.fixes).insert(FixesCompanion(
      id: Value(id),
      description: Value(record.description),
      filesChanged: Value(record.filesChanged),
      resolvedAt: Value(resolvedAt),
    ));
    return record.copyWith(id: id, resolvedAt: resolvedAt);
  }

  @override
  Future<List<FixRecord>> listAll() async {
    final query = _db.select(_db.fixes)
      ..orderBy([(t) => OrderingTerm.desc(t.resolvedAt)]);
    final rows = await query.get();
    return rows
        .map((r) => FixRecord(
              id: r.id,
              description: r.description,
              filesChanged: r.filesChanged,
              resolvedAt: r.resolvedAt,
            ))
        .toList();
  }
}
