import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_notes_ssh/services/conflict_resolver.dart';

void main() {
  group('ConflictResolver.resolve basic cases', () {
    test('returns ConflictDetected when base is null', () {
      final result = ConflictResolver.resolve(
        base: null,
        local: 'local content',
        remote: 'remote content',
      );

      expect(result, isA<ConflictDetected>());
      final conflict = result as ConflictDetected;
      expect(conflict.localContent, 'local content');
      expect(conflict.remoteContent, 'remote content');
      expect(conflict.partialMerge, isNull);
    });

    test('returns AlreadyInSync when local == remote', () {
      final result = ConflictResolver.resolve(
        base: 'initial base',
        local: 'same content',
        remote: 'same content',
      );

      expect(result, isA<AlreadyInSync>());
      expect(result, const AlreadyInSync());
    });

    test('returns FastForwardPull when local == base and remote has changes', () {
      final result = ConflictResolver.resolve(
        base: 'original content',
        local: 'original content',
        remote: 'updated remote content',
      );

      expect(result, isA<FastForwardPull>());
      final pull = result as FastForwardPull;
      expect(pull.content, 'updated remote content');
    });

    test('returns FastForwardPush when remote == base and local has changes', () {
      final result = ConflictResolver.resolve(
        base: 'original content',
        local: 'updated local content',
        remote: 'original content',
      );

      expect(result, isA<FastForwardPush>());
      final push = result as FastForwardPush;
      expect(push.content, 'updated local content');
    });
  });

  group('ConflictResolver 3-way merge real-world cases', () {
    test('toggling different checklist items on different lines auto-merges', () {
      const base = '''
# Checklist
- [ ] Task 1
- [ ] Task 2
- [ ] Task 3
''';

      // Local toggles Task 1 on line 1
      const local = '''
# Checklist
- [x] Task 1
- [ ] Task 2
- [ ] Task 3
''';

      // Remote toggles Task 3 on line 3
      const remote = '''
# Checklist
- [ ] Task 1
- [ ] Task 2
- [x] Task 3
''';

      final result = ConflictResolver.resolve(
        base: base,
        local: local,
        remote: remote,
      );

      expect(result, isA<AutoMerged>());
      final autoMerged = result as AutoMerged;
      const expected = '''
# Checklist
- [x] Task 1
- [ ] Task 2
- [x] Task 3
''';
      expect(autoMerged.mergedContent, expected);
    });

    test('appending text at the end on both sides auto-merges', () {
      const base = '''
# Main Section
Original notes line 1
Original notes line 2
''';

      const local = '''
# Main Section
Original notes line 1
Original notes line 2
Appended note from Phone
''';

      const remote = '''
# Main Section
Original notes line 1
Original notes line 2
Appended note from Laptop
''';

      final result = ConflictResolver.resolve(
        base: base,
        local: local,
        remote: remote,
      );

      expect(result, isA<AutoMerged>());
      final autoMerged = result as AutoMerged;
      expect(autoMerged.mergedContent.contains('Appended note from Phone'), isTrue);
      expect(autoMerged.mergedContent.contains('Appended note from Laptop'), isTrue);
      expect(autoMerged.mergedContent.startsWith('# Main Section'), isTrue);
    });

    test('identical changes on both sides auto-merges cleanly', () {
      const base = '''
# Heading
Original text
''';

      const modified = '''
# Heading
Modified text
''';

      final result = ConflictResolver.resolve(
        base: base,
        local: modified,
        remote: modified,
      );

      expect(result, isA<AlreadyInSync>());
    });

    test('editing the same line differently detects conflict', () {
      const base = '''
# Title
The quick brown fox
Footer
''';

      const local = '''
# Title
The FAST brown fox
Footer
''';

      const remote = '''
# Title
The SLOW brown fox
Footer
''';

      final result = ConflictResolver.resolve(
        base: base,
        local: local,
        remote: remote,
      );

      expect(result, isA<ConflictDetected>());
      final conflict = result as ConflictDetected;
      expect(conflict.localContent, local);
      expect(conflict.remoteContent, remote);
      expect(conflict.partialMerge, isNotNull);
      expect(conflict.partialMerge!.contains('<<<<<<< local'), isTrue);
      expect(conflict.partialMerge!.contains('The FAST brown fox'), isTrue);
      expect(conflict.partialMerge!.contains('======='), isTrue);
      expect(conflict.partialMerge!.contains('The SLOW brown fox'), isTrue);
      expect(conflict.partialMerge!.contains('>>>>>>> remote'), isTrue);
    });

    test('one side deletes a line, other side edits it detects conflict', () {
      const base = '''
Line 1
Line 2 to be deleted or modified
Line 3
''';

      // Local deletes Line 2
      const local = '''
Line 1
Line 3
''';

      // Remote modifies Line 2
      const remote = '''
Line 1
Line 2 heavily updated
Line 3
''';

      final result = ConflictResolver.resolve(
        base: base,
        local: local,
        remote: remote,
      );

      expect(result, isA<ConflictDetected>());
      final conflict = result as ConflictDetected;
      expect(conflict.partialMerge, isNotNull);
      expect(conflict.partialMerge!.contains('<<<<<<< local'), isTrue);
      expect(conflict.partialMerge!.contains('Line 2 heavily updated'), isTrue);
      expect(conflict.partialMerge!.contains('>>>>>>> remote'), isTrue);
    });
  });

  group('MergeResult pattern matching', () {
    test('pattern matching works exhaustively across all subclasses', () {
      const results = <MergeResult>[
        AlreadyInSync(),
        FastForwardPull('pulled'),
        FastForwardPush('pushed'),
        AutoMerged('merged'),
        ConflictDetected(localContent: 'l', remoteContent: 'r'),
      ];

      for (final res in results) {
        final label = switch (res) {
          AlreadyInSync() => 'in_sync',
          FastForwardPull(:final content) => 'pull: $content',
          FastForwardPush(:final content) => 'push: $content',
          AutoMerged(:final mergedContent) => 'auto: $mergedContent',
          ConflictDetected(:final localContent, :final remoteContent) =>
            'conflict: $localContent vs $remoteContent',
        };
        expect(label.isNotEmpty, isTrue);
      }
    });
  });
}
