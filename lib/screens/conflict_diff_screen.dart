import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/screens/note_editor_screen.dart';
import 'package:sticky_notes_ssh/services/local_db_service.dart';
import 'package:sticky_notes_ssh/widgets/diff_line_widget.dart';

/// Represents a single computed line inside a line-level diff comparison.
class DiffLine {
  /// Creates a [DiffLine].
  const DiffLine({
    required this.text,
    required this.type,
  });

  /// Text content of the line.
  final String text;

  /// Diff line classification.
  final DiffLineType type;
}

/// Represents an aligned pair of diff lines for side-by-side comparison.
class SideBySidePair {
  /// Creates a [SideBySidePair].
  const SideBySidePair({
    this.phoneLine,
    this.laptopLine,
  });

  /// The line on the phone side, or `null` if added on laptop.
  final DiffLine? phoneLine;

  /// The line on the laptop side, or `null` if deleted on phone.
  final DiffLine? laptopLine;
}

/// Screen allowing side-by-side and unified diff inspection of conflicting note edits,
/// with one-tap conflict resolution options.
class ConflictDiffScreen extends StatefulWidget {
  /// Creates a [ConflictDiffScreen].
  const ConflictDiffScreen({
    super.key,
    required this.note,
  });

  /// The conflicting sticky note.
  final StickyNote note;

  @override
  State<ConflictDiffScreen> createState() => _ConflictDiffScreenState();
}

