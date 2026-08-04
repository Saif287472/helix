import 'package:flutter/material.dart';

import '../admin_client.dart';
import '../theme/app_theme.dart';

/// Editor for the server's display name - the one setting on the Config
/// screen that the server's own users actually see.
class ServerNameCard extends StatefulWidget {
  const ServerNameCard({
    super.key,
    required this.initialName,
    required this.maxLength,
    required this.onSave,
    this.serverHost,
  });

  /// Name currently stored on the server; empty when unset.
  final String initialName;

  final int maxLength;

  /// Persists the name and returns the normalized value the server kept.
  /// Throws [AdminRequestException] with a message worth showing when the
  /// server rejects it.
  final Future<String> Function(String name) onSave;

  /// What users see when no name is set, shown as the placeholder so the
  /// fallback isn't a mystery.
  final String? serverHost;

  @override
  State<ServerNameCard> createState() => _ServerNameCardState();
}

class _ServerNameCardState extends State<ServerNameCard> {
  late final TextEditingController _controller;
  late String _savedName;
  bool _isSaving = false;
  String? _error;
  bool _justSaved = false;

  @override
  void initState() {
    super.initState();
    _savedName = widget.initialName;
    _controller = TextEditingController(text: widget.initialName);
    _controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(ServerNameCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A background refresh must not overwrite something half-typed, so the
    // field only re-syncs when the operator has no unsaved edit.
    if (widget.initialName != oldWidget.initialName && !_isDirty) {
      _savedName = widget.initialName;
      _controller.text = widget.initialName;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  bool get _isDirty => _controller.text.trim() != _savedName.trim();

  void _onChanged() {
    if (_error != null || _justSaved) {
      setState(() {
        _error = null;
        _justSaved = false;
      });
    } else {
      // Still rebuild, so the Save button tracks the dirty state.
      setState(() {});
    }
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
      _justSaved = false;
    });
    try {
      final stored = await widget.onSave(_controller.text);
      if (!mounted) return;
      setState(() {
        _savedName = stored;
        // Show the normalized form the server actually kept, so what's on
        // screen matches what users will see.
        _controller.text = stored;
        _isSaving = false;
        _justSaved = true;
      });
    } on AdminRequestException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = "Couldn't reach the server to save the name.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.serverHost;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Server Name',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Shown to everyone on this server - on the join screen when '
              'they use your invite, and in their app settings afterwards.',
              style: TextStyle(
                color: context.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              enabled: !_isSaving,
              maxLength: widget.maxLength,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (_isDirty && !_isSaving) _save();
              },
              decoration: InputDecoration(
                labelText: 'Server name',
                hintText: host == null || host.isEmpty
                    ? 'e.g. Rahman Family Server'
                    : 'Unnamed - users see $host',
                errorText: _error,
                helperText: _justSaved
                    ? 'Saved. Users will see this name from now on.'
                    : 'Leave empty to show the server address instead.',
                helperStyle: _justSaved
                    ? const TextStyle(color: Colors.green)
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _isDirty && !_isSaving ? _save : null,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_isSaving ? 'Saving...' : 'Save name'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
