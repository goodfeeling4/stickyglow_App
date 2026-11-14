import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/widgets/color_picker_bar.dart';
import 'package:sticky_notes_ssh/widgets/markdown_toolbar.dart';
import 'package:sticky_notes_ssh/widgets/sticky_card.dart';
import 'package:sticky_notes_ssh/widgets/sync_status_pill.dart';
import 'package:sticky_notes_ssh/widgets/tag_editor.dart';

void main() {
  group('UI/UX Accessibility Guidelines Tests', () {
    testWidgets('ColorPickerBar has >= 48x48 dp touch targets and Semantics', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ColorPickerBar(
              selectedIndex: 2,
              onColorSelected: (_) {},
            ),
          ),
        ),
      );

      // Verify Semantics nodes for color buttons inside ColorPickerBar
      final semanticsFinder = find.descendant(
        of: find.byType(ColorPickerBar),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.button == true,
        ),
      );
      expect(semanticsFinder, findsNWidgets(6));

      // Verify touch target constraints on the circles
      final constrainedFinder = find.descendant(
        of: find.byType(ColorPickerBar),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ConstrainedBox &&
              widget.constraints.minWidth == 48 &&
              widget.constraints.minHeight == 48,
        ),
      );
      expect(constrainedFinder, findsNWidgets(6));
    });

    testWidgets('MarkdownToolbar buttons meet 48x48 dp tap targets and have Semantics', (tester) async {
      final controller = TextEditingController(text: 'sample text');
      final focusNode = FocusNode();

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

      // Verify all toolbar buttons have Semantics button = true
      final buttonSemantics = find.descendant(
        of: find.byType(MarkdownToolbar),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.button == true,
        ),
      );
      expect(buttonSemantics, findsWidgets);

      // Verify all buttons have minWidth and minHeight >= 48
      final buttonBoxes = find.descendant(
        of: find.byType(MarkdownToolbar),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ConstrainedBox &&
              widget.constraints.minWidth >= 48 &&
              widget.constraints.minHeight >= 48,
        ),
      );
      expect(buttonBoxes, findsWidgets);

      // Verify dividers are excluded from semantics
      final dividers = find.byType(ExcludeSemantics);
      expect(dividers, findsWidgets);
    });

    testWidgets('StickyCard checklist items have toggle semantics and accessible tap area', (tester) async {
      final note = StickyNote(
        id: 'note-1',
        filename: 'todos.md',
        title: 'Todos',
        content: '# Todos\n- [ ] Buy milk\n- [x] Read book',
        colorIndex: 1,
        isPinned: false,
        tags: const <String>[],
        updatedAt: DateTime.now(),
        createdAt: DateTime.now(),
        syncStatus: SyncStatus.synced,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StickyCard(
              note: note,
              onTap: () {},
              onCheckboxToggle: (_) {},
            ),
          ),
        ),
      );

      // Verify toggle semantics on checklist items
      final checkedItem = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.toggled == true &&
            widget.properties.button == true,
      );
      expect(checkedItem, findsOneWidget);

      final uncheckedItem = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.toggled == false &&
            widget.properties.button == true,
      );
      expect(uncheckedItem, findsOneWidget);
    });

    testWidgets('SyncStatusPill shows redundant icons for colorblind accessibility', (tester) async {
      // Connected state has check icon
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SyncStatusPill(state: SyncState.connected),
          ),
        ),
      );
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      // Offline state has cloud off icon
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SyncStatusPill(state: SyncState.offline),
          ),
        ),
      );
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);

      // Conflict state has warning icon
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SyncStatusPill(state: SyncState.conflict),
          ),
        ),
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('TagEditor InputChip has delete tooltip for screen readers', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TagEditor(
              tags: const <String>['test_tag'],
              onTagsChanged: (_) {},
            ),
          ),
        ),
      );

      final chipFinder = find.byWidgetPredicate(
        (widget) =>
            widget is InputChip &&
            widget.deleteButtonTooltipMessage == 'Remove #test_tag',
      );
      expect(chipFinder, findsOneWidget);
    });
  });
}
