import 'package:helix_remote_ui/helix_remote_ui.dart';
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
    this.fallbackName,
    this.serverHost,
  });

  /// Name currently stored on the server; empty when unset.
  final String initialName;

  final int maxLength;

  /// Persists the name and returns the normalized value the server kept.
  /// Throws [AdminRequestException] with a message worth showing when the
  /// server rejects it.
  final Future<String> Function(String name) onSave;

  /// Fallback name shown to users when no custom display name is configured.
  final String? fallbackName;

  /// Host users connect to (internal fallback).
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
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Server Name',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Shown to everyone on this server - on the join screen when they use your invite, and in their app settings afterwards.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
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
                hintText:
                    'Unnamed - users see ${widget.fallbackName ?? (widget.serverHost != null && widget.serverHost!.isNotEmpty ? widget.serverHost! : "Private Server")}',
                errorText: _error,
                helperText: _justSaved
                    ? 'Saved. Users will see this name from now on.'
                    : 'Leave empty to show the default name instead.',
                helperStyle: _justSaved
                    ? const TextStyle(color: Colors.green)
                    : null,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF2563EB)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _isDirty && !_isSaving ? _save : null,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
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
