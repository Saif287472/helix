import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/composition_root.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDir = await getApplicationDocumentsDirectory();
  final root = RemoteCompositionRoot.production(databaseDirectory: appDir.path);
  await root.initialize();
  runApp(HelixRemoteApp(root: root));
}

class HelixRemoteApp extends StatefulWidget {
  const HelixRemoteApp({super.key, required this.root});

  final RemoteCompositionRoot root;

  @override
  State<HelixRemoteApp> createState() => _HelixRemoteAppState();
}

class _HelixRemoteAppState extends State<HelixRemoteApp> {
  @override
  void dispose() {
    widget.root.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.root.config.displayName,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF166A64),
          brightness: Brightness.light,
        ),
      ),
      home: const _RemoteHomeScreen(),
    );
  }
}

class _RemoteHomeScreen extends StatefulWidget {
  const _RemoteHomeScreen();

  @override
  State<_RemoteHomeScreen> createState() => _RemoteHomeScreenState();
}

class _RemoteHomeScreenState extends State<_RemoteHomeScreen> {
  final _usernameController = TextEditingController(text: 'alice');
  final _deviceController = TextEditingController(text: 'Primary phone');
  final _contactController = TextEditingController(text: 'bob');
  final _messageController = TextEditingController();
  final _contacts = <String>['bob'];
  final _messages = <_UiMessage>[
    const _UiMessage(
      author: 'bob',
      body: 'Encrypted direct channel is ready.',
      status: 'delivered',
    ),
  ];
  var _selectedContact = 'bob';
  var _deviceVerified = true;
  var _readReceipts = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _deviceController.dispose();
    _contactController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Helix Remote'),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
          IconButton(
            tooltip: 'Sync',
            icon: const Icon(Icons.sync),
            onPressed: () {},
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final sidebar = _Sidebar(
            usernameController: _usernameController,
            deviceController: _deviceController,
            contactController: _contactController,
            contacts: _contacts,
            selectedContact: _selectedContact,
            deviceVerified: _deviceVerified,
            readReceipts: _readReceipts,
            onDeviceVerifiedChanged: (value) {
              setState(() => _deviceVerified = value);
            },
            onReadReceiptsChanged: (value) {
              setState(() => _readReceipts = value);
            },
            onContactSelected: (contact) {
              setState(() => _selectedContact = contact);
            },
            onAddContact: _addContact,
            onBlockSelected: _blockSelectedContact,
          );
          final chat = _ConversationPane(
            contact: _selectedContact,
            messages: _messages,
            messageController: _messageController,
            isTyping: _messageController.text.trim().isNotEmpty,
            onSend: _sendMessage,
            onChanged: (_) => setState(() {}),
            onEdit: _editMessage,
            onReact: _reactToMessage,
            onDelete: _deleteMessage,
          );

          if (compact) {
            return ListView(
              children: [
                sidebar,
                const Divider(height: 1),
                SizedBox(height: 520, child: chat),
              ],
            );
          }

          return Row(
            children: [
              SizedBox(width: 340, child: sidebar),
              const VerticalDivider(width: 1),
              Expanded(child: chat),
            ],
          );
        },
      ),
    );
  }

  void _addContact() {
    final contact = _contactController.text.trim();
    if (contact.isEmpty || _contacts.contains(contact)) return;
    setState(() {
      _contacts.add(contact);
      _selectedContact = contact;
    });
  }

  void _blockSelectedContact() {
    setState(() {
      _contacts.remove(_selectedContact);
      if (_contacts.isEmpty) {
        _contacts.add('new-contact');
      }
      _selectedContact = _contacts.first;
    });
  }

  void _sendMessage() {
    final body = _messageController.text.trim();
    if (body.isEmpty) return;
    setState(() {
      _messages.add(_UiMessage(author: 'me', body: body, status: 'queued'));
      _messageController.clear();
    });
  }

  void _editMessage(int index) {
    final current = _messages[index];
    setState(() {
      _messages[index] = current.copyWith(
        body: '${current.body} (edited)',
        edited: true,
      );
    });
  }

  void _reactToMessage(int index) {
    final current = _messages[index];
    setState(() {
      _messages[index] = current.copyWith(reaction: '+1');
    });
  }

  void _deleteMessage(int index) {
    setState(() => _messages.removeAt(index));
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.usernameController,
    required this.deviceController,
    required this.contactController,
    required this.contacts,
    required this.selectedContact,
    required this.deviceVerified,
    required this.readReceipts,
    required this.onDeviceVerifiedChanged,
    required this.onReadReceiptsChanged,
    required this.onContactSelected,
    required this.onAddContact,
    required this.onBlockSelected,
  });

  final TextEditingController usernameController;
  final TextEditingController deviceController;
  final TextEditingController contactController;
  final List<String> contacts;
  final String selectedContact;
  final bool deviceVerified;
  final bool readReceipts;
  final ValueChanged<bool> onDeviceVerifiedChanged;
  final ValueChanged<bool> onReadReceiptsChanged;
  final ValueChanged<String> onContactSelected;
  final VoidCallback onAddContact;
  final VoidCallback onBlockSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Account', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: usernameController,
          decoration: const InputDecoration(
            labelText: 'Username',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: deviceController,
          decoration: const InputDecoration(
            labelText: 'Device',
            prefixIcon: Icon(Icons.devices_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Verified device'),
          value: deviceVerified,
          onChanged: onDeviceVerifiedChanged,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Read receipts'),
          value: readReceipts,
          onChanged: onReadReceiptsChanged,
        ),
        const SizedBox(height: 16),
        Text('Contacts', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: contactController,
                decoration: const InputDecoration(
                  labelText: 'Contact',
                  prefixIcon: Icon(Icons.alternate_email),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Add contact',
              onPressed: onAddContact,
              icon: const Icon(Icons.person_add_alt_1),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final contact in contacts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.lock_outline)),
            title: Text(contact),
            subtitle: const Text('Direct'),
            selected: contact == selectedContact,
            onTap: () => onContactSelected(contact),
            trailing: contact == selectedContact
                ? IconButton(
                    tooltip: 'Block contact',
                    icon: const Icon(Icons.block),
                    onPressed: onBlockSelected,
                  )
                : null,
          ),
      ],
    );
  }
}

