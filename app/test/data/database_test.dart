import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/database/database.dart';

void main() {
  group('AppDatabase', () {
    test('in-memory database instantiates without error', () async {
      final db = AppDatabase.memory();
      expect(db.schemaVersion, 4);
      await db.close();
    });

    test('schema version is correct', () async {
      final db = AppDatabase.memory();
      expect(db.schemaVersion, 4);
      await db.close();
    });
  });
}
