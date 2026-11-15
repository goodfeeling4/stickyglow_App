import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sticky_notes_ssh/models/ssh_profile.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/screens/note_editor_screen.dart';
import 'package:sticky_notes_ssh/services/secure_storage_service.dart';
import 'package:sticky_notes_ssh/utils/ssh_key_helper.dart';
import 'package:sticky_notes_ssh/view_models/settings_view_model.dart';
import 'package:uuid/uuid.dart';

/// Screen allowing configuration, reordering, creation, and connection testing
/// of prioritized SSH profiles used for laptop synchronization.
class SshSettingsScreen extends StatefulWidget {
  /// Creates an [SshSettingsScreen].
  const SshSettingsScreen({super.key});

  @override
  State<SshSettingsScreen> createState() => _SshSettingsScreenState();
}

class _SshSettingsScreenState extends State<SshSettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsViewModel>().loadProfiles();
    });
  }

  Future<void> _openProfileForm({SshProfile? existingProfile}) async {
    final viewModel = context.read<SettingsViewModel>();
    final secureStorage = SecureStorageService();

    String initialKey = '';
    if (existingProfile != null) {
      initialKey =
          (await secureStorage.getPrivateKey(existingProfile.id)) ?? '';
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        return _ProfileFormSheet(
          existingProfile: existingProfile,
          initialPrivateKey: initialKey,
          onSave: (SshProfile profile, String privateKeyPem) async {
            if (existingProfile != null) {
              await viewModel.updateProfile(
                profile,
                newPrivateKeyPem:
                    privateKeyPem.isNotEmpty ? privateKeyPem : null,
              );
            } else {
              await viewModel.addProfile(profile, privateKeyPem);
            }
          },
        );
      },
    );
  }

  void _confirmDeleteProfile(SshProfile profile) {
    final viewModel = context.read<SettingsViewModel>();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Delete "${profile.name}"?'),
          content: Text(
            'Are you sure you want to delete profile "${profile.name}" (${profile.host}:${profile.port})?',
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
                viewModel.deleteProfile(profile.id);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _testProfile(SshProfile profile) async {
    final viewModel = context.read<SettingsViewModel>();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Consumer<SettingsViewModel>(
          builder: (context, vm, child) {
            return AlertDialog(
              title: Row(
                children: <Widget>[
                  if (vm.isTesting) ...<Widget>[
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      vm.isTesting
                          ? 'Testing Connection...'
                          : 'Test Results',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: vm.isTesting
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Probing ${profile.host}:${profile.port}...'),
                        const SizedBox(height: 8),
                        const Text(
                          'Checking SSH credentials and Git repository on laptop.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Text(
                        vm.testResult ?? 'No diagnostic output returned.',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ),
              actions: <Widget>[
                if (!vm.isTesting)
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close'),
                  ),
              ],
            );
          },
        );
      },
    );

    await viewModel.testConnection(profile);
  }

  Future<void> _startSshCopyIdForProfile(SshProfile profile) async {
    final pem = await SecureStorageService().getPrivateKey(profile.id);
    if (!mounted) return;
    String privateKey = pem ?? '';
    String? publicKey = (privateKey.isNotEmpty && SshKeyHelper.isValidPrivateKey(privateKey))
        ? SshKeyHelper.extractOpenSshPublicKey(privateKey)
        : null;

    if (publicKey == null || privateKey.isEmpty || !SshKeyHelper.isValidPrivateKey(privateKey)) {
      final keypair = SshKeyHelper.generateEd25519KeyPair();
      privateKey = keypair.privateKeyPem;
      publicKey = keypair.publicKeyOpenSsh;
      await SecureStorageService().savePrivateKey(profile.id, privateKey);
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => _SshCopyIdDialog(
        host: profile.host,
        port: profile.port,
        username: profile.username,
        remoteDir: profile.remoteDir,
        publicKeyOpenSsh: publicKey!,
        privateKeyPem: privateKey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewModel = context.watch<SettingsViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH & Machine Settings'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Add Machine Profile',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _openProfileForm(),
          ),
        ],
      ),
      body: viewModel.isLoading
          ? const Center(child: CircularProgressIndicator())
          : viewModel.profiles.isEmpty
              ? _buildEmptyState()
              : _buildMainSettingsContent(context, viewModel, theme),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.terminal_rounded,
              size: 64,
              color: Colors.grey.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            const Text(
              'Add an SSH profile to sync with your laptop',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Supports local Wi-Fi LAN IP, Android Hotspot, and Tailscale VPN.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyPublicKey(SshProfile profile) async {
    final pem = await SecureStorageService().getPrivateKey(profile.id);
    if (!mounted) return;
    if (pem != null) {
      final pubKey = SshKeyHelper.extractOpenSshPublicKey(pem);
      if (pubKey != null) {
        await Clipboard.setData(ClipboardData(text: pubKey));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Copied Public Key! Append to ~/.ssh/authorized_keys on your laptop.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No key found for this profile. Edit to generate one.'),
      ),
    );
  }

  Future<void> _promptAddLocation(SshProfile profile) async {
    final viewModel = context.read<SettingsViewModel>();
    final controller = TextEditingController(text: '~/sticky-notes/');

    final result = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Add Sync Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Enter a directory path (e.g. ~/my-notes) or a specific Markdown file path (e.g. ~/notes/todo.md) on your laptop.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Remote Path',
                hintText: '~/notes or ~/notes/todo.md',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.folder_open_outlined),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await viewModel.addRemotePath(profile.id, result);
    }
  }

  Widget _buildMainSettingsContent(
    BuildContext context,
    SettingsViewModel viewModel,
    ThemeData theme,
  ) {
    final activeProfile = viewModel.activeProfile ?? viewModel.profiles.first;

    return RefreshIndicator(
      onRefresh: () => viewModel.loadProfiles(),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: <Widget>[
          // Section 1: Active Machine Selector Dropdown
          _buildMachineSelectorCard(context, viewModel, activeProfile, theme),
          const SizedBox(height: 16),

          // Section 2: Configured Sync Locations (Dirs & Files)
          _buildLocationsCard(context, viewModel, activeProfile, theme),
          const SizedBox(height: 16),

          // Section 3: Opened & Synced Files on Laptop (Isolated Compartment)
          _buildSyncedFilesCard(context, viewModel, activeProfile, theme),
          const SizedBox(height: 16),

          // Section 4: General Preferences & SSH Tools
          _buildPreferencesCard(context, viewModel, activeProfile, theme),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildMachineSelectorCard(
    BuildContext context,
    SettingsViewModel viewModel,
    SshProfile activeProfile,
    ThemeData theme,
  ) {
    return Card(
      elevation: 0.8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.computer_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'ACTIVE SSH MACHINE',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
            const SizedBox(height: 6),
            Text(
              'Strictly one machine connects at a time. The app will never automatically probe or jump to other machines.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),

            // Dropdown Menu Selector
            InputDecorator(
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                labelText: 'Select Connected Laptop / Machine',
                prefixIcon: const Icon(Icons.laptop_chromebook_rounded),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: activeProfile.id,
                  icon: const Icon(Icons.arrow_drop_down_rounded),
                  items: viewModel.profiles.map((SshProfile profile) {
                    final isCurrent = profile.id == activeProfile.id;
                    return DropdownMenuItem<String>(
                      value: profile.id,
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  profile.name,
                                  style: TextStyle(
                                    fontWeight: isCurrent
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${profile.username}@${profile.host}:${profile.port}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (isCurrent)
                            Icon(
                              Icons.check_circle_rounded,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newId) {
                    if (newId != null && newId != activeProfile.id) {
                      viewModel.setActiveProfile(newId);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Active Machine Action Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: () => _testProfile(activeProfile),
                  icon: const Icon(Icons.network_check_rounded, size: 16),
                  label: const Text('Test Connection'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _openProfileForm(existingProfile: activeProfile),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _startSshCopyIdForProfile(activeProfile),
                  icon: const Icon(Icons.bolt_rounded, size: 16),
                  label: const Text('Key Setup'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete Machine',
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmDeleteProfile(activeProfile),
                ),
              ],
            ),
            const Divider(height: 24),
            Center(
              child: TextButton.icon(
                onPressed: () => _openProfileForm(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Another Machine Profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationsCard(
    BuildContext context,
    SettingsViewModel viewModel,
    SshProfile activeProfile,
    ThemeData theme,
  ) {
    final paths = activeProfile.allRemotePaths;

    return Card(
      elevation: 0.8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.folder_copy_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'SYNC LOCATIONS (${paths.length})',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => _promptAddLocation(activeProfile),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Location'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Directories and individual .md files watched on ${activeProfile.name}. All pure markdown files in these locations are synchronized.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ...paths.map((String path) {
              final isSingleFile = path.toLowerCase().endsWith('.md');
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      isSingleFile
                          ? Icons.description_outlined
                          : Icons.folder_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            path,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            isSingleFile
                                ? 'Single Markdown File'
                                : 'Directory (Recursively scans *.md)',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (paths.length > 1)
                      IconButton(
                        tooltip: 'Remove location',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => viewModel.removeRemotePath(
                          activeProfile.id,
                          path,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncedFilesCard(
    BuildContext context,
    SettingsViewModel viewModel,
    SshProfile activeProfile,
    ThemeData theme,
  ) {
    final notes = viewModel.syncedNotes;

    return Card(
      elevation: 0.8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.menu_book_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'OPENED & SYNCED FILES (${notes.length})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'OFFLINE COMPARTMENT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Files opened and saved for ${activeProfile.name}. Even if you go offline or switch machines, notes in this compartment remain preserved and accessible.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (notes.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: <Widget>[
                    Icon(
                      Icons.note_add_outlined,
                      size: 32,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No files cached for this machine yet.',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap Sync on the home screen to pull files from your laptop.',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...notes.map((StickyNote note) {
                final displayTitle = note.title.trim().isNotEmpty
                    ? note.title.trim()
                    : note.filename;
                final statusColor = switch (note.syncStatus) {
                  SyncStatus.synced => const Color(0xFF2E7D32),
                  SyncStatus.pending => const Color(0xFFE65100),
                  SyncStatus.conflict => const Color(0xFFC62828),
                };
                final statusText = switch (note.syncStatus) {
                  SyncStatus.synced => 'SYNCED',
                  SyncStatus.pending => 'PENDING',
                  SyncStatus.conflict => 'CONFLICT',
                };

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.description_outlined,
                        size: 16,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      displayTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${note.filename} ${note.remotePath != null ? "• ${note.remotePath}" : ""}',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.push<bool>(
                        context,
                        MaterialPageRoute<bool>(
                          builder: (_) => NoteEditorScreen(
                            noteId: note.id,
                            profileId: activeProfile.id,
                          ),
                        ),
                      );
                      if (context.mounted) {
                        viewModel.refreshSyncedNotes();
                      }
                    },
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferencesCard(
    BuildContext context,
    SettingsViewModel viewModel,
    SshProfile activeProfile,
    ThemeData theme,
  ) {
    return Card(
      elevation: 0.8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'SYNC PREFERENCES',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Auto-Sync on Laptop Connect',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: const Text(
                'Syncs active machine when network connects and after editing notes.',
                style: TextStyle(fontSize: 12),
              ),
              value: viewModel.autoSyncEnabled,
              onChanged: (bool value) async {
                await viewModel.toggleAutoSync(value);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value
                          ? 'Auto-Sync enabled for ${activeProfile.name}.'
                          : 'Auto-Sync disabled.',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            const Divider(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.key_rounded),
              title: const Text(
                'Copy Active Machine Public Key',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Paste into ~/.ssh/authorized_keys on your laptop for passwordless login.',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () => _copyPublicKey(activeProfile),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileFormSheet extends StatefulWidget {
  const _ProfileFormSheet({
    this.existingProfile,
    required this.initialPrivateKey,
    required this.onSave,
  });

  final SshProfile? existingProfile;
  final String initialPrivateKey;
  final Future<void> Function(SshProfile profile, String privateKeyPem) onSave;

  @override
  State<_ProfileFormSheet> createState() => _ProfileFormSheetState();
}

class _ProfileFormSheetState extends State<_ProfileFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _remoteDirController;
  late final TextEditingController _privateKeyController;

  bool _isSaving = false;
  String? _publicKeyOpenSsh;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProfile;
    _nameController = TextEditingController(text: p?.name ?? '');
    _hostController = TextEditingController(text: p?.host ?? '');
    _portController =
        TextEditingController(text: (p?.port ?? 22).toString());
    _usernameController = TextEditingController(text: p?.username ?? '');
    _remoteDirController =
        TextEditingController(text: p?.remoteDir ?? '~/sticky-notes');
    _privateKeyController =
        TextEditingController(text: widget.initialPrivateKey);

    if (_privateKeyController.text.trim().isNotEmpty &&
        SshKeyHelper.isValidPrivateKey(_privateKeyController.text)) {
      _publicKeyOpenSsh =
          SshKeyHelper.extractOpenSshPublicKey(_privateKeyController.text);
    } else {
      // Auto-generate a secure Ed25519 keypair on the phone for new or invalid profiles!
      _generateNewKey(notify: false);
    }
  }

  void _generateNewKey({bool notify = true}) {
    final generated = SshKeyHelper.generateEd25519KeyPair();
    _privateKeyController.text = generated.privateKeyPem;
    setState(() {
      _publicKeyOpenSsh = generated.publicKeyOpenSsh;
    });
    if (notify && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generated new Ed25519 key on phone! Tap "Copy Public Key" to copy it.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _copyPublicKey() async {
    if (_publicKeyOpenSsh != null) {
      await Clipboard.setData(ClipboardData(text: _publicKeyOpenSsh!));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied Public Key! Paste into ~/.ssh/authorized_keys on your laptop.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _startSshCopyId() async {
    final host = _hostController.text.trim();
    final username = _usernameController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 22;
    final remoteDir = _remoteDirController.text.trim().isNotEmpty
        ? _remoteDirController.text.trim()
        : '~/sticky-notes';

    if (host.isEmpty || username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Host and Username before auto-setup.'),
        ),
      );
      return;
    }

    if (_publicKeyOpenSsh == null ||
        _privateKeyController.text.isEmpty ||
        !SshKeyHelper.isValidPrivateKey(_privateKeyController.text)) {
      _generateNewKey(notify: false);
    }

    final publicKey = _publicKeyOpenSsh!;
    final privateKey = _privateKeyController.text;

    final success = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => _SshCopyIdDialog(
        host: host,
        port: port,
        username: username,
        remoteDir: remoteDir,
        publicKeyOpenSsh: publicKey,
        privateKeyPem: privateKey,
      ),
    );

    if (success == true && mounted) {
      setState(() {
        _privateKeyController.text = privateKey;
        _publicKeyOpenSsh = publicKey;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SSH key successfully verified! Tap "Save Changes" to save this profile.'),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _remoteDirController.dispose();
    _privateKeyController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _privateKeyController.text = data.text!;
        _publicKeyOpenSsh = SshKeyHelper.extractOpenSshPublicKey(data.text!);
      });
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final port = int.tryParse(_portController.text.trim()) ?? 22;
      final id = widget.existingProfile?.id ?? const Uuid().v4();
      final priority = widget.existingProfile?.priority ?? 0;

      final remotePaths = widget.existingProfile?.remotePaths ??
          <String>[
            _remoteDirController.text.trim().isNotEmpty
                ? _remoteDirController.text.trim()
                : '~/sticky-notes'
          ];

      final profile = SshProfile(
        id: id,
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        port: port,
        username: _usernameController.text.trim(),
        remoteDir: _remoteDirController.text.trim().isNotEmpty
            ? _remoteDirController.text.trim()
            : '~/sticky-notes',
        remotePaths: remotePaths,
        priority: priority,
        privateKeyId: id,
      );

      await widget.onSave(profile, _privateKeyController.text.trim());

      if (mounted) {
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingProfile != null;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Sheet Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    isEdit ? 'Edit SSH Profile' : 'Add SSH Profile',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),

              // Name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Profile Name',
                  hintText: 'e.g. Home Wi-Fi, Tailscale, Hotspot',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a profile name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Host & Port Row
              Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _hostController,
                      decoration: const InputDecoration(
                        labelText: 'Host / IP',
                        hintText: '192.168.1.100',
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Host is required';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        hintText: '22',
                      ),
                      validator: (val) {
                        final p = int.tryParse(val ?? '');
                        if (p == null || p < 1 || p > 65535) {
                          return '1-65535';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Username
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'user',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Username is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Remote Directory
              TextFormField(
                controller: _remoteDirController,
                decoration: const InputDecoration(
                  labelText: 'Remote Directory',
                  hintText: '~/sticky-notes',
                ),
              ),
              const SizedBox(height: 12),

              // Public Key Card
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.key_rounded,
                              size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            "Phone's Public Key",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Copy this public key and append it to ~/.ssh/authorized_keys on your Linux laptop.',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_publicKeyOpenSsh != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: SelectableText(
                            _publicKeyOpenSsh!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                            maxLines: 3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Primary Action: Auto-Setup via ssh-copy-id
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _startSshCopyId,
                            icon: const Icon(Icons.bolt_rounded, size: 18),
                            label: const Text('Auto-Setup on Laptop (ssh-copy-id)'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _copyPublicKey,
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copy Key'),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => _generateNewKey(notify: true),
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Regenerate'),
                            ),
                          ],
                        ),
                      ] else ...[
                        OutlinedButton.icon(
                          onPressed: () => _generateNewKey(notify: true),
                          icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                          label: const Text('Generate Keypair Now'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Advanced: Custom Private Key
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Advanced: Custom Private Key (PEM)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  children: [
                    TextFormField(
                      controller: _privateKeyController,
                      maxLines: 4,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'Private Key (PEM)',
                        hintText: 'Paste OpenSSH or PEM private key here...',
                        alignLabelWithHint: true,
                        suffixIcon: IconButton(
                          tooltip: 'Paste from clipboard',
                          icon: const Icon(Icons.content_paste_rounded),
                          onPressed: _pasteFromClipboard,
                        ),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _publicKeyOpenSsh = SshKeyHelper.extractOpenSshPublicKey(val);
                        });
                      },
                      validator: (val) {
                        if (!isEdit && (val == null || val.trim().isEmpty)) {
                          return 'Private key is required';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Save Button
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: double.infinity,
                  minHeight: 48,
                ),
                child: FilledButton(
                  onPressed: _isSaving ? null : _handleSave,
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(isEdit ? 'Save Changes' : 'Add Profile'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Interactive modal dialog that prompts for the laptop SSH password once,
/// runs `ssh-copy-id` via [SettingsViewModel.autoInstallKey], and shows
/// real-time progress and verification.
class _SshCopyIdDialog extends StatefulWidget {
  const _SshCopyIdDialog({
    required this.host,
    required this.port,
    required this.username,
    required this.remoteDir,
    required this.publicKeyOpenSsh,
    required this.privateKeyPem,
  });

  final String host;
  final int port;
  final String username;
  final String remoteDir;
  final String publicKeyOpenSsh;
  final String privateKeyPem;

  @override
  State<_SshCopyIdDialog> createState() => _SshCopyIdDialogState();
}

class _SshCopyIdDialogState extends State<_SshCopyIdDialog> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isRunning = false;
  String? _successResult;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _runInstall() async {
    final password = _passwordController.text;
    if (password.isEmpty) return;

    setState(() {
      _isRunning = true;
      _errorMessage = null;
    });

    try {
      final viewModel = context.read<SettingsViewModel>();
      final result = await viewModel.autoInstallKey(
        host: widget.host,
        port: widget.port,
        username: widget.username,
        password: password,
        publicKeyOpenSsh: widget.publicKeyOpenSsh,
        privateKeyPem: widget.privateKeyPem,
        remoteDir: widget.remoteDir,
      );

      if (mounted) {
        setState(() {
          _isRunning = false;
          _successResult = result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 1. Success View
    if (_successResult != null) {
      return AlertDialog(
        icon: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
        title: const Text('Key Installed & Verified!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your phone\'s public key was added to ~/.ssh/authorized_keys on your laptop. '
              'Passwordless SSH key authentication is now active!',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: SelectableText(
                _successResult!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Done'),
          ),
        ],
      );
    }

    // 2. Running View
    if (_isRunning) {
      return AlertDialog(
        title: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 12),
            Text('Auto-Setting Up Key...'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1. Connecting to ${widget.username}@${widget.host}:${widget.port} via password...',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            const Text(
              '2. Installing public key to ~/.ssh/authorized_keys...',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            const Text(
              '3. Verifying passwordless private key login...',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      );
    }

    // 3. Password Input or Error View
    return AlertDialog(
      icon: Icon(
        _errorMessage != null ? Icons.error_outline_rounded : Icons.bolt_rounded,
        color: _errorMessage != null ? theme.colorScheme.error : theme.colorScheme.primary,
        size: 36,
      ),
      title: Text(_errorMessage != null ? 'Setup Failed' : 'Auto-Setup (ssh-copy-id)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_errorMessage != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],
            Text(
              'Enter your Linux login password for ${widget.username}@${widget.host}. Just like running ssh-copy-id on a computer, this password is only used once to install the phone\'s public key to ~/.ssh/authorized_keys.',
              style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Laptop User Password (Linux Login)',
                hintText: 'Enter your laptop user account password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              onSubmitted: (_) => _runInstall(),
            ),
            const SizedBox(height: 6),
            Text(
              'Your password is never saved. The phone uses its generated Ed25519 private key for all future syncing.',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _runInstall,
          icon: const Icon(Icons.bolt_rounded, size: 18),
          label: Text(_errorMessage != null ? 'Retry' : 'Install Key'),
        ),
      ],
    );
  }
}
