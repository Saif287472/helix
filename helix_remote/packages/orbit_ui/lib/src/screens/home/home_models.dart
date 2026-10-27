import 'dart:async';

import 'package:orbit_ui/src/models/view_models.dart';

/// Whether a list has loaded (`contracts/home.md`, shared types).
enum ListStatus { loading, failed, ready }

/// The Home tabs.
enum HomeTab { chats, calls }

/// The chat filters (design decision 2026-10-16): All, Unread, Groups; and
/// Favourites, the chats the person starred in the list.
enum ChatFilter {
  all('All'),
  unread('Unread'),
  groups('Groups'),
  favourites('Favourites');

  const ChatFilter(this.label);

  final String label;

  bool matches(HelixChatListItem c) => switch (this) {
    all => true,
    unread => c.unreadCount > 0,
    groups => c.avatar.isGroup,
    favourites => c.favourite,
  };
}

/// Where the people panel is: in the Chats search or the Calls search.
enum PeopleSearchMode { chats, calls }

/// The contacts card at the top of the people panel.
enum ContactsCard { hidden, ask, openSettings, refresh }

/// Where checking your contacts is (the Refresh row's subtitle).
enum PhoneBookStatus { idle, checking, limit, done, failed }

/// The row that offers a network lookup for what was typed.
sealed class LookupPrompt {
  const LookupPrompt();
}

class NoLookup extends LookupPrompt {
  const NoLookup();
}

/// A number without enough digits: "Type the whole number…".
class NeedFullNumber extends LookupPrompt {
  const NeedFullNumber();
}

/// "Find +880 1711 000002 on Orbit".
class FindNumber extends LookupPrompt {
  const FindNumber(this.shown);

  final String shown;
}

/// "Find ~arifh on Orbit".
class FindName extends LookupPrompt {
  const FindName(this.name);

  final String name;
}

/// What a lookup came back with.
enum LookupView {
  idle,
  searching,
  notFound,
  self,
  rateLimited,
  offline,
  failed,
}

/// A group in the people panel.
class PanelGroup {
  const PanelGroup({
    required this.groupId,
    required this.chatId,
    required this.title,
    required this.avatar,
  });

  final String groupId;
  final String chatId;
  final String title;
  final HelixAvatarModel avatar;
}

/// The note-to-self entry the people panel offers while browsing: the chat
/// you keep your own notes in. Its title is the app's, so the row and the chat
/// it opens say the same thing.
class PanelSelf {
  const PanelSelf({
    required this.accountId,
    required this.title,
    required this.avatar,
  });

  /// Whose chat this is: this device's own account.
  final String accountId;
  final String title;
  final HelixAvatarModel avatar;
}

/// What the panel says when there is nothing to show.
enum PanelEmpty { none, nobodyYet, noMatches }

/// `PeoplePanelModel` (`contracts/home.md`).
class PeoplePanelModel {
  const PeoplePanelModel({
    this.query = '',
    this.mode = PeopleSearchMode.chats,
    this.status = ListStatus.ready,
    this.contacts = ContactsCard.hidden,
    this.refresh = PhoneBookStatus.idle,
    this.found = 0,
    this.lookupPrompt = const NoLookup(),
    this.lookup = LookupView.idle,
    this.groups = const [],
    this.people = const [],
    this.self,
    this.empty = PanelEmpty.none,
  });

  final String query;
  final PeopleSearchMode mode;
  final ListStatus status;
  final ContactsCard contacts;
  final PhoneBookStatus refresh;

  /// How many contacts are on Orbit, after a check.
  final int found;
  final LookupPrompt lookupPrompt;
  final LookupView lookup;
  final List<PanelGroup> groups;
  final List<HelixPersonItem> people;

  /// The note-to-self row, while browsing; null with no account on this
  /// device, and on the Calls tab, where you cannot call yourself.
  final PanelSelf? self;
  final PanelEmpty empty;

  /// "People on Orbit" while browsing, "People" for a search.
  String get peopleLabel => query.trim().isEmpty ? 'People on Orbit' : 'People';
}