class _ConversationPane extends StatelessWidget {
  const _ConversationPane({
    required this.contact,
    required this.messages,
    required this.messageController,
    required this.isTyping,
    required this.onSend,
    required this.onChanged,
    required this.onEdit,
    required this.onReact,
    required this.onDelete,
  });

  final String contact;
  final List<_UiMessage> messages;
  final TextEditingController messageController;
  final bool isTyping;
  final VoidCallback onSend;
  final ValueChanged<String> onChanged;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onReact;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.security)),
          title: Text(contact),
          subtitle: Text(isTyping ? 'Typing' : 'Encrypted direct chat'),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final mine = message.author == 'me';
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: mine
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(message.body),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                [
                                  message.status,
                                  if (message.edited) 'edited',
                                  if (message.reaction != null)
                                    message.reaction!,
                                ].join(' - '),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () => onEdit(index),
                              ),
                              IconButton(
                                tooltip: 'React',
                                icon: const Icon(Icons.add_reaction, size: 18),
                                onPressed: () => onReact(index),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                onPressed: () => onDelete(index),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: messageController,
                  onChanged: onChanged,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: onSend,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UiMessage {
  const _UiMessage({
    required this.author,
    required this.body,
    required this.status,
    this.edited = false,
    this.reaction,
  });

  final String author;
  final String body;
  final String status;
  final bool edited;
  final String? reaction;

  _UiMessage copyWith({String? body, String? reaction, bool? edited}) {
    return _UiMessage(
      author: author,
      body: body ?? this.body,
      status: status,
      edited: edited ?? this.edited,
      reaction: reaction ?? this.reaction,
    );
  }
}
