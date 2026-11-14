import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/theme/app_theme.dart';
import 'package:sticky_notes_ssh/widgets/color_picker_bar.dart';
import 'package:sticky_notes_ssh/widgets/diff_line_widget.dart';
import 'package:sticky_notes_ssh/widgets/markdown_toolbar.dart';
import 'package:sticky_notes_ssh/widgets/sticky_card.dart';
import 'package:sticky_notes_ssh/widgets/sync_status_pill.dart';
import 'package:sticky_notes_ssh/widgets/tag_editor.dart';

void main() {
  group('AppTheme Tests', () {
    test('stickyColors has 6 palette colors', () {
      expect(AppTheme.stickyColors.length, 6);
      expect(AppTheme.stickyColors[0].name, 'Amber');
      expect(AppTheme.stickyColors[1].name, 'Mint');
      expect(AppTheme.stickyColors[2].name, 'Sky');
      expect(AppTheme.stickyColors[3].name, 'Lavender');
      expect(AppTheme.stickyColors[4].name, 'Rose');
      expect(AppTheme.stickyColors[5].name, 'Slate');
    });

    test('cardColor returns light and dark variants properly', () {
      final amberLight = AppTheme.cardColor(0, Brightness.light);
      final amberDark = AppTheme.cardColor(0, Brightness.dark);
      expect(amberLight, const Color(0xFFFFF8E1));
      expect(amberDark, const Color(0xFF4E3E00));

      // Wraps out of bounds indices safely
      final wrappedLight = AppTheme.cardColor(6, Brightness.light);
      expect(wrappedLight, const Color(0xFFFFF8E1));
    });

    test('lightTheme and darkTheme are Material 3', () {
      final light = AppTheme.lightTheme();
      final dark = AppTheme.darkTheme();
      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
    });
  });

  group('DiffLineWidget Tests', () {
    testWidgets('renders added line with green tint and + prefix', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DiffLineWidget(text: 'hello world', type: DiffLineType.added),
          ),
        ),
      );

      expect(find.text('+ hello world'), findsOneWidget);
    });

    testWidgets('renders removed line with - prefix', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DiffLineWidget(text: 'old text', type: DiffLineType.removed),
          ),
        ),
      );

      expect(find.text('- old text'), findsOneWidget);
    });

    testWidgets('renders header line', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DiffLineWidget(text: '1,4 +1,5', type: DiffLineType.header),
          ),
        ),
      );

      expect(find.text('@@ 1,4 +1,5 @@'), findsOneWidget);
    });
  });

  group('SyncStatusPill Tests', () {
    testWidgets('renders each SyncState correctly', (tester) async {
      for (final state in SyncState.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SyncStatusPill(state: state),
            ),
          ),
        );

        final expectedText = switch (state) {
          SyncState.connected => 'Connected',
          SyncState.offline => 'Offline',
          SyncState.syncing => 'Syncing...',
          SyncState.conflict => 'Conflict',
        };

        expect(find.text(expectedText), findsOneWidget);
      }
    });
  });

  group('ColorPickerBar Tests', () {
    testWidgets('renders 6 circles and handles selection', (tester) async {
      int selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ColorPickerBar(
                  selectedIndex: selected,
                  onColorSelected: (idx) => setState(() => selected = idx),
                );
              },
            ),
          ),
        ),
      );

      // Check checkmark exists for selected item 0
      expect(find.byIcon(Icons.check), findsOneWidget);

      // Tap on second color (Mint)
      await tester.tap(find.byTooltip('Mint'));
      await tester.pumpAndSettle();

      expect(selected, 1);
    });
  });

  group('TagEditor Tests', () {
    testWidgets('displays existing tags as InputChip and allows delete', (tester) async {
      List<String> currentTags = <String>['work', 'urgent'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return TagEditor(
                  tags: currentTags,
                  onTagsChanged: (newTags) => setState(() => currentTags = newTags),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('#work'), findsOneWidget);
      expect(find.text('#urgent'), findsOneWidget);

      // Tap delete on 'work'
      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey<String>('tag_work')),
        matching: find.byIcon(Icons.close),
      ));
      await tester.pumpAndSettle();

      expect(currentTags, <String>['urgent']);
    });

    testWidgets('adds new tag on enter', (tester) async {
      List<String> currentTags = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return TagEditor(
                  tags: currentTags,
                  onTagsChanged: (newTags) => setState(() => currentTags = newTags),
                );
              },
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'project');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(currentTags, <String>['project']);
    });
  });

  group('MarkdownToolbar Tests', () {
    testWidgets('wraps selected text with bold syntax', (tester) async {
      final controller = TextEditingController(text: 'Hello world');
      final focusNode = FocusNode();

      // Select 'world'
      controller.selection = const TextSelection(baseOffset: 6, extentOffset: 11);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownToolbar(
              controller: controller,
              focusNode: focusNode,
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Bold (**text**)'));
      await tester.pump();

      expect(controller.text, 'Hello **world**');
    });

    testWidgets('inserts H1 at cursor position', (tester) async {
      final controller = TextEditingController(text: 'Title');
      final focusNode = FocusNode();

      controller.selection = const TextSelection.collapsed(offset: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownToolbar(
              controller: controller,
              focusNode: focusNode,
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Heading 1'));
      await tester.pump();

      expect(controller.text, '# Title');
    });
  });

  group('StickyCard Tests', () {
    testWidgets('renders title, pin, conflict badge and tags', (tester) async {
      final note = StickyNote(
        id: '123',
        filename: 'groceries.md',
        title: 'Grocery List',
        content: '# Grocery List\n- [ ] Milk\n- [x] Bread\nApples',
        colorIndex: 0,
        isPinned: true,
        tags: const <String>['shopping', 'food'],
        updatedAt: DateTime.now(),
        createdAt: DateTime.now(),
        syncStatus: SyncStatus.conflict,
      );

      int toggledLineIndex = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StickyCard(
              note: note,
              onTap: () {},
              onCheckboxToggle: (idx) => toggledLineIndex = idx,
            ),
          ),
        ),
      );

      expect(find.text('Grocery List'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
      expect(find.text('Conflict'), findsOneWidget);
      expect(find.text('#shopping'), findsOneWidget);
      expect(find.text('#food'), findsOneWidget);

      // Verify checklist items
      expect(find.text('Milk'), findsOneWidget);
      expect(find.text('Bread'), findsOneWidget);

      // Tap on 'Milk' checkbox
      await tester.tap(find.text('Milk'));
      await tester.pump();

      expect(toggledLineIndex, 1);
    });
  });
}
