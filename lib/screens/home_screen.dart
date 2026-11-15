import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sticky_notes_ssh/models/home_background.dart';
import 'package:sticky_notes_ssh/models/ssh_profile.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/screens/conflict_diff_screen.dart';
import 'package:sticky_notes_ssh/screens/note_editor_screen.dart';
import 'package:sticky_notes_ssh/screens/ssh_settings_screen.dart';
import 'package:sticky_notes_ssh/view_models/home_view_model.dart';
import 'package:sticky_notes_ssh/widgets/background_picker_sheet.dart';
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TextEditingController _searchController;
  late final AnimationController _syncAnimationController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final vm = context.read<HomeViewModel>();
    if (state == AppLifecycleState.resumed) {
      vm.checkAndAutoSync();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      vm.stopRemoteWatcher();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _syncAnimationController.dispose();
    super.dispose();
  }

  Future<void> _navigateToEditor({String? noteId}) async {
    final viewModel = context.read<HomeViewModel>();
    final didChange = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => NoteEditorScreen(
          noteId: noteId,
          profileId: viewModel.activeProfileId,
          remotePath: viewModel.activeRemotePath,
        ),
      ),
    );
    if (mounted && (didChange == true)) {
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
    final bgDecoration =
        _buildBackgroundDecoration(viewModel.background, theme);
    final isCustomBg = bgDecoration != null;

    return Scaffold(
      backgroundColor: isCustomBg ? Colors.transparent : null,
      appBar: AppBar(
        backgroundColor: isCustomBg ? Colors.transparent : null,
        elevation: isCustomBg ? 0 : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/app_logo.png',
                width: 30,
                height: 30,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Sticky Notes'),
          ],
        ),
        actions: <Widget>[
          // View mode toggle (Grid vs Markdown Reader)
          IconButton(
            tooltip: viewModel.isGridView
                ? 'Markdown Reader View'
                : 'Grid View',
            onPressed: () => viewModel.toggleViewMode(),
            icon: Icon(
              viewModel.isGridView
                  ? Icons.view_agenda_outlined
                  : Icons.grid_view_rounded,
            ),
          ),
          // Customize background button
          IconButton(
            tooltip: 'Customize background',
            onPressed: () {
              BackgroundPickerSheet.show(
                context: context,
                currentBackground: viewModel.background,
                onBackgroundChanged: (newBg) => viewModel.setBackground(newBg),
                onPickGalleryImage: () => viewModel.pickAndSetGalleryImage(),
              );
            },
            icon: const Icon(Icons.palette_outlined),
          ),
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
              await Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const SshSettingsScreen(),
                ),
              );
              if (context.mounted) {
                await viewModel.loadNotes();
                await viewModel.checkAndAutoSync();
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
      body: Container(
        decoration: bgDecoration,
        child: Column(
        children: <Widget>[
          // Sync status and machine selector pill header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: <Widget>[
                _buildActiveMachineChip(context, viewModel, theme),
                const SizedBox(width: 8),
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
                              crossAxisCount: viewModel.isGridView ? 2 : 1,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childCount: viewModel.pinnedNotes.length,
                              itemBuilder: (context, index) {
                                final note = viewModel.pinnedNotes[index];
                                return StickyCard(
                                  note: note,
                                  isCompact: viewModel.isGridView,
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
                              crossAxisCount: viewModel.isGridView ? 2 : 1,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childCount: viewModel.unpinnedNotes.length,
                              itemBuilder: (context, index) {
                                final note = viewModel.unpinnedNotes[index];
                                return StickyCard(
                                  note: note,
                                  isCompact: viewModel.isGridView,
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

  Widget _buildActiveMachineChip(
    BuildContext context,
    HomeViewModel viewModel,
    ThemeData theme,
  ) {
    final active = viewModel.activeProfile;
    final String label;
    if (active == null) {
      label = 'No Machine';
    } else if (viewModel.activeRemotePath != null &&
        viewModel.activeRemotePath!.isNotEmpty) {
      final base = p.basename(viewModel.activeRemotePath!);
      final dirLabel = base.isNotEmpty ? base : viewModel.activeRemotePath!;
      label = '${active.name} ($dirLabel)';
    } else {
      label = active.name;
    }

    return InkWell(
      onTap: () => _showMachineSwitcherSheet(context, viewModel),
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.computer_rounded,
                size: 15,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMachineSwitcherSheet(BuildContext context, HomeViewModel viewModel) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final entries = <_MachineLocationItem>[];
        for (final profile in viewModel.availableProfiles) {
          final paths = profile.allRemotePaths;
          for (final path in paths) {
            final isCurrentActive = profile.id == viewModel.activeProfileId &&
                (viewModel.activeRemotePath == null
                    ? path == paths.first
                    : viewModel.activeRemotePath == path);
            entries.add(
              _MachineLocationItem(
                profile: profile,
                locationPath: path,
                isActive: isCurrentActive,
              ),
            );
          }
        }

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Expanded(
                            child: Text(
                              'Active SSH Machine & Directory',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '1 ACTIVE AT A TIME',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Each directory across every profile is listed independently below with its own switch. All compartments remain fully accessible offline.',
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No SSH machines configured yet.',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = entries[index];
                        final isFile = item.locationPath.endsWith('.md');

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          leading: Icon(
                            isFile
                                ? Icons.description_outlined
                                : Icons.folder_outlined,
                            color: item.isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                          ),
                          title: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  '${item.profile.name} (${item.locationPath})',
                                  style: TextStyle(
                                    fontWeight: item.isActive
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 14,
                                    color: item.isActive
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              if (item.isActive) ...<Widget>[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            '${item.profile.username}@${item.profile.host}:${item.profile.port} • ${isFile ? 'Markdown File' : 'Directory'}',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: Semantics(
                            label: 'Activate ${item.profile.name} ${item.locationPath}',
                            child: Switch(
                              value: item.isActive,
                              onChanged: (bool val) {
                                if (val) {
                                  Navigator.pop(sheetContext);
                                  viewModel.switchActiveProfileAndLocation(
                                    item.profile.id,
                                    item.locationPath,
                                  );
                                }
                              },
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            viewModel.switchActiveProfileAndLocation(
                              item.profile.id,
                              item.locationPath,
                            );
                          },
                        );
                      },
                    ),
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.settings_suggest_outlined),
                  title: const Text('Manage Machines & Locations'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const SshSettingsScreen(),
                      ),
                    ).then((_) {
                      if (context.mounted) {
                        viewModel.loadNotes();
                      }
                    });
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  BoxDecoration? _buildBackgroundDecoration(
    HomeBackground bg,
    ThemeData theme,
  ) {
    switch (bg.type) {
      case HomeBackgroundType.defaultTheme:
        return null;
      case HomeBackgroundType.color:
        if (bg.colorValue == null) return null;
        return BoxDecoration(color: Color(bg.colorValue!));
      case HomeBackgroundType.gradient:
        final preset = bg.activeGradient;
        if (preset == null) return null;
        return BoxDecoration(
          gradient: LinearGradient(
            colors: preset.colors,
            begin: preset.begin,
            end: preset.end,
          ),
        );
      case HomeBackgroundType.image:
        if (bg.imagePath == null) return null;
        final file = File(bg.imagePath!);
        if (!file.existsSync()) return null;
        return BoxDecoration(
          image: DecorationImage(
            image: FileImage(file),
            fit: BoxFit.cover,
            colorFilter: bg.overlayOpacity > 0
                ? ColorFilter.mode(
                    Colors.black.withValues(alpha: bg.overlayOpacity),
                    BlendMode.darken,
                  )
                : null,
          ),
        );
    }
  }
}

class _MachineLocationItem {
  const _MachineLocationItem({
    required this.profile,
    required this.locationPath,
    required this.isActive,
  });

  final SshProfile profile;
  final String locationPath;
  final bool isActive;
}
