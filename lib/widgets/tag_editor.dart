import 'package:flutter/material.dart';

/// An interactive tag chip editor allowing creation and deletion of tags.
class TagEditor extends StatefulWidget {
  /// Creates a [TagEditor].
  const TagEditor({
    super.key,
    required this.tags,
    required this.onTagsChanged,
    this.maxTags = 10,
    this.maxTagLength = 20,
  });

  /// The current list of tag labels.
  final List<String> tags;

  /// Callback triggered when tags are added or removed.
  final ValueChanged<List<String>> onTagsChanged;

  /// Maximum number of tags allowed.
  final int maxTags;

  /// Maximum character length per tag.
  final int maxTagLength;

  @override
  State<TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<TagEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addTag(String rawInput) {
    final candidate = rawInput.trim().replaceAll(',', '');
    if (candidate.isEmpty) {
      _controller.clear();
      return;
    }

    if (widget.tags.length >= widget.maxTags) {
      _controller.clear();
      return;
    }

    final sanitized = candidate.length > widget.maxTagLength
        ? candidate.substring(0, widget.maxTagLength)
        : candidate;

    final alreadyExists = widget.tags.any(
      (String existing) => existing.toLowerCase() == sanitized.toLowerCase(),
    );

    if (!alreadyExists) {
      final updatedList = List<String>.from(widget.tags)..add(sanitized);
      widget.onTagsChanged(updatedList);
    }

    _controller.clear();
  }

  void _removeTag(int index) {
    if (index >= 0 && index < widget.tags.length) {
      final updatedList = List<String>.from(widget.tags)..removeAt(index);
      widget.onTagsChanged(updatedList);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAddMore = widget.tags.length < widget.maxTags;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        ...List<Widget>.generate(widget.tags.length, (int index) {
          final tag = widget.tags[index];
          return InputChip(
            key: ValueKey<String>('tag_$tag'),
            label: Text(
              '#$tag',
              style: const TextStyle(fontSize: 12),
            ),
            deleteIcon: const Icon(Icons.close, size: 14),
            deleteButtonTooltipMessage: 'Remove #$tag',
            onDeleted: () => _removeTag(index),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          );
        }),
        if (canAddMore)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 80, maxWidth: 140),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: canAddMore,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Add tag...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (String value) {
                if (value.contains(',')) {
                  _addTag(value);
                }
              },
              onSubmitted: _addTag,
            ),
          ),
      ],
    );
  }
}