/// One message that matches the Chats search.
class ChatSearchHit {
  const ChatSearchHit({
    required this.chatId,
    required this.messageId,
    required this.title,
    required this.avatar,
    required this.timeLabel,
    required this.who,
    required this.text,
  });

  final String chatId;
  final String messageId;
  final String title;
  final HelixAvatarModel avatar;
  final String timeLabel;

  /// "You", or the sender's first name.
  final String who;

  /// The message, with the match emphasised.
  final HelixHighlightedText text;
}

/// `ChatSearchModel` (`contracts/home.md`).
class ChatSearchModel {
  const ChatSearchModel({
    this.query = '',
    this.status = ListStatus.ready,
    this.chats = const [],
    this.messages = const [],
    this.people = const PeoplePanelModel(),
  });

  final String query;
  final ListStatus status;
  final List<HelixChatListItem> chats;
  final List<ChatSearchHit> messages;
  final PeoplePanelModel people;
}

/// `ChatsTabModel` (`contracts/home.md`).
class ChatsTabModel {
  const ChatsTabModel({
    this.chats = const [],
    this.status = ListStatus.ready,
    this.archivedCount = 0,
    this.openChatId,
    this.search = const ChatSearchModel(),
    this.lists = const [],
    this.lockedCount = 0,
  });

  /// How many chats are locked (the menu's Locked chats shows only then).
  final int lockedCount;

  /// The person's own lists, in the order of their chips.
  final List<HelixChatList> lists;
  final List<HelixChatListItem> chats;
  final ListStatus status;
  final int archivedCount;
  final String? openChatId;
  final ChatSearchModel search;
}

/// A recent person in the Calls tab's quick row.
class QuickPerson {
  const QuickPerson({
    required this.peerId,
    required this.label,
    required this.avatar,
  });

  final String peerId;

  /// The first name under the picture.
  final String label;
  final HelixAvatarModel avatar;
}

/// `CallsTabModel` (`contracts/home.md`).
class CallsTabModel {
  const CallsTabModel({
    this.calls = const [],
    this.status = ListStatus.ready,
    this.quick = const [],
    this.openCallId,
    this.search = const PeoplePanelModel(mode: PeopleSearchMode.calls),
  });

  final List<HelixCallLogItem> calls;
  final ListStatus status;
  final List<QuickPerson> quick;
  final String? openCallId;
  final PeoplePanelModel search;
}

/// `HomeModel` (`contracts/home.md`).
class HomeModel {
  const HomeModel({
    required this.me,
    this.meNeedsAttention = false,
    this.chats = const ChatsTabModel(),
    this.calls = const CallsTabModel(),
  });

  final HelixAvatarModel me;
  final bool meNeedsAttention;
  final ChatsTabModel chats;
  final CallsTabModel calls;
}

/// How long to mute (`MuteFor` in `contracts/home.md`).
enum MuteFor {
  eightHours('8 hours'),
  week('1 week'),
  always('Always');

  const MuteFor(this.label);
  final String label;
}

/// `PeoplePanelActions` (`contracts/home.md`).
class PeoplePanelActions {
  const PeoplePanelActions({
    this.onQueryChanged,
    this.onLookUp,
    this.onAllowContacts,
    this.onOpenContactsSettings,
    this.onRefreshContacts,
    this.onOpenPerson,
    this.onCallPerson,
    this.onOpenContactInfo,
    this.onOpenGroup,
    this.onOpenSelf,
  });

  final void Function(String text)? onQueryChanged;
  final void Function()? onLookUp;
  final Future<void> Function()? onAllowContacts;
  final Future<void> Function()? onOpenContactsSettings;
  final Future<void> Function()? onRefreshContacts;
  final Future<String?> Function(String accountId)? onOpenPerson;
  final Future<String?> Function(String accountId, {required bool video})?
  onCallPerson;
  final void Function(String accountId)? onOpenContactInfo;
  final void Function(String groupId)? onOpenGroup;