class _ConflictDiffScreenState extends State<ConflictDiffScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final LocalDbService _localDbService = LocalDbService();

  late final List<DiffLine> _unifiedDiff;
  late final List<SideBySidePair> _sideBySidePairs;
  bool _isResolving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final localContent = widget.note.content;
    final remoteContent = widget.note.conflictRemoteContent ?? '';

    _unifiedDiff = _computeDiff(localContent, remoteContent);
    _sideBySidePairs = _computeSideBySidePairs(_unifiedDiff);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Computes a line-by-line diff between [local] and [remote] strings using LCS.
  List<DiffLine> _computeDiff(String local, String remote) {
    final localLines = local.isEmpty ? <String>[] : local.split('\n');
    final remoteLines = remote.isEmpty ? <String>[] : remote.split('\n');

    final n = localLines.length;
    final m = remoteLines.length;

    // Build Longest Common Subsequence DP table
    final dp = List<List<int>>.generate(
      n + 1,
      (_) => List<int>.filled(m + 1, 0),
    );

    for (var i = 0; i < n; i++) {
      for (var j = 0; j < m; j++) {
        if (localLines[i] == remoteLines[j]) {
          dp[i + 1][j + 1] = dp[i][j] + 1;
        } else {
          dp[i + 1][j + 1] = math.max(dp[i + 1][j], dp[i][j + 1]);
        }
      }
    }

    // Backtrack to assemble unified diff list
    final reversedResult = <DiffLine>[];
    var i = n;
    var j = m;

    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && localLines[i - 1] == remoteLines[j - 1]) {
        reversedResult.add(
          DiffLine(text: localLines[i - 1], type: DiffLineType.unchanged),
        );
        i--;
        j--;
      } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
        reversedResult.add(
          DiffLine(text: remoteLines[j - 1], type: DiffLineType.added),
        );
        j--;
      } else if (i > 0 && (j == 0 || dp[i][j - 1] < dp[i - 1][j])) {
        reversedResult.add(
          DiffLine(text: localLines[i - 1], type: DiffLineType.removed),
        );
        i--;
      }
    }

    return reversedResult.reversed.toList();
  }

  /// Converts unified diff lines into aligned pairs for side-by-side rendering.
  List<SideBySidePair> _computeSideBySidePairs(List<DiffLine> diff) {
    final pairs = <SideBySidePair>[];

    for (final line in diff) {
      switch (line.type) {
        case DiffLineType.unchanged:
          pairs.add(
            SideBySidePair(
              phoneLine: line,
              laptopLine: line,
            ),
          );
        case DiffLineType.removed:
          pairs.add(
            SideBySidePair(
              phoneLine: line,
              laptopLine: null,
            ),
          );
        case DiffLineType.added:
          // Check if previous pair had a removed line without a laptop line to align changes
          if (pairs.isNotEmpty &&
              pairs.last.phoneLine != null &&
              pairs.last.phoneLine!.type == DiffLineType.removed &&
              pairs.last.laptopLine == null) {
            final last = pairs.removeLast();
            pairs.add(
              SideBySidePair(
                phoneLine: last.phoneLine,
                laptopLine: line,
              ),
            );
          } else {
            pairs.add(
              SideBySidePair(
                phoneLine: null,
                laptopLine: line,
              ),
            );
          }
        case DiffLineType.header:
          pairs.add(
            SideBySidePair(
              phoneLine: line,
              laptopLine: line,
            ),
          );
      }
    }

    return pairs;
  }

  /// Resolves the conflict by persisting [winningContent] to SQLite and local disk.
  Future<void> _resolveConflict(
    String winningContent, {
    bool openEditor = false,
  }) async {
    if (_isResolving) return;

    setState(() {
      _isResolving = true;
    });

    try {
      final updatedNote = widget.note.copyWith(
        content: winningContent,
        syncStatus: SyncStatus.pending,
        clearConflict: true,
        updatedAt: DateTime.now(),
      );

      await _localDbService.updateNote(updatedNote);
      await _localDbService.writeLocalFile(widget.note.filename, winningContent);

      if (!mounted) return;

      if (openEditor) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => NoteEditorScreen(noteId: widget.note.id),
          ),
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to resolve conflict: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResolving = false;
        });
      }
    }
  }

  void _onKeepPhone() {
    _resolveConflict(widget.note.content);
  }

  void _onKeepLaptop() {
    final remoteContent = widget.note.conflictRemoteContent ?? '';
    _resolveConflict(remoteContent);
  }

  void _onKeepBoth() {
    final local = widget.note.content;
    final remote = widget.note.conflictRemoteContent ?? '';
    final concatenated = '$local\n\n'
        '<!-- ============================================== -->\n'
        '<!-- Laptop Version:                                -->\n'
        '<!-- ============================================== -->\n\n'
        '$remote';
    _resolveConflict(concatenated);
  }

  void _onEditMerged() {
    final local = widget.note.content;
    final remote = widget.note.conflictRemoteContent ?? '';
    final concatenated = '$local\n\n'
        '<!-- ============================================== -->\n'
        '<!-- Laptop Version:                                -->\n'
        '<!-- ============================================== -->\n\n'
        '$remote';
    _resolveConflict(concatenated, openEditor: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Resolve Conflict',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.note.filename,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Widget>[
            Tab(text: 'Side by Side'),
            Tab(text: 'Unified'),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          if (_isResolving) const LinearProgressIndicator(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: <Widget>[
                _buildSideBySideView(theme),
                _buildUnifiedView(theme),
              ],
            ),
          ),
          _buildResolutionBottomBar(theme),
        ],
      ),
    );
  }

  Widget _buildSideBySideView(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final phoneColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0);
    final laptopColor = isDark ? const Color(0xFFFFB74D) : const Color(0xFFD84315);

    return Column(
      children: <Widget>[
        // Column headers
        Container(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    Icon(Icons.phone_android, size: 16, color: phoneColor),
                    const SizedBox(width: 6),
                    Text(
                      'Phone Version',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: phoneColor,
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 8),
                    Icon(Icons.laptop, size: 16, color: laptopColor),
                    const SizedBox(width: 6),
                    Text(
                      'Laptop Version',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: laptopColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Side by side scrollable rows
        Expanded(
          child: _sideBySidePairs.isEmpty
              ? const Center(child: Text('Both versions are empty.'))
              : ListView.builder(
                  itemCount: _sideBySidePairs.length,
                  itemBuilder: (context, index) {
                    final pair = _sideBySidePairs[index];
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(
                            child: pair.phoneLine != null
                                ? DiffLineWidget(
                                    text: pair.phoneLine!.text,
                                    type: pair.phoneLine!.type,
                                  )
                                : ColoredBox(
                                    color: theme.brightness == Brightness.dark
                                        ? Colors.white.withValues(alpha: 0.03)
                                        : Colors.black.withValues(alpha: 0.03),
                                    child: const SizedBox.expand(),
                                  ),
                          ),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                          ),
                          Expanded(
                            child: pair.laptopLine != null
                                ? DiffLineWidget(
                                    text: pair.laptopLine!.text,
                                    type: pair.laptopLine!.type,
                                  )
                                : ColoredBox(
                                    color: theme.brightness == Brightness.dark
                                        ? Colors.white.withValues(alpha: 0.03)
                                        : Colors.black.withValues(alpha: 0.03),
                                    child: const SizedBox.expand(),
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildUnifiedView(ThemeData theme) {
    if (_unifiedDiff.isEmpty) {
      return const Center(child: Text('Both versions are empty.'));
    }

    return ListView.builder(
      itemCount: _unifiedDiff.length,
      itemBuilder: (context, index) {
        final line = _unifiedDiff[index];
        return DiffLineWidget(
          text: line.text,
          type: line.type,
        );
      },
    );
  }

  Widget _buildResolutionBottomBar(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              // Keep Phone button
              Tooltip(
                message: 'Keep phone version and overwrite laptop',
                child: OutlinedButton.icon(
                  onPressed: _isResolving ? null : _onKeepPhone,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.brightness == Brightness.dark
                        ? const Color(0xFF64B5F6)
                        : const Color(0xFF1565C0),
                    side: BorderSide(
                      color: theme.brightness == Brightness.dark
                          ? const Color(0xFF64B5F6)
                          : const Color(0xFF1565C0),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.phone_android, size: 16),
                  label: const Text('Keep Phone'),
                ),
              ),
              const SizedBox(width: 8),

              // Keep Laptop button
              Tooltip(
                message: 'Keep laptop version and overwrite phone',
                child: OutlinedButton.icon(
                  onPressed: _isResolving ? null : _onKeepLaptop,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.brightness == Brightness.dark
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFFD84315),
                    side: BorderSide(
                      color: theme.brightness == Brightness.dark
                          ? const Color(0xFFFFB74D)
                          : const Color(0xFFD84315),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.laptop, size: 16),
                  label: const Text('Keep Laptop'),
                ),
              ),
              const SizedBox(width: 8),

              // Keep Both button
              Tooltip(
                message: 'Keep both phone and laptop versions sequentially',
                child: OutlinedButton.icon(
                  onPressed: _isResolving ? null : _onKeepBoth,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.call_split, size: 16),
                  label: const Text('Keep Both'),
                ),
              ),
              const SizedBox(width: 8),

              // Edit Merged button
              Tooltip(
                message: 'Open editor with merged versions to edit manually',
                child: FilledButton.icon(
                  onPressed: _isResolving ? null : _onEditMerged,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Edit Merged'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
