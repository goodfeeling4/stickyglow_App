import 'dart:math';

/// Sealed class representing the result of a 3-way merge operation.
sealed class MergeResult {
  const MergeResult();
}

/// Remote had changes, local was unchanged from base. Fast-forward pull remote.
class FastForwardPull extends MergeResult {
  /// Creates a [FastForwardPull] result with the new remote [content].
  const FastForwardPull(this.content);

  /// The updated remote content to apply locally.
  final String content;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FastForwardPull &&
          runtimeType == other.runtimeType &&
          content == other.content;

  @override
  int get hashCode => content.hashCode;

  @override
  String toString() => 'FastForwardPull(content: $content)';
}

/// Local had changes, remote was unchanged from base. Fast-forward push local.
class FastForwardPush extends MergeResult {
  /// Creates a [FastForwardPush] result with the local [content] to push.
  const FastForwardPush(this.content);

  /// The modified local content to push to remote.
  final String content;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FastForwardPush &&
          runtimeType == other.runtimeType &&
          content == other.content;

  @override
  int get hashCode => content.hashCode;

  @override
  String toString() => 'FastForwardPush(content: $content)';
}

/// Both local and remote are already identical.
class AlreadyInSync extends MergeResult {
  /// Creates an [AlreadyInSync] result.
  const AlreadyInSync();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlreadyInSync && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'AlreadyInSync()';
}

/// Non-overlapping changes from both sides were cleanly auto-merged.
class AutoMerged extends MergeResult {
  /// Creates an [AutoMerged] result with the [mergedContent].
  const AutoMerged(this.mergedContent);

  /// The cleanly merged content combining changes from local and remote.
  final String mergedContent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoMerged &&
          runtimeType == other.runtimeType &&
          mergedContent == other.mergedContent;

  @override
  int get hashCode => mergedContent.hashCode;

  @override
  String toString() => 'AutoMerged(mergedContent: $mergedContent)';
}

/// Overlapping or conflicting changes detected between local and remote.
class ConflictDetected extends MergeResult {
  /// Creates a [ConflictDetected] result.
  const ConflictDetected({
    required this.localContent,
    required this.remoteContent,
    this.partialMerge,
  });

  /// The current local version of the content.
  final String localContent;

  /// The remote version of the content from the laptop.
  final String remoteContent;

  /// The partial merge output containing Git-style conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`),
  /// or `null` if base content was unavailable.
  final String? partialMerge;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConflictDetected &&
          runtimeType == other.runtimeType &&
          localContent == other.localContent &&
          remoteContent == other.remoteContent &&
          partialMerge == other.partialMerge;

  @override
  int get hashCode => Object.hash(localContent, remoteContent, partialMerge);

  @override
  String toString() =>
      'ConflictDetected(localContent: $localContent, remoteContent: $remoteContent, partialMerge: $partialMerge)';
}

/// The type of edit operation in a line-level diff.
enum EditType {
  /// The line exists in both source and destination and is kept.
  keep,

  /// The line is inserted into the destination.
  insert,

  /// The line is deleted from the source.
  delete,
}

/// Represents a single edit operation from a line-level diff.
class EditOp {
  /// Creates an edit operation.
  const EditOp({
    required this.type,
    required this.fromIndex,
    required this.toIndex,
    required this.text,
  });

  /// The edit operation type (keep, insert, or delete).
  final EditType type;

  /// 0-based line index in the source list (`from`), or -1 if insertion.
  final int fromIndex;

  /// 0-based line index in the destination list (`to`), or -1 if deletion.
  final int toIndex;

  /// The line text content.
  final String text;

  /// Convenience getter for the primary line index of this edit operation.
  int get lineIndex => type == EditType.insert ? toIndex : fromIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditOp &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          fromIndex == other.fromIndex &&
          toIndex == other.toIndex &&
          text == other.text;

  @override
  int get hashCode => Object.hash(type, fromIndex, toIndex, text);

  @override
  String toString() =>
      'EditOp($type, from: $fromIndex, to: $toIndex, text: "$text")';
}

