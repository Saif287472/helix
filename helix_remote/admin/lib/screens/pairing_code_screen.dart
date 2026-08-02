import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../admin_client.dart';

/// Redeems a short-lived pairing code (see the backend's
/// AdminPairingModule) for a freshly-rotated admin token, as an alternative
/// to scanning or hand-typing the long token itself. The code comes from
/// running a command directly on the server, which works while the server
/// is running - not just on first boot, unlike ADMIN_TOKEN.txt. Pops with
/// the new token on success, or nothing if the user backs out.
class PairingCodeScreen extends StatefulWidget {
  const PairingCodeScreen({super.key, required this.baseUrl});

  /// Server URL as currently entered in Settings, used to redeem the code
  /// over the network. The printed command itself always targets the
  /// server's own loopback address, independent of this.
  final String baseUrl;

  @override
  State<PairingCodeScreen> createState() => _PairingCodeScreenState();
}

class _PairingCodeScreenState extends State<PairingCodeScreen> {
  static const _command =
      'curl -s -X POST http://127.0.0.1:8080/api/v1/admin-pairing/generate';
  static final _codePattern = RegExp(r'^[0-9]{16}$');

  final _codeController = TextEditingController();
  bool _isRedeeming = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _codeController.text.trim();
    if (!_codePattern.hasMatch(code)) {
      setState(() => _error = 'Enter the 16-digit code exactly as printed.');
      return;
    }
    if (widget.baseUrl.trim().isEmpty) {
      setState(
        () => _error = 'Enter your server URL above first, then redeem.',
      );
      return;
    }

    setState(() {
      _isRedeeming = true;
      _error = null;
    });
    try {
      final token = await redeemPairingCode(
        baseUrl: widget.baseUrl.trim(),
        code: code,
      );
      if (!mounted) return;
      Navigator.of(context).pop(token);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRedeeming = false;
        _error = 'Could not redeem that code: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PAIRING CODE')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Run this on the server (over SSH, Termius, etc.) while it's "
              'running:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0B12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: SelectableText(
                      _command,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Color(0xFF00E5FF),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy command',
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: _command));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Command copied to clipboard'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Replace 8080 if you customized HELIX_REMOTE_PORT. It prints '
              'a 16-digit code, valid for 10 minutes and usable once.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 32),
            TextField(
              key: const Key('pairing_code_field'),
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 16,
              decoration: const InputDecoration(
                labelText: 'Pairing Code',
                prefixIcon: Icon(Icons.dialpad),
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFFF3366),
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton.icon(
              key: const Key('pairing_code_redeem_button'),
              onPressed: _isRedeeming ? null : _redeem,
              icon: _isRedeeming
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.key),
              label: Text(_isRedeeming ? 'Redeeming…' : 'Redeem Code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A2BE2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
