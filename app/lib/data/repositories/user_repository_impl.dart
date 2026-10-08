import 'package:highlight_creator/domain/entities/user_profile.dart';
import 'package:highlight_creator/domain/repositories/user_repository.dart';

/// Drift-backed implementation of UserRepository.
/// Phase 0: placeholder. Full implementation comes in Phase 1 once drift codegen runs.
class UserRepositoryImpl implements UserRepository {
  @override
  Future<UserProfile?> getCurrentUser() async {
    // TODO Phase 1: implement via db.getCurrentUser()
    return null;
  }

  @override
  Future<UserProfile> save(UserProfile profile) async {
    return profile; // TODO Phase 1: implement via db.upsertUser()
  }

  @override
  Future<void> delete(String id) async {
    // TODO Phase 1: implement via db.deleteUser()
  }

  @override
  Future<List<UserProfile>> listAll() async {
    return []; // TODO Phase 1: implement via db.listAllUsers()
  }
}