  /// Opens the note-to-self chat of [PanelSelf.accountId]. Null where there is
  /// no such entry to tap.
  final void Function(String accountId)? onOpenSelf;
}

/// `HomeActions` with the Chats and Calls tabs' actions (`contracts/home.md`).
class HomeActions {
  const HomeActions({
    this.onOpenYou,
    this.onTabChanged,
    this.onOpenChat,
    this.onSetPinned,
    this.onSetFavourite,
    this.onCreateList,
    this.onRenameList,
    this.onDeleteList,
    this.onSetOnList,
    this.onSetLocked,
    this.onOpenLocked,
    this.onSetArchived,
    this.onMute,
    this.onMarkRead,
    this.onDelete,
    this.onNewGroup,
    this.onJoinGroup,
    this.onOpenArchived,
    this.onSearchChanged,
    this.onOpenCall,
    this.onCallBack,
    this.onCall,
    this.onDeleteCalls,
    this.onCallSearchChanged,
    this.people = const PeoplePanelActions(),
    this.peopleCalls,
  });

  final void Function()? onOpenYou;
  final void Function(HomeTab tab)? onTabChanged;
  final void Function(String chatId, {String? messageId})? onOpenChat;
  final Future<void> Function(Set<String> ids, {required bool pinned})?
  onSetPinned;

  /// Makes the chats favourites, or not. With it set, the selection menu
  /// offers Favourite.
  final Future<void> Function(Set<String> ids, {required bool favourite})?
  onSetFavourite;

  /// Makes a list called [name] holding [chatIds] (none from the New list
  /// chip); the sentence to show when it could not be made. With it set, the
  /// chat filters end in New list and the selection menu offers Add to list.
  final FutureOr<String?> Function(String name, Set<String> chatIds)?
  onCreateList;

  /// Renames a list; the sentence to show when it could not be.
  final FutureOr<String?> Function(String id, String name)? onRenameList;
  final Future<void> Function(String id)? onDeleteList;

  /// Puts the chats on a list, or takes them off it.
  final Future<void> Function(
    Set<String> chatIds,
    String listId, {
    required bool member,
  })?
  onSetOnList;

  /// Locks the chats, or unlocks them; the sentence to show when it could not
  /// be done (the phone has no screen lock), null when it was. With it set, the
  /// selection menu offers Lock chat.
  final Future<String?> Function(Set<String> ids, {required bool locked})?
  onSetLocked;

  /// Opens the Locked chats screen (the app asks for the phone's unlock
  /// first). With it set, and chats locked, the ⋮ menu offers it.
  final void Function()? onOpenLocked;
  final Future<void> Function(Set<String> ids, {required bool archived})?
  onSetArchived;
  final Future<void> Function(Set<String> ids, MuteFor? length)? onMute;
  final Future<void> Function(Set<String> ids)? onMarkRead;
  final Future<void> Function(Set<String> ids)? onDelete;
  final void Function()? onNewGroup;
  final void Function()? onJoinGroup;
  final void Function()? onOpenArchived;
  final void Function(String text)? onSearchChanged;
  final void Function(String callId)? onOpenCall;
  final Future<String?> Function(String callId)? onCallBack;
  final Future<String?> Function(String peerId, {required bool video})? onCall;
  final Future<void> Function(String callId)? onDeleteCalls;

  /// The Calls search's text (its own people panel).
  final void Function(String text)? onCallSearchChanged;
  final PeoplePanelActions people;
  final PeoplePanelActions? peopleCalls;
}

/// Where the preview opens Home: the prototype's keys start in these states.
class HomeStart {
  const HomeStart({
    this.tab = HomeTab.chats,
    this.filter = ChatFilter.all,
    this.searching = false,
    this.query = '',
    this.callSearching = false,
    this.selected = const {},
    this.menu = false,
    this.toast,
  });

  final HomeTab tab;
  final ChatFilter filter;
  final bool searching;
  final String query;
  final bool callSearching;
  final Set<String> selected;

  /// The ⋮ menu is open.
  final bool menu;

  /// A toast showing (the invite link while signed in).
  final String? toast;
}
