import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_notes_ssh/utils/markdown_checklist_helper.dart';

void main() {
  group('MarkdownChecklistHelper.toggleCheckbox', () {
    test('toggles unchecked item to checked', () {
      const input = '- [ ] Buy groceries\n- [ ] Pay rent';
      final output = MarkdownChecklistHelper.toggleCheckbox(input, 0);
      expect(output, '- [x] Buy groceries\n- [ ] Pay rent');
    });

    test('toggles checked item to unchecked', () {
      const input = '- [x] Buy groceries\n- [ ] Pay rent';
      final output = MarkdownChecklistHelper.toggleCheckbox(input, 0);
      expect(output, '- [ ] Buy groceries\n- [ ] Pay rent');
    });

    test('toggles uppercase [X] to unchecked', () {
      const input = '- [X] Buy groceries';
      final output = MarkdownChecklistHelper.toggleCheckbox(input, 0);
      expect(output, '- [ ] Buy groceries');
    });

    test('preserves indentation for nested checklist items', () {
      const input = '  - [ ] Sub-task\n    - [x] Deep item';
      final output1 = MarkdownChecklistHelper.toggleCheckbox(input, 0);
      expect(output1, '  - [x] Sub-task\n    - [x] Deep item');

      final output2 = MarkdownChecklistHelper.toggleCheckbox(input, 1);
      expect(output2, '  - [ ] Sub-task\n    - [ ] Deep item');
    });

    test('returns markdown unchanged if line is not a checklist item', () {
      const input = '# Title\nSome paragraph text\n- [ ] Task';
      expect(MarkdownChecklistHelper.toggleCheckbox(input, 0), input);
      expect(MarkdownChecklistHelper.toggleCheckbox(input, 1), input);
    });

    test('returns markdown unchanged if line index is out of bounds', () {
      const input = '- [ ] Task';
      expect(MarkdownChecklistHelper.toggleCheckbox(input, -1), input);
      expect(MarkdownChecklistHelper.toggleCheckbox(input, 5), input);
    });

    test('preserves CRLF line endings', () {
      const input = '- [ ] Item 1\r\n- [ ] Item 2';
      final output = MarkdownChecklistHelper.toggleCheckbox(input, 1);
      expect(output, '- [ ] Item 1\r\n- [x] Item 2');
    });
  });

  group('MarkdownChecklistHelper.countChecklistItems', () {
    test('counts total and checked items accurately', () {
      const markdown = '''
# Shopping List
- [ ] Milk
- [x] Bread
- [X] Eggs
- Just a bullet
Some other text
- [ ] Apples
''';
      final counts = MarkdownChecklistHelper.countChecklistItems(markdown);
      expect(counts.total, 4);
      expect(counts.checked, 2);
    });

    test('returns zeros when no checklist items present', () {
      const markdown = '# Header\nJust text';
      final counts = MarkdownChecklistHelper.countChecklistItems(markdown);
      expect(counts.total, 0);
      expect(counts.checked, 0);
    });
  });

  group('MarkdownChecklistHelper.extractTitle', () {
    test('extracts first # Heading line without # marker', () {
      const markdown = '# My Awesome Note\nBody content here';
      expect(MarkdownChecklistHelper.extractTitle(markdown), 'My Awesome Note');
    });

    test('extracts ## Heading if first heading is H2', () {
      const markdown = '## Subheading Title\nBody text';
      expect(MarkdownChecklistHelper.extractTitle(markdown), 'Subheading Title');
    });

    test('returns first non-empty line trimmed if no heading present', () {
      const markdown = '\n\n   First non-empty line text   \nSecond line';
      expect(
        MarkdownChecklistHelper.extractTitle(markdown),
        'First non-empty line text',
      );
    });

    test('returns Untitled if markdown is empty or only whitespace', () {
      expect(MarkdownChecklistHelper.extractTitle(''), 'Untitled');
      expect(MarkdownChecklistHelper.extractTitle('   \n\n  '), 'Untitled');
    });
  });

  group('MarkdownChecklistHelper.getChecklistLines', () {
    test('extracts lines with indices, text without prefix, and checked state', () {
      const markdown = '''
# Header (line 0)
- [ ] Task One (line 1)
Plain line (line 2)
  - [x] Task Two indented (line 3)
- [X] Task Three uppercase (line 4)
''';
      final items = MarkdownChecklistHelper.getChecklistLines(markdown);
      expect(items.length, 3);

      expect(items[0].lineIndex, 1);
      expect(items[0].text, 'Task One (line 1)');
      expect(items[0].isChecked, isFalse);

      expect(items[1].lineIndex, 3);
      expect(items[1].text, 'Task Two indented (line 3)');
      expect(items[1].isChecked, isTrue);

      expect(items[2].lineIndex, 4);
      expect(items[2].text, 'Task Three uppercase (line 4)');
      expect(items[2].isChecked, isTrue);
    });

    test('handles empty checklist item without text', () {
      const markdown = '- [ ]';
      final items = MarkdownChecklistHelper.getChecklistLines(markdown);
      expect(items.length, 1);
      expect(items[0].lineIndex, 0);
      expect(items[0].text, '');
      expect(items[0].isChecked, isFalse);
    });
  });

  group('MarkdownChecklistHelper.extractPreview', () {
    test('strips markdown markers and collapses whitespace', () {
      const markdown = '''
# Meeting Notes
- [ ] Discuss budget
- [x] Review designs
**Bold action item**
*Italic reminder*
- Bullet point
''';
      final preview = MarkdownChecklistHelper.extractPreview(markdown);
      expect(
        preview,
        'Meeting Notes Discuss budget Review designs Bold action item Italic reminder Bullet point',
      );
    });

    test('truncates to maxLength with ... if exceeded', () {
      final longMarkdown = 'A' * 200;
      final preview = MarkdownChecklistHelper.extractPreview(
        longMarkdown,
        maxLength: 50,
      );
      expect(preview, '${'A' * 50}...');
      expect(preview.length, 53);
    });

    test('does not truncate if within maxLength', () {
      const markdown = 'Short preview';
      final preview = MarkdownChecklistHelper.extractPreview(
        markdown,
        maxLength: 50,
      );
      expect(preview, 'Short preview');
    });
  });
}
