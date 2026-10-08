import 'package:highlight_creator/domain/entities/user_profile.dart';

/// Abstract repository for user profile operations.
abstract class UserRepository {
  /// Get the current user profile, or null if not created.
  Future<UserProfile?> getCurrentUser();

  /// Create or update a user profile.
  Future<UserProfile> save(UserProfile profile);

  /// Delete a user profile by ID.
  Future<void> delete(String id);

  /// List all local profiles.
  Future<List<UserProfile>> listAll();
}
