import 'package:uuid/uuid.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';
import 'package:highlight_creator/domain/repositories/timeslot_repository.dart';

/// In-memory implementation of TimeslotRepository.
/// Phase 2: drift-backed implementation will replace this once codegen runs.
class TimeslotRepositoryImpl implements TimeslotRepository {
  final Map<String, Timeslot> _timeslots = {};
  final Uuid _uuid = const Uuid();

  @override
  Future<Timeslot> create(Timeslot slot) async {
    final id = slot.id.isEmpty ? _uuid.v4() : slot.id;
    final s = slot.copyWith(id: id, createdAt: DateTime.now());
    _timeslots[id] = s;
    return s;
  }

  @override
  Future<Timeslot?> getById(String id) async {
    return _timeslots[id];
  }

  @override
  Future<Timeslot> update(Timeslot slot) async {
    final existing = _timeslots[slot.id];
    if (existing == null) throw StateError('Timeslot not found: ${slot.id}');
    _timeslots[slot.id] = slot;
    return slot;
  }

  @override
  Future<void> delete(String id) async {
    _timeslots.remove(id);
  }

  @override
  Future<List<Timeslot>> listByProject(String projectId) async {
    return _timeslots.values
        .where((s) => s.projectId == projectId)
        .toList()
      ..sort((a, b) => a.inPointMs.compareTo(b.inPointMs));
  }

  @override
  Future<List<Timeslot>> listByVideoSource(String videoSourceId) async {
    return _timeslots.values
        .where((s) => s.videoSourceId == videoSourceId)
        .toList()
      ..sort((a, b) => a.inPointMs.compareTo(b.inPointMs));
  }
}
