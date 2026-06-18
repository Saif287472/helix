part of 'chat_screen.dart';

mixin _ChatSearchMixin on _ChatScreenBase {
  void _updateSearch(List<ChatMessage> messages, String query) {
    if (query.isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchHitIndices = [];
        _searchHitIndex = 0;
      });
      return;
    }
    final hits = <int>[];
    for (var i = 0; i < messages.length; i++) {
      if (!messages[i].isDeleted &&
          !messages[i].isFile &&
          messages[i].text.toLowerCase().contains(query.toLowerCase())) {
        hits.add(i);
      }
    }
    setState(() {
      _searchQuery = query;
      _searchHitIndices = hits;
      _searchHitIndex = hits.isEmpty ? 0 : hits.length - 1;
    });
    if (hits.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final msgId = messages[hits.last].messageId;
        _scrollToMessage(msgId);
      });
    }
  }

  void _navigateSearch(List<ChatMessage> messages, {required bool forward}) {
    if (_searchHitIndices.isEmpty) return;
    final next = forward
        ? (_searchHitIndex + 1) % _searchHitIndices.length
        : (_searchHitIndex - 1 + _searchHitIndices.length) %
              _searchHitIndices.length;
    setState(() => _searchHitIndex = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final msgId = messages[_searchHitIndices[next]].messageId;
      _scrollToMessage(msgId);
    });
  }
}
