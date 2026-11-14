import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/screens/conflict_diff_screen.dart';
import 'package:sticky_notes_ssh/screens/note_editor_screen.dart';
import 'package:sticky_notes_ssh/screens/ssh_settings_screen.dart';
import 'package:sticky_notes_ssh/view_models/home_view_model.dart';
import 'package:sticky_notes_ssh/widgets/sticky_card.dart';
import 'package:sticky_notes_ssh/widgets/sync_status_pill.dart';

/// Main home screen displaying the search bar, tag filters, connection status,
/// and a Google Keep-style staggered grid of pinned and unpinned sticky notes.
class HomeScreen extends StatefulWidget {
  /// Creates a [HomeScreen].
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _searchController;
  late final AnimationController _syncAnimationController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _syncAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<HomeViewModel>();
      vm.loadNotes();
      vm.initConnectivityListener();
      vm.checkAndAutoSync();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _syncAnimationController.dispose();
    super.dispose();
  }

  Future<void> _navigateToEditor({String? noteId}) async {
    final viewModel = context.read<HomeViewModel>();
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NoteEditorScreen(noteId: noteId),
      ),
    );
    if (mounted) {
      await viewModel.loadNotes();
      await viewModel.checkAndAutoSync();
    }
  }

  void _showNoteContextMenu(StickyNote note) {
    final viewModel = context.read<HomeViewModel>();

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        final isConflict = note.syncStatus == SyncStatus.conflict;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          note.title.trim().isNotEmpty
                              ? note.title
                              : note.filename,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    note.isPinned
                        ? Icons.push_pin_outlined
                        : Icons.push_pin_rounded,
                  ),
                  title: Text(note.isPinned ? 'Unpin note' : 'Pin note'),
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    viewModel.togglePin(note.id);
                  },
                ),
                if (isConflict)
                  ListTile(
                    leading: const Icon(
                      Icons.merge_type_rounded,
                      color: Color(0xFFC62828),
                    ),
                    title: const Text(
                      'Resolve conflict',
                      style: TextStyle(
                        color: Color(0xFFC62828),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(bottomSheetContext);
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ConflictDiffScreen(note: note),
                        ),
                      );
                      if (mounted) {
                        viewModel.loadNotes();
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('Share'),
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    final shareText = note.title.trim().isNotEmpty
                        ? '${note.title}\n\n${note.content}'
                        : note.content;
                    Share.share(
                      shareText,
                      subject: note.title.isNotEmpty ? note.title : null,
                    );
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Delete note',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _confirmDelete(note);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDelete(StickyNote note) {
    final viewModel = context.read<HomeViewModel>();
    final displayTitle =
        note.title.trim().isNotEmpty ? note.title.trim() : note.filename;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Delete "$displayTitle"?'),
          content: const Text(
            'Are you sure you want to delete this note? It will be removed from your phone and your laptop on the next sync.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                viewModel.deleteNote(note.id);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewModel = context.watch<HomeViewModel>();

    if (viewModel.syncState == SyncState.syncing) {
      if (!_syncAnimationController.isAnimating) {
        _syncAnimationController.repeat();
      }
    } else {
      if (_syncAnimationController.isAnimating) {
        _syncAnimationController.stop();
        _syncAnimationController.reset();
      }
    }

    final hasPinned = viewModel.pinnedNotes.isNotEmpty;
    final hasUnpinned = viewModel.unpinnedNotes.isNotEmpty;
    final isEmpty = !hasPinned && !hasUnpinned;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sticky Notes'),
        actions: <Widget>[
          // Animated sync button
          IconButton(
            tooltip: 'Sync with laptop',
            onPressed: viewModel.syncState == SyncState.syncing
                ? null
                : () async {
                    final result = await viewModel.syncNow();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result.summary),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
            icon: RotationTransition(
              turns: _syncAnimationController,
              child: const Icon(Icons.sync_rounded),
            ),
          ),
          // Settings gear icon
          IconButton(
            tooltip: 'SSH Settings',
            onPressed: () async {
              final vm = context.read<HomeViewModel>();
              await Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const SshSettingsScreen(),
                ),
              );
              if (mounted) {
                await vm.loadNotes();
                await vm.checkAndAutoSync();
              }
            },
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Create new note',
        onPressed: () => _navigateToEditor(noteId: null),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: <Widget>[
          // Sync status pill header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: <Widget>[
                SyncStatusPill(
                  state: viewModel.syncState,
                  onTap: () => viewModel.syncNow(),
                ),
                if (viewModel.hasConflicts) ...<Widget>[
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: 'Resolve conflicting notes',
                    child: Tooltip(
                      message: 'Resolve conflicts',
                      child: InkWell(
                        onTap: () {
                          final conflictNote = viewModel.notes.firstWhere(
                            (StickyNote n) => n.syncStatus == SyncStatus.conflict,
                          );
                          Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ConflictDiffScreen(note: conflictNote),
                            ),
                          ).then((_) => viewModel.loadNotes());
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 36),
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: theme.brightness == Brightness.dark
                                  ? const Color(0xFF3F1719)
                                  : const Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: theme.brightness == Brightness.dark
                                    ? const Color(0xFFC62828)
                                    : const Color(0xFFEF9A9A),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 14,
                                  color: theme.brightness == Brightness.dark
                                      ? const Color(0xFFEF9A9A)
                                      : const Color(0xFFC62828),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Resolve Conflicts',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: theme.brightness == Brightness.dark
                                        ? const Color(0xFFEF9A9A)
                                        : const Color(0xFFC62828),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search notes...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          viewModel.setSearchQuery('');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.45),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              onChanged: viewModel.setSearchQuery,
            ),
          ),

          // Tag filter chips
          if (viewModel.allTags.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: <Widget>[
                  FilterChip(
                    label: const Text('All'),
                    selected: viewModel.activeTag == null,
                    onSelected: (bool selected) {
                      if (selected) {
                        viewModel.setActiveTag(null);
                      }
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 6),
                  ...viewModel.allTags.map((String tag) {
                    final isSelected = viewModel.activeTag == tag;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text('#$tag'),
                        selected: isSelected,
                        onSelected: (bool selected) {
                          viewModel.setActiveTag(selected ? tag : null);
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }),
                ],
              ),
            ),

          // Notes list / grid / empty state
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await viewModel.syncNow();
              },
              child: isEmpty
                  ? _buildEmptyState(viewModel)
                  : CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: <Widget>[
                        // Pinned notes section
                        if (hasPinned) ...<Widget>[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                              child: Semantics(
                                header: true,
                                child: Text(
                                  'PINNED',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            sliver: SliverMasonryGrid.count(
                              crossAxisCount: 2,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childCount: viewModel.pinnedNotes.length,
                              itemBuilder: (context, index) {
                                final note = viewModel.pinnedNotes[index];
                                return StickyCard(
                                  note: note,
                                  onTap: () => _navigateToEditor(noteId: note.id),
                                  onCheckboxToggle: (int lineIndex) {
                                    viewModel.toggleCheckbox(note.id, lineIndex);
                                  },
                                  onLongPress: () => _showNoteContextMenu(note),
                                );
                              },
                            ),
                          ),
                        ],

                        // Notes section
                        if (hasUnpinned) ...<Widget>[
                          if (hasPinned)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                                child: Semantics(
                                  header: true,
                                  child: Text(
                                    'OTHERS',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          SliverPadding(
                            padding: const EdgeInsets.all(12),
                            sliver: SliverMasonryGrid.count(
                              crossAxisCount: 2,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childCount: viewModel.unpinnedNotes.length,
                              itemBuilder: (context, index) {
                                final note = viewModel.unpinnedNotes[index];
                                return StickyCard(
                                  note: note,
                                  onTap: () => _navigateToEditor(noteId: note.id),
                                  onCheckboxToggle: (int lineIndex) {
                                    viewModel.toggleCheckbox(note.id, lineIndex);
                                  },
                                  onLongPress: () => _showNoteContextMenu(note),
                                );
                              },
                            ),
                          ),
                        ],

                        const SliverToBoxAdapter(
                          child: SizedBox(height: 80),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(HomeViewModel viewModel) {
    final theme = Theme.of(context);
    final isSearching = viewModel.searchQuery.isNotEmpty ||
        viewModel.activeTag != null;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        const SizedBox(height: 120),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                isSearching
                    ? Icons.search_off_rounded
                    : Icons.note_alt_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Text(
                isSearching
                    ? 'No notes match your filter.'
                    : 'No notes yet. Tap + to create one.',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
