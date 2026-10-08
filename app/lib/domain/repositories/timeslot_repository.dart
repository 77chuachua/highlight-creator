import 'package:highlight_creator/domain/entities/timeslot.dart';

/// Abstract repository for timeslot CRUD operations.
abstract class TimeslotRepository {
  Future<Timeslot> create(Timeslot slot);
  Future<Timeslot?> getById(String id);
  Future<Timeslot> update(Timeslot slot);
  Future<void> delete(String id);
  Future<List<Timeslot>> listByProject(String projectId);
  Future<List<Timeslot>> listByVideoSource(String videoSourceId);
}
