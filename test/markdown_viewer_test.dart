import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_notes_ssh/widgets/markdown_viewer.dart';

void main() {
  group('MarkdownViewer Widget Tests', () {
    testWidgets('renders headings correctly with VS Code styling', (tester) async {
      const markdown =
          '# Main Heading\n## Sub Heading\n### Section\n#### Level 4\n##### Level 5\n###### Level 6';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownViewer(markdown: markdown),
          ),
        ),
      );

      expect(find.text('Main Heading'), findsOneWidget);
      expect(find.text('Sub Heading'), findsOneWidget);
      expect(find.text('Section'), findsOneWidget);
      expect(find.text('Level 4'), findsOneWidget);
      expect(find.text('Level 5'), findsOneWidget);
      expect(find.text('Level 6'), findsOneWidget);

      // H1 and H2 include bottom Divider lines
      expect(find.byType(Divider), findsNWidgets(2));
    });

    testWidgets('renders checklist items with toggle callback and accessibility semantics', (tester) async {
      const markdown = '- [ ] Buy groceries\n- [x] Read chapter 1';
      int? tappedIndex;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownViewer(
              markdown: markdown,
              onCheckboxToggled: (idx) => tappedIndex = idx,
            ),
          ),
        ),
      );

      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.text('Read chapter 1'), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);

      // Verify semantics
      final uncheckedSemantics = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.toggled == false && w.properties.button == true,
      );
      expect(uncheckedSemantics, findsOneWidget);

      final checkedSemantics = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.toggled == true && w.properties.button == true,
      );
      expect(checkedSemantics, findsOneWidget);

      // Tap on unchecked item
      await tester.tap(find.text('Buy groceries'));
      await tester.pump();

      expect(tappedIndex, 0);
    });

    testWidgets('renders bullet lists and numbered lists', (tester) async {
      const markdown = '- First item\n* Second item\n1. Numbered item';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownViewer(markdown: markdown),
          ),
        ),
      );

      expect(find.text('First item'), findsOneWidget);
      expect(find.text('Second item'), findsOneWidget);
      expect(find.text('Numbered item'), findsOneWidget);
      expect(find.text('1. '), findsOneWidget);
    });

    testWidgets('renders blockquotes and code blocks', (tester) async {
      const markdown = '> Important advice\n\n```\nconst x = 42;\n```';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownViewer(markdown: markdown),
          ),
        ),
      );

      expect(find.text('Important advice'), findsOneWidget);
      expect(find.text('const x = 42;'), findsOneWidget);
    });

    testWidgets('skips first header when skipFirstHeader is true and matches filterTitle', (tester) async {
      const markdown = '# Shopping\n- [ ] Apples\n- [ ] Oranges';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownViewer(
              markdown: markdown,
              skipFirstHeader: true,
              filterTitle: 'Shopping',
            ),
          ),
        ),
      );

      // Shopping header should be skipped
      expect(find.text('Shopping'), findsNothing);
      expect(find.text('Apples'), findsOneWidget);
      expect(find.text('Oranges'), findsOneWidget);
    });

    testWidgets('compact mode truncates with more items indicator', (tester) async {
      final markdown = List.generate(15, (i) => '- [ ] Task $i').join('\n');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownViewer(
              markdown: markdown,
              isCompact: true,
              maxCompactLines: 5,
            ),
          ),
        ),
      );

      expect(find.text('Task 0'), findsOneWidget);
      expect(find.text('Task 4'), findsOneWidget);
      expect(find.text('Task 10'), findsNothing);
      expect(find.text('+10 more items'), findsOneWidget);
    });

    testWidgets('full mode does not truncate', (tester) async {
      final markdown = List.generate(12, (i) => '- [ ] Task $i').join('\n');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownViewer(
              markdown: markdown,
              isCompact: false,
            ),
          ),
        ),
      );

      expect(find.text('Task 0'), findsOneWidget);
      expect(find.text('Task 11'), findsOneWidget);
      expect(find.textContaining('more items'), findsNothing);
    });
  });
}
