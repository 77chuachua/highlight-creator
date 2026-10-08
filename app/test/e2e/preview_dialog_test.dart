import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/repositories/project_repository_impl.dart';
import 'package:highlight_creator/data/repositories/timeslot_repository_impl.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/domain/entities/template.dart';
import 'package:highlight_creator/domain/repositories/template_repository.dart';
import 'package:highlight_creator/presentation/shell/preview_dialog.dart';

void main() {
  setUp(() {
    // Set large enough viewport for the 1400x1100 dialog.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('PreviewDialog renders title and resolution chips',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = _createContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => FilledButton(
                onPressed: () => showDialog(
                  context: ctx,
                  builder: (_) => const PreviewDialog(
                    maxSourceHeight: 1080,
                    timeslotCount: 3,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 200));

    // Dialog title rendered.
    expect(find.byIcon(Icons.visibility), findsOneWidget);

    // Resolution chips rendered.
    expect(find.byKey(const Key('resolution_480P')), findsOneWidget);
    expect(find.byKey(const Key('resolution_720P')), findsOneWidget);
    expect(find.byKey(const Key('resolution_1080P')), findsOneWidget);
    expect(find.byKey(const Key('resolution_4K')), findsOneWidget);

    // Confirm button rendered.
    expect(find.byKey(const Key('preview_confirm_button')), findsOneWidget);
  });

  testWidgets('PreviewDialog shows timeslot count and total elapse',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = _createContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => FilledButton(
                onPressed: () => showDialog(
                  context: ctx,
                  builder: (_) => const PreviewDialog(
                    maxSourceHeight: 1080,
                    timeslotCount: 3,
                    totalElapseMs: 45000,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 200));

    // Timeslot count and total elapse shown below the resolution picker.
    expect(find.text('3 timeslots'), findsOneWidget);
    expect(find.text('Total elapse: 0:45'), findsOneWidget);
  });

  testWidgets('PreviewDialog confirm returns selected resolution',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = _createContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => FilledButton(
                onPressed: () async {
                  final result = await showDialog<(int, int)>(
                    context: ctx,
                    builder: (_) => const PreviewDialog(
                      maxSourceHeight: 1080,
                      timeslotCount: 2,
                    ),
                  );
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Result: $result')),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 200));

    // Select 1080P.
    await tester.tap(find.byKey(const Key('resolution_1080P')));
    await tester.pumpAndSettle();

    // Tap confirm.
    await tester.tap(find.byKey(const Key('preview_confirm_button')));
    await tester.pumpAndSettle();

    expect(find.text('Result: (1920, 1080)'), findsOneWidget);
  });

  testWidgets('PreviewDialog cancel returns null', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = _createContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => FilledButton(
                onPressed: () async {
                  final result = await showDialog<(int, int)>(
                    context: ctx,
                    builder: (_) => const PreviewDialog(
                      maxSourceHeight: 1080,
                      timeslotCount: 1,
                    ),
                  );
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Result: $result')),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 200));

    // Tap cancel.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Result: null'), findsOneWidget);
  });

  testWidgets('PreviewDialog disables resolutions above source height',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = _createContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => FilledButton(
                onPressed: () => showDialog(
                  context: ctx,
                  builder: (_) => const PreviewDialog(
                    maxSourceHeight: 720,
                    timeslotCount: 1,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 200));

    // 1080P and 4K should be disabled when source is 720p.
    final chip1080 = tester.widget<ChoiceChip>(
        find.byKey(const Key('resolution_1080P')));
    final chip4k = tester.widget<ChoiceChip>(
        find.byKey(const Key('resolution_4K')));
    expect(chip1080.onSelected, isNull);
    expect(chip4k.onSelected, isNull);

    // 720P should be enabled.
    final chip720 = tester.widget<ChoiceChip>(
        find.byKey(const Key('resolution_720P')));
    expect(chip720.onSelected, isNotNull);
  });

  testWidgets(
      'returning from the template editor rebuilds previews without throwing',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        // Fast, empty repo so the template cards (and their edit pencils)
        // render synchronously inside the test.
        templateRepositoryProvider
            .overrideWith((ref) => _EmptyTemplateRepository()),
        projectRepositoryProvider.overrideWith((ref) => ProjectRepositoryImpl()),
        timeslotRepositoryProvider
            .overrideWith((ref) => TimeslotRepositoryImpl()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => FilledButton(
                onPressed: () => showDialog(
                  context: ctx,
                  builder: (_) => const PreviewDialog(
                    maxSourceHeight: 1080,
                    timeslotCount: 1,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Each template card has an edit pencil that opens the config dialog.
    expect(find.byIcon(Icons.edit), findsWidgets);
    await tester.tap(find.byIcon(Icons.edit).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Close the editor: PreviewDialog._openTemplateEditor then swaps
    // _templatesFuture. Regression: that reassignment used to throw
    // LateInitializationError, leaving the previews dead.
    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    // No pending debounce timers from the editor.
    await tester.pump(const Duration(milliseconds: 900));
  });
}

/// Empty in-memory template repository: no filesystem I/O, resolves on a
/// microtask so widget tests don't hang on async disk access.
class _EmptyTemplateRepository implements TemplateRepository {
  @override
  Future<Template?> getById(String id) async => null;

  @override
  Future<List<Template>> listAll() async => const [];

  @override
  Future<List<Template>> listByType(TemplateType type) async => const [];

  @override
  Future<Template> save(Template template) async => template;

  @override
  Future<void> delete(String id) async {}
}

ProviderContainer _createContainer() {
  final projectRepo = ProjectRepositoryImpl();
  final timeslotRepo = TimeslotRepositoryImpl();
  return ProviderContainer(
    overrides: [
      projectRepositoryProvider.overrideWith((ref) => projectRepo),
      timeslotRepositoryProvider.overrideWith((ref) => timeslotRepo),
    ],
  );
}
