import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/domain/entities/user_profile.dart';
import 'package:highlight_creator/domain/entities/project.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/domain/entities/preset.dart';
import 'package:highlight_creator/domain/entities/template.dart';

void main() {
  group('UserProfile', () {
    test('copyWith preserves unchanged fields', () {
      final profile = UserProfile(
        id: 'u1',
        displayName: 'Alice',
        avatarPath: null,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 6, 1),
      );

      final updated = profile.copyWith(displayName: 'Alice Updated');

      expect(updated.id, 'u1');
      expect(updated.displayName, 'Alice Updated');
      expect(updated.avatarPath, isNull);
      expect(updated.createdAt, DateTime(2026, 1, 1));
    });
  });

  group('Timeslot', () {
    test('isValid returns true for valid range', () {
      final slot = Timeslot(
        id: 't1',
        projectId: 'p1',
        videoSourceId: 'v1',
        inPointMs: 0,
        outPointMs: 5000,
        createdAt: DateTime(2026),
      );
      expect(slot.isValid, isTrue);
      expect(slot.duration, const Duration(milliseconds: 5000));
    });

    test('isValid returns false when outPoint <= inPoint', () {
      final slot = Timeslot(
        id: 't1',
        projectId: 'p1',
        videoSourceId: 'v1',
        inPointMs: 5000,
        outPointMs: 5000,
        createdAt: DateTime(2026),
      );
      expect(slot.isValid, isFalse);
    });

    test('isValid returns false for negative inPoint', () {
      final slot = Timeslot(
        id: 't1',
        projectId: 'p1',
        videoSourceId: 'v1',
        inPointMs: -100,
        outPointMs: 1000,
        createdAt: DateTime(2026),
      );
      expect(slot.isValid, isFalse);
    });
  });

  group('Project', () {
    test('totalDuration sums all timeslot durations', () {
      final project = Project(
        id: 'p1',
        name: 'Test Project',
        userId: 'u1',
        timeslots: [
          Timeslot(
            id: 't1',
            projectId: 'p1',
            videoSourceId: 'v1',
            inPointMs: 0,
            outPointMs: 3000,
            createdAt: DateTime(2026),
          ),
          Timeslot(
            id: 't2',
            projectId: 'p1',
            videoSourceId: 'v1',
            inPointMs: 5000,
            outPointMs: 10000,
            createdAt: DateTime(2026),
          ),
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      expect(project.totalDuration, const Duration(milliseconds: 8000));
    });

    test('totalDuration is zero with no timeslots', () {
      final project = Project(
        id: 'p1',
        name: 'Empty',
        userId: 'u1',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(project.totalDuration, Duration.zero);
    });
  });

  group('VideoSource', () {
    test('duration getter converts milliseconds to Duration', () {
      final source = VideoSource(
        id: 'vs1',
        projectId: 'p1',
        filePath: '/videos/test.mp4',
        durationMs: 120000,
        width: 1920,
        height: 1080,
        codecName: 'h264',
        fps: 30.0,
        createdAt: DateTime(2026),
      );
      expect(source.duration, const Duration(minutes: 2));
    });
  });

  group('Preset', () {
    test('copyWith updates specified fields', () {
      final preset = Preset(
        id: 'pr1',
        name: 'Cinematic',
        category: PresetCategory.color,
        parameters: {'brightness': 1.2},
        isBuiltIn: true,
        updatedAt: DateTime(2026),
      );
      final updated = preset.copyWith(
        name: 'Cinematic V2',
        parameters: {'brightness': 1.5, 'contrast': 1.1},
      );
      expect(updated.name, 'Cinematic V2');
      expect(updated.parameters['brightness'], 1.5);
      expect(updated.parameters['contrast'], 1.1);
    });
  });

  group('Template', () {
    test('copyWith updates specified fields', () {
      const t = Template(
        id: 't1',
        name: 'Startup A',
        path: '/videos/intro.mp4',
        type: TemplateType.startup,
      );
      final updated = t.copyWith(name: 'Startup B', path: '/videos/new.mp4');
      expect(updated.name, 'Startup B');
      expect(updated.path, '/videos/new.mp4');
      expect(updated.type, TemplateType.startup);
    });

    test('copyWith preserves unchanged fields', () {
      const t = Template(
        id: 't2',
        name: 'Transition X',
        path: 'https://example.com/trans.mp4',
        type: TemplateType.transition,
      );
      final updated = t.copyWith();
      expect(updated.name, 'Transition X');
      expect(updated.path, 'https://example.com/trans.mp4');
      expect(updated.type, TemplateType.transition);
    });
  });
}