/// An internal representation of a contiguous diff hunk relative to base lines.
class _Hunk {
  _Hunk({
    required this.baseStart,
    required this.baseEnd,
    required this.lines,
  });

  /// The start line index in base (inclusive).
  final int baseStart;

  /// The end line index in base (exclusive).
  final int baseEnd;

  /// The replacement lines in the modified version.
  final List<String> lines;

  @override
  String toString() => '_Hunk([$baseStart, $baseEnd), lines: $lines)';
}

/// A line-level 3-way merge and conflict resolution engine.
class ConflictResolver {
  ConflictResolver._();

  /// Resolves changes between [base], [local], and [remote] versions of a note.
  ///
  /// - If [base] is `null` (new file on both sides with same filename), returns [ConflictDetected].
  /// - If [local] == [remote], returns [AlreadyInSync].
  /// - If [local] == [base], returns [FastForwardPull] with [remote].
  /// - If [remote] == [base], returns [FastForwardPush] with [local].
  /// - Otherwise, attempts a line-level 3-way merge via [_threeWayMerge].
  static MergeResult resolve({
    required String? base,
    required String local,
    required String remote,
  }) {
    if (base == null) {
      return ConflictDetected(
        localContent: local,
        remoteContent: remote,
        partialMerge: null,
      );
    }

    if (local == remote) {
      return const AlreadyInSync();
    }

    if (local == base) {
      return FastForwardPull(remote);
    }

    if (remote == base) {
      return FastForwardPush(local);
    }

    return _threeWayMerge(base, local, remote);
  }

