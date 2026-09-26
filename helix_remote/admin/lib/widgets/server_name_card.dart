import 'package:flutter/material.dart';

import '../admin_client.dart';

/// Editor for the server's display name - the one setting on the Config
/// screen that the server's own users actually see.
class ServerNameCard extends StatefulWidget {
  const ServerNameCard({
    super.key,
    required this.initialName,
    required this.maxLength,
    required this.onSave,
    this.fallbackName,
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

  @override
  State<ServerNameCard> createState() => _ServerNameCardState();
}

class _ServerNameCardState extends State<ServerNameCard> {
  late final TextEditingController _controller;
  late String _savedName;
  bool _isEditing = false;
  bool _isSaving = false;
  String? _error;

  /// The name to show when neither a stored name nor a server-computed
  /// fallback exists. A neutral placeholder, not a plausible-looking invented
  /// server name.
  static const _placeholderName = 'Helix Server';

  @override
  void initState() {
    super.initState();
    _savedName = widget.initialName.isNotEmpty
        ? widget.initialName
        : (widget.fallbackName ?? _placeholderName);
    _controller = TextEditingController(text: _savedName);
    // Save stays disabled until the text differs from what is stored, so
    // opening the editor and closing it again cannot issue a pointless write
    // - or send a name that differs from the server's only by surrounding
    // whitespace, which the server would silently normalize.
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {
      // Clear a previous failure as soon as the user starts fixing it. Leaving
      // it up means a stale "server_name must be 60 characters or fewer" sits
      // under the field while the user is typing a valid name, which reads as
      // "still wrong" for as long as they are typing.
      if (_error != null) _error = null;
    });
  }

  @override
  void didUpdateWidget(ServerNameCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialName != oldWidget.initialName && !_isEditing) {
      _savedName = widget.initialName.isNotEmpty
          ? widget.initialName
          : (widget.fallbackName ?? _placeholderName);
      _controller.text = _savedName;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  /// True when the field holds something the server does not already have.
  bool get _hasChanges => _controller.text != _savedName;

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final stored = await widget.onSave(_controller.text);
      if (!mounted) return;
      setState(() {
        _savedName = stored.isNotEmpty ? stored : _savedName;
        _controller.text = _savedName;
        _isSaving = false;
        _isEditing = false;
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
        _error = "Couldn't reach server.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'SERVER NODE IDENTITY',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF64748B),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          if (!_isEditing)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _savedName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Public node identity shown to onboarding users',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  onPressed: () => setState(() => _isEditing = true),
                  child: const Text('Edit Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _controller,
                  enabled: !_isSaving,
                  maxLength: widget.maxLength,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Server name',
                    errorText: _error,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : () => setState(() => _isEditing = false),
                      child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        minimumSize: Size.zero,
                      ),
                      onPressed: (_isSaving || !_hasChanges) ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Save Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}
