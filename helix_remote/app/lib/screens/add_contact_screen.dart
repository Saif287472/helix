import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({
    super.key,
    required this.root,
    required this.messagingService,
  });

  final RemoteCompositionRoot root;
  final RemoteMessagingService messagingService;

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _nameController = TextEditingController();
  final _linkController = TextEditingController();
  int _searchGen = 0;
  bool _searching = false;
  bool _handlingLink = false;
  String? _searchError;
  String? _linkError;
  List<Map<String, dynamic>> _foundAccounts = const [];
  late final String _shareLink;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final nonce = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    _shareLink = widget.messagingService.createSignedContactLink(
      linkId: 'cl_$nonce',
      nonce: nonce,
      ttl: const Duration(days: 7),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _nameController.text.trim();
    if (q.length < 3) {
      setState(() {
        _searchError = 'Enter at least 3 characters of a display name.';
        _foundAccounts = const [];
      });
      return;
    }
    final gen = ++_searchGen;
    setState(() {
      _searching = true;
      _searchError = null;
      _foundAccounts = const [];
    });
    try {
      final results = await widget.root.restClient.searchContacts(q);
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _foundAccounts = results;
        if (results.isEmpty) {
          _searchError = 'No display names found for "$q"';
        }
      });
    } catch (e) {
      if (mounted && gen == _searchGen) {
        setState(
          () => _searchError =
              'Search failed. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted && gen == _searchGen) setState(() => _searching = false);
    }
  }

  Future<void> _sendRequest(String accountId, String displayName) async {
    try {
      widget.messagingService.sendContactRequest(peerAccountId: accountId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contact request sent to $displayName')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _handleContactLink(String link) async {
    final trimmed = link.trim();
    if (_handlingLink || trimmed.isEmpty) return;
    setState(() {
      _handlingLink = true;
      _linkError = null;
    });
    try {
      if (!widget.messagingService.verifySignedContactLink(trimmed)) {
        setState(() => _linkError = 'This contact link is invalid or expired.');
        return;
      }
      final uri = Uri.parse(trimmed);
      final accountId = uri.queryParameters['a'] ?? '';
      if (accountId.isEmpty ||
          accountId == widget.messagingService.currentAccountId) {
        setState(() => _linkError = 'This link cannot be used here.');
        return;
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Send contact request?'),
          content: Text('Send a Helix contact request to $accountId?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Send request'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        _sendRequest(accountId, accountId);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _linkError = 'This is not a valid Helix contact link.');
      }
    } finally {
      if (mounted) setState(() => _handlingLink = false);
    }
  }

  String _displayNameFor(Map<String, dynamic> account) {
    final value = account['display_name'] ?? account['displayName'];
    return value is String ? value.trim() : '';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: Text(
          'Add Contact',
          style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: cs.onPrimary,
          unselectedLabelColor: cs.onPrimary.withAlpha(160),
          indicatorColor: cs.onPrimary,
          // 'Search' rather than 'Search names': three equal-width tabs give
          // each a third of the screen, and the longer label was being cut
          // mid-word ("Search name") on a 1080p phone before any text
          // scaling was applied. The other two are already one word.
          tabs: const [
            Tab(icon: Icon(Icons.search), text: 'Search'),
            Tab(icon: Icon(Icons.qr_code_2), text: 'My QR'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scan'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildSearchTab(), _buildShareTab(), _buildScanTab()],
      ),
    );
  }

  Widget _buildSearchTab() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Display name',
              hintText: 'e.g. Saif',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.person_search_outlined),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              errorText: _searchError,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _searching ? null : _search,
            icon: const Icon(Icons.search),
            label: const Text('Search'),
          ),
          if (_foundAccounts.isNotEmpty) ...[
            const SizedBox(height: 24),
            Expanded(
              child: ListView.separated(
                itemCount: _foundAccounts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final account = _foundAccounts[index];
                  final displayName = _displayNameFor(account);
                  final accountId = (account['account_id'] as String?) ?? '';
                  final initial = displayName.isEmpty
                      ? '?'
                      : displayName.substring(0, 1).toUpperCase();
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          initial,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        displayName.isEmpty
                            ? 'Unknown display name'
                            : displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: FilledButton(
                        onPressed: accountId.isEmpty
                            ? null
                            : () => _sendRequest(accountId, displayName),
                        child: const Text('Add'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShareTab() {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    // Scrollable rather than a bare Column: this tab's height is not fixed.
    // The link grows with the account id and signature, the caption below
    // it wraps to a different number of lines on narrower screens, and the
    // app allows system text scaling up to 1.3x on top of both. A layout
    // that happens to fit one phone overflows the next.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            'Share this link with someone so they can add you as a contact.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Center(
            child: QrImageView(
              data: _shareLink,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _shareLink,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy link',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _shareLink));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied to clipboard')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Send this via WhatsApp, email, or any other channel. '
            'The link expires in 7 days and opens a confirmation screen before any contact request is sent.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _shareLink));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Link copied — paste it anywhere to share'),
                ),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy link'),
          ),
        ],
      ),
    );
  }

  Widget _buildScanTab() {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    // Same reason as the share tab, plus one specific to this one: the
    // "Paste contact link" field raises the keyboard, which takes roughly
    // half the height away from a square camera preview that does not
    // shrink. Without a scroll view that is a guaranteed overflow every
    // time someone taps the field.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: MobileScanner(
                onDetect: (capture) {
                  String? raw;
                  for (final barcode in capture.barcodes) {
                    if (barcode.rawValue != null) {
                      raw = barcode.rawValue;
                      break;
                    }
                  }
                  if (raw != null) _handleContactLink(raw);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _linkController,
            decoration: InputDecoration(
              labelText: 'Paste contact link',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.link),
              errorText: _linkError,
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: _handleContactLink,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _handlingLink
                ? null
                : () => _handleContactLink(_linkController.text),
            icon: _handlingLink
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : const Icon(Icons.verified_user_outlined),
            label: const Text('Validate link'),
          ),
          const SizedBox(height: 12),
          Text(
            'Scanned links are checked for expiry and replay before a request is sent.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }
}