  /// Generates a conflict backup filename on the laptop (e.g. note.conflict-1699999999.md).
  static String generateConflictFilename(String filename) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    if (filename.endsWith('.md')) {
      final base = filename.substring(0, filename.length - 3);
      return '$base.conflict-$timestamp.md';
    }
    return '$filename.conflict-$timestamp.md';
  }

  /// Internal 3-way line merge implementation.
  static MergeResult _threeWayMerge(
    String base,
    String local,
    String remote,
  ) {
    final baseLines = _splitLines(base);
    final localLines = _splitLines(local);
    final remoteLines = _splitLines(remote);

    final localEdits = _computeEdits(baseLines, localLines);
    final remoteEdits = _computeEdits(baseLines, remoteLines);

    final localHunks = _extractHunks(localEdits, baseLines.length);
    final remoteHunks = _extractHunks(remoteEdits, baseLines.length);

    final hasTrailingNewline =
        base.endsWith('\n') || local.endsWith('\n') || remote.endsWith('\n');

    return _mergeHunks(
      baseLines: baseLines,
      localHunks: localHunks,
      remoteHunks: remoteHunks,
      localRaw: local,
      remoteRaw: remote,
      hasTrailingNewline: hasTrailingNewline,
    );
  }

  /// Computes the Longest Common Subsequence of lines between [a] and [b].
  static List<String> _lcs(List<String> a, List<String> b) {
    final m = a.length;
    final n = b.length;
    if (m == 0 || n == 0) return const [];

    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = max(dp[i - 1][j], dp[i][j - 1]);
        }
      }
    }

    var i = m;
    var j = n;
    final result = <String>[];
    while (i > 0 && j > 0) {
      if (a[i - 1] == b[j - 1]) {
        result.add(a[i - 1]);
        i--;
        j--;
      } else if (dp[i - 1][j] >= dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }

    return result.reversed.toList();
  }

  /// Computes line-level edit operations (keep, insert, delete) transforming [from] into [to].
  static List<EditOp> _computeEdits(List<String> from, List<String> to) {
    if (from.isEmpty || to.isEmpty || _lcs(from, to).isEmpty) {
      final ops = <EditOp>[];
      for (var i = 0; i < from.length; i++) {
        ops.add(EditOp(
          type: EditType.delete,
          fromIndex: i,
          toIndex: -1,
          text: from[i],
        ));
      }
      for (var j = 0; j < to.length; j++) {
        ops.add(EditOp(
          type: EditType.insert,
          fromIndex: -1,
          toIndex: j,
          text: to[j],
        ));
      }
      return ops;
    }

    final m = from.length;
    final n = to.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        if (from[i - 1] == to[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = max(dp[i - 1][j], dp[i][j - 1]);
        }
      }
    }

    var i = m;
    var j = n;
    final reversedOps = <EditOp>[];

    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && from[i - 1] == to[j - 1]) {
        reversedOps.add(EditOp(
          type: EditType.keep,
          fromIndex: i - 1,
          toIndex: j - 1,
          text: from[i - 1],
        ));
        i--;
        j--;
      } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
        reversedOps.add(EditOp(
          type: EditType.insert,
          fromIndex: -1,
          toIndex: j - 1,
          text: to[j - 1],
        ));
        j--;
      } else {
        reversedOps.add(EditOp(
          type: EditType.delete,
          fromIndex: i - 1,
          toIndex: -1,
          text: from[i - 1],
        ));
        i--;
      }
    }

    return reversedOps.reversed.toList();
  }

  /// Converts a sequence of [EditOp]s into contiguous diff hunks relative to base lines.
  static List<_Hunk> _extractHunks(List<EditOp> edits, int baseLength) {
    final hunks = <_Hunk>[];
    var currentBaseIndex = 0;
    var i = 0;

    while (i < edits.length) {
      if (edits[i].type == EditType.keep) {
        currentBaseIndex = edits[i].fromIndex + 1;
        i++;
        continue;
      }

      final hunkStart = currentBaseIndex;
      final replacementLines = <String>[];

      while (i < edits.length && edits[i].type != EditType.keep) {
        if (edits[i].type == EditType.insert) {
          replacementLines.add(edits[i].text);
        }
        i++;
      }

      final nextBaseIndex =
          (i < edits.length) ? edits[i].fromIndex : baseLength;

      hunks.add(_Hunk(
        baseStart: hunkStart,
        baseEnd: nextBaseIndex,
        lines: replacementLines,
      ));

      currentBaseIndex = nextBaseIndex;
    }

    return hunks;
  }

  /// Walks base lines and merges non-overlapping hunks from local and remote.
  static MergeResult _mergeHunks({
    required List<String> baseLines,
    required List<_Hunk> localHunks,
    required List<_Hunk> remoteHunks,
    required String localRaw,
    required String remoteRaw,
    required bool hasTrailingNewline,
  }) {
    var localIdx = 0;
    var remoteIdx = 0;
    var currentBase = 0;
    final mergedLines = <String>[];
    final partialLines = <String>[];
    var hasConflict = false;

    while (localIdx < localHunks.length || remoteIdx < remoteHunks.length) {
      final nextLocal =
          localIdx < localHunks.length ? localHunks[localIdx] : null;
      final nextRemote =
          remoteIdx < remoteHunks.length ? remoteHunks[remoteIdx] : null;

      int earliestStart;
      if (nextLocal != null && nextRemote != null) {
        earliestStart = min(nextLocal.baseStart, nextRemote.baseStart);
      } else if (nextLocal != null) {
        earliestStart = nextLocal.baseStart;
      } else {
        earliestStart = nextRemote!.baseStart;
      }

      // Preserve base lines before the earliest hunk
      for (var k = currentBase; k < earliestStart; k++) {
        mergedLines.add(baseLines[k]);
        partialLines.add(baseLines[k]);
      }
      currentBase = earliestStart;

      // Group overlapping hunks into a single cluster
      final clusterStart = earliestStart;
      var clusterEnd = clusterStart;

      final localCluster = <_Hunk>[];
      final remoteCluster = <_Hunk>[];

      while (true) {
        var expanded = false;

        if (localIdx < localHunks.length) {
          final h = localHunks[localIdx];
          final belongs = (h.baseStart < clusterEnd) ||
              (localCluster.isEmpty &&
                  remoteCluster.isEmpty &&
                  h.baseStart == clusterStart) ||
              (clusterStart == clusterEnd &&
                  h.baseStart == clusterStart &&
                  h.baseEnd == clusterEnd);
          if (belongs) {
            localCluster.add(h);
            if (h.baseEnd > clusterEnd) {
              clusterEnd = h.baseEnd;
            }
            localIdx++;
            expanded = true;
          }
        }

        if (remoteIdx < remoteHunks.length) {
          final h = remoteHunks[remoteIdx];
          final belongs = (h.baseStart < clusterEnd) ||
              (localCluster.isEmpty &&
                  remoteCluster.isEmpty &&
                  h.baseStart == clusterStart) ||
              (clusterStart == clusterEnd &&
                  h.baseStart == clusterStart &&
                  h.baseEnd == clusterEnd);
          if (belongs) {
            remoteCluster.add(h);
            if (h.baseEnd > clusterEnd) {
              clusterEnd = h.baseEnd;
            }
            remoteIdx++;
            expanded = true;
          }
        }

        if (!expanded) break;
      }

      final clusterLocalLines = _reconstructCluster(
        baseLines,
        clusterStart,
        clusterEnd,
        localCluster,
      );
      final clusterRemoteLines = _reconstructCluster(
        baseLines,
        clusterStart,
        clusterEnd,
        remoteCluster,
      );

      if (localCluster.isEmpty) {
        mergedLines.addAll(clusterRemoteLines);
        partialLines.addAll(clusterRemoteLines);
      } else if (remoteCluster.isEmpty) {
        mergedLines.addAll(clusterLocalLines);
        partialLines.addAll(clusterLocalLines);
      } else {
        if (_listEquals(clusterLocalLines, clusterRemoteLines)) {
          mergedLines.addAll(clusterLocalLines);
          partialLines.addAll(clusterLocalLines);
        } else if (clusterStart >= baseLines.length &&
            clusterEnd >= baseLines.length) {
          // Both sides appended text at the end of the file
          mergedLines.addAll(clusterLocalLines);
          mergedLines.addAll(clusterRemoteLines);
          partialLines.addAll(clusterLocalLines);
          partialLines.addAll(clusterRemoteLines);
        } else {
          // Conflicting edits
          hasConflict = true;
          partialLines.add('<<<<<<< local');
          partialLines.addAll(clusterLocalLines);
          partialLines.add('=======');
          partialLines.addAll(clusterRemoteLines);
          partialLines.add('>>>>>>> remote');
        }
      }

      currentBase = clusterEnd;
    }

    // Preserve any remaining base lines after the last hunk
    for (var k = currentBase; k < baseLines.length; k++) {
      mergedLines.add(baseLines[k]);
      partialLines.add(baseLines[k]);
    }

    if (hasConflict) {
      final partialMerge = _joinLines(partialLines, hasTrailingNewline);
      return ConflictDetected(
        localContent: localRaw,
        remoteContent: remoteRaw,
        partialMerge: partialMerge,
      );
    }

    final mergedContent = _joinLines(mergedLines, hasTrailingNewline);
    return AutoMerged(mergedContent);
  }

  /// Reconstructs lines within `[start, end)` applying [hunks].
  static List<String> _reconstructCluster(
    List<String> baseLines,
    int start,
    int end,
    List<_Hunk> hunks,
  ) {
    final result = <String>[];
    var pos = start;
    for (final h in hunks) {
      for (var k = pos; k < h.baseStart; k++) {
        if (k < baseLines.length) {
          result.add(baseLines[k]);
        }
      }
      result.addAll(h.lines);
      pos = h.baseEnd;
    }
    for (var k = pos; k < end; k++) {
      if (k < baseLines.length) {
        result.add(baseLines[k]);
      }
    }
    return result;
  }

  /// Splits text into lines, handling both CRLF and LF line endings.
  static List<String> _splitLines(String text) {
    if (text.isEmpty) return const [];
    var s = text;
    if (s.endsWith('\r\n')) {
      s = s.substring(0, s.length - 2);
    } else if (s.endsWith('\n')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) return const [''];
    return s.split(RegExp(r'\r?\n'));
  }

  /// Joins lines back with newline delimiters, respecting trailing newline.
  static String _joinLines(List<String> lines, bool trailingNewline) {
    if (lines.isEmpty) return '';
    final joined = lines.join('\n');
    return trailingNewline ? '$joined\n' : joined;
  }

  /// Compares two lists of strings for equality.
  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
