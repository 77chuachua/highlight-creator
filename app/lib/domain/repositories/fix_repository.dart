import 'package:highlight_creator/domain/entities/fix_record.dart';

/// Abstract repository for fix record operations.
abstract class FixRepository {
  /// Record a completed fix.
  Future<FixRecord> create(FixRecord record);

  /// List all recorded fixes, most recent first.
  Future<List<FixRecord>> listAll();
}
