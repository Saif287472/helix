import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'helix_localizations_bn.dart';
import 'helix_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of HelixLocalizations
/// returned by `HelixLocalizations.of(context)`.
///
/// Applications need to include `HelixLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/helix_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: HelixLocalizations.localizationsDelegates,
///   supportedLocales: HelixLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the HelixLocalizations.supportedLocales
/// property.
abstract class HelixLocalizations {
  HelixLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static HelixLocalizations of(BuildContext context) {
    return Localizations.of<HelixLocalizations>(context, HelixLocalizations)!;
  }

  static const LocalizationsDelegate<HelixLocalizations> delegate =
      _HelixLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en'),
  ];

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @acceptRequestBeforeOpeningChat.
  ///
  /// In en, this message translates to:
  /// **'Accept the request before opening a chat.'**
  String get acceptRequestBeforeOpeningChat;

  /// No description provided for @accountId.
  ///
  /// In en, this message translates to:
  /// **'Account ID'**
  String get accountId;

  /// No description provided for @accountIdCopied.
  ///
  /// In en, this message translates to:
  /// **'Account ID copied'**
  String get accountIdCopied;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @addContact.
  ///
  /// In en, this message translates to:
  /// **'Add Contact'**
  String get addContact;

  /// No description provided for @addContact2.
  ///
  /// In en, this message translates to:
  /// **'Add contact'**
  String get addContact2;

  /// No description provided for @addFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to Favorites'**
  String get addFavorites;

  /// No description provided for @addGroup.
  ///
  /// In en, this message translates to:
  /// **'Add to group'**
  String get addGroup;

  /// No description provided for @addList.
  ///
  /// In en, this message translates to:
  /// **'Add to list'**
  String get addList;

  /// No description provided for @addShortcut.
  ///
  /// In en, this message translates to:
  /// **'Add shortcut'**
  String get addShortcut;

  /// No description provided for @addedQuickList.
  ///
  /// In en, this message translates to:
  /// **'Added to Quick list'**
  String get addedQuickList;

  /// No description provided for @adminServerYoureJoiningShares.
  ///
  /// In en, this message translates to:
  /// **'The admin of the server you\'re joining shares a link like https://their-server.example/join?invite=CODE.'**
  String get adminServerYoureJoiningShares;

  /// No description provided for @allAttendeesWillNotified.
  ///
  /// In en, this message translates to:
  /// **'All attendees will be notified.'**
  String get allAttendeesWillNotified;

  /// No description provided for @allowExport.
  ///
  /// In en, this message translates to:
  /// **'Allow export'**
  String get allowExport;

  /// No description provided for @allowExternalSave.
  ///
  /// In en, this message translates to:
  /// **'Allow external save'**
  String get allowExternalSave;

  /// No description provided for @allowForwarding.
  ///
  /// In en, this message translates to:
  /// **'Allow forwarding'**
  String get allowForwarding;

  /// No description provided for @anomalyLog.
  ///
  /// In en, this message translates to:
  /// **'Anomaly Log'**
  String get anomalyLog;

  /// No description provided for @appLock.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get appLock;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Helix Remote'**
  String get appTitle;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @approveRejectPendingRequestFresh.
  ///
  /// In en, this message translates to:
  /// **'Approve or reject a pending request from a fresh device.'**
  String get approveRejectPendingRequestFresh;

  /// No description provided for @archiveNotAvailableHelixYet.
  ///
  /// In en, this message translates to:
  /// **'Archive is not available in Helix yet'**
  String get archiveNotAvailableHelixYet;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @backupRestore.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get backupRestore;

  /// No description provided for @backupStatus.
  ///
  /// In en, this message translates to:
  /// **'Backup Status'**
  String get backupStatus;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @browsingOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re browsing offline'**
  String get browsingOffline;

  /// No description provided for @callInfo.
  ///
  /// In en, this message translates to:
  /// **'Call info'**
  String get callInfo;

  /// No description provided for @callLink.
  ///
  /// In en, this message translates to:
  /// **'Call link'**
  String get callLink;

  /// No description provided for @callsRequireTurnRelayConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Calls require TURN relay configuration'**
  String get callsRequireTurnRelayConfiguration;

  /// No description provided for @cameraCapture.
  ///
  /// In en, this message translates to:
  /// **'Camera capture'**
  String get cameraCapture;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @cancelCall.
  ///
  /// In en, this message translates to:
  /// **'Cancel call'**
  String get cancelCall;

  /// No description provided for @cancelScheduledCall.
  ///
  /// In en, this message translates to:
  /// **'Cancel scheduled call?'**
  String get cancelScheduledCall;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @changeServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Change Server URL'**
  String get changeServerUrl;

  /// No description provided for @chatBlocksExternalExport.
  ///
  /// In en, this message translates to:
  /// **'This chat blocks external export'**
  String get chatBlocksExternalExport;

  /// No description provided for @chatTheme.
  ///
  /// In en, this message translates to:
  /// **'Chat theme'**
  String get chatTheme;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @clearAllRecentCallsDevice.
  ///
  /// In en, this message translates to:
  /// **'Clear all recent calls from this device?'**
  String get clearAllRecentCallsDevice;

  /// No description provided for @clearCallLog.
  ///
  /// In en, this message translates to:
  /// **'Clear call log'**
  String get clearCallLog;

  /// No description provided for @clearChat.
  ///
  /// In en, this message translates to:
  /// **'Clear chat'**
  String get clearChat;

  /// No description provided for @clearChats.
  ///
  /// In en, this message translates to:
  /// **'Clear chats'**
  String get clearChats;

  /// No description provided for @clearLog.
  ///
  /// In en, this message translates to:
  /// **'Clear this log'**
  String get clearLog;

  /// No description provided for @clearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get clearSelection;

  /// No description provided for @clearsSavedSessionDeviceAccount.
  ///
  /// In en, this message translates to:
  /// **'This clears the saved session on this device. Your account and server data are not deleted.'**
  String get clearsSavedSessionDeviceAccount;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @confirmDestructiveReset.
  ///
  /// In en, this message translates to:
  /// **'Confirm destructive reset'**
  String get confirmDestructiveReset;

  /// No description provided for @connectPersonalServer.
  ///
  /// In en, this message translates to:
  /// **'Connect to a personal server'**
  String get connectPersonalServer;

  /// No description provided for @connectServer.
  ///
  /// In en, this message translates to:
  /// **'Connect a server'**
  String get connectServer;

  /// No description provided for @connectServer2.
  ///
  /// In en, this message translates to:
  /// **'Connect to Server'**
  String get connectServer2;

  /// No description provided for @contactBlocked.
  ///
  /// In en, this message translates to:
  /// **'Contact blocked'**
  String get contactBlocked;

  /// No description provided for @contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contacts;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copyClear.
  ///
  /// In en, this message translates to:
  /// **'Copy & clear'**
  String get copyClear;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @couldNotLoadSecurityHistory.
  ///
  /// In en, this message translates to:
  /// **'Could not load security history. Check your connection and try again.'**
  String get couldNotLoadSecurityHistory;

  /// No description provided for @couldNotProcessDeviceLink.
  ///
  /// In en, this message translates to:
  /// **'Could not process device link. Try again.'**
  String get couldNotProcessDeviceLink;

  /// No description provided for @couldNotRenameDeviceTry.
  ///
  /// In en, this message translates to:
  /// **'Could not rename device. Try again.'**
  String get couldNotRenameDeviceTry;

  /// No description provided for @couldNotReportDeviceLost.
  ///
  /// In en, this message translates to:
  /// **'Could not report device as lost. Try again.'**
  String get couldNotReportDeviceLost;

  /// No description provided for @couldNotRevokeDeviceCheck.
  ///
  /// In en, this message translates to:
  /// **'Could not revoke device. Check your connection and try again.'**
  String get couldNotRevokeDeviceCheck;

  /// No description provided for @couldNotSendMessageTry.
  ///
  /// In en, this message translates to:
  /// **'Could not send message. Try again.'**
  String get couldNotSendMessageTry;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @createBackup.
  ///
  /// In en, this message translates to:
  /// **'Create Backup'**
  String get createBackup;

  /// No description provided for @createGroup.
  ///
  /// In en, this message translates to:
  /// **'Create Group'**
  String get createGroup;

  /// No description provided for @createJoinLink.
  ///
  /// In en, this message translates to:
  /// **'Create Join Link'**
  String get createJoinLink;

  /// No description provided for @databaseKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'Database key is missing'**
  String get databaseKeyMissing;

  /// No description provided for @days.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get days;

  /// No description provided for @days2.
  ///
  /// In en, this message translates to:
  /// **'90 days'**
  String get days2;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @decryptStageValidateThenReplace.
  ///
  /// In en, this message translates to:
  /// **'Decrypt, stage-validate, then replace local state'**
  String get decryptStageValidateThenReplace;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deleteChats.
  ///
  /// In en, this message translates to:
  /// **'Delete chats'**
  String get deleteChats;

  /// No description provided for @deleteEveryone.
  ///
  /// In en, this message translates to:
  /// **'Delete for everyone'**
  String get deleteEveryone;

  /// No description provided for @deleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get deleteGroup;

  /// No description provided for @deleteReset.
  ///
  /// In en, this message translates to:
  /// **'Delete and reset'**
  String get deleteReset;

  /// No description provided for @deletingSelectedCallsNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Deleting selected calls is not available yet'**
  String get deletingSelectedCallsNotAvailable;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devices;

  /// No description provided for @disappearingMessages.
  ///
  /// In en, this message translates to:
  /// **'Disappearing messages'**
  String get disappearingMessages;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// No description provided for @displayNameUpdated.
  ///
  /// In en, this message translates to:
  /// **'Display name updated'**
  String get displayNameUpdated;

  /// No description provided for @document.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get document;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @editMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit message'**
  String get editMessage;

  /// No description provided for @editNickname.
  ///
  /// In en, this message translates to:
  /// **'Edit nickname'**
  String get editNickname;

  /// No description provided for @edited.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get edited;

  /// No description provided for @encryptAppDataArgonId.
  ///
  /// In en, this message translates to:
  /// **'Encrypt app data with Argon2id recovery protection'**
  String get encryptAppDataArgonId;

  /// No description provided for @enterUrlHelixRemoteBackend.
  ///
  /// In en, this message translates to:
  /// **'Enter the URL of your Helix Remote backend.'**
  String get enterUrlHelixRemoteBackend;

  /// No description provided for @existingDatabaseWasFoundBut.
  ///
  /// In en, this message translates to:
  /// **'An existing database was found but its encryption key is not available in secure storage. A destructive reset is required to continue.'**
  String get existingDatabaseWasFoundBut;

  /// No description provided for @exportChat.
  ///
  /// In en, this message translates to:
  /// **'Export chat'**
  String get exportChat;

  /// No description provided for @exportMyData.
  ///
  /// In en, this message translates to:
  /// **'Export my data'**
  String get exportMyData;

  /// No description provided for @failedStart.
  ///
  /// In en, this message translates to:
  /// **'Failed to start'**
  String get failedStart;

  /// No description provided for @findContactsAlreadyHelixPhone.
  ///
  /// In en, this message translates to:
  /// **'Find contacts already on Helix? Phone numbers are hashed before comparison and never sent in the clear.'**
  String get findContactsAlreadyHelixPhone;

  /// No description provided for @firstSeen.
  ///
  /// In en, this message translates to:
  /// **'First seen'**
  String get firstSeen;

  /// No description provided for @foundViaPhoneContacts.
  ///
  /// In en, this message translates to:
  /// **'Found via phone contacts'**
  String get foundViaPhoneContacts;

  /// No description provided for @groupAddPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Group-Add Privacy'**
  String get groupAddPrivacy;

  /// No description provided for @groupAddPrivacy2.
  ///
  /// In en, this message translates to:
  /// **'Group-add privacy'**
  String get groupAddPrivacy2;

  /// No description provided for @groups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groups;

  /// No description provided for @helixAdminFreeCompanionApp.
  ///
  /// In en, this message translates to:
  /// **'Helix Admin is a free companion app that sets up and manages a Helix Remote server on your own PC or a rented VPS. You stay in full control of your data.'**
  String get helixAdminFreeCompanionApp;

  /// No description provided for @helixProtectsChatEndEnd.
  ///
  /// In en, this message translates to:
  /// **'Helix protects this chat with end-to-end encryption. Verify this contact on a trusted device before sharing sensitive information.'**
  String get helixProtectsChatEndEnd;

  /// No description provided for @hideNotificationPreviews.
  ///
  /// In en, this message translates to:
  /// **'Hide notification previews'**
  String get hideNotificationPreviews;

  /// No description provided for @hostOwnServer.
  ///
  /// In en, this message translates to:
  /// **'Host your own server'**
  String get hostOwnServer;

  /// No description provided for @hours.
  ///
  /// In en, this message translates to:
  /// **'24 hours'**
  String get hours;

  /// No description provided for @howWouldLikeGetStarted.
  ///
  /// In en, this message translates to:
  /// **'How would you like to get started?'**
  String get howWouldLikeGetStarted;

  /// No description provided for @image.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get image;

  /// No description provided for @immediate.
  ///
  /// In en, this message translates to:
  /// **'Immediate'**
  String get immediate;

  /// No description provided for @installHelixAdminMachineWill.
  ///
  /// In en, this message translates to:
  /// **'1. Install Helix Admin on the machine that will run your server.\n2. Follow its Self-Hosting Guide to install and configure the backend.\n3. Once it\'s running, Helix Admin gives you a shareable invite link.\n4. Come back here and choose \"Join a personal server\" with that link.'**
  String get installHelixAdminMachineWill;

  /// No description provided for @invite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get invite;

  /// No description provided for @inviteMember.
  ///
  /// In en, this message translates to:
  /// **'Invite Member'**
  String get inviteMember;

  /// No description provided for @inviteMember2.
  ///
  /// In en, this message translates to:
  /// **'Invite member'**
  String get inviteMember2;

  /// No description provided for @inviteServerOnlyContinueIf.
  ///
  /// In en, this message translates to:
  /// **'Your invite is for this server. Only continue if you recognise it.'**
  String get inviteServerOnlyContinueIf;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// No description provided for @joinLink.
  ///
  /// In en, this message translates to:
  /// **'Join Link'**
  String get joinLink;

  /// No description provided for @joinLink2.
  ///
  /// In en, this message translates to:
  /// **'Join link'**
  String get joinLink2;

  /// No description provided for @joinServer.
  ///
  /// In en, this message translates to:
  /// **'Join this server?'**
  String get joinServer;

  /// No description provided for @keep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keep;

  /// No description provided for @keyFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Key fingerprint'**
  String get keyFingerprint;

  /// No description provided for @leaveGroup.
  ///
  /// In en, this message translates to:
  /// **'Leave group'**
  String get leaveGroup;

  /// No description provided for @linkCopiedClipboard.
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get linkCopiedClipboard;

  /// No description provided for @linkCopiedPasteAnywhereShare.
  ///
  /// In en, this message translates to:
  /// **'Link copied — paste it anywhere to share'**
  String get linkCopiedPasteAnywhereShare;

  /// No description provided for @linkNewDevice.
  ///
  /// In en, this message translates to:
  /// **'Link New Device'**
  String get linkNewDevice;

  /// No description provided for @linkTokenCopied.
  ///
  /// In en, this message translates to:
  /// **'Link token copied'**
  String get linkTokenCopied;

  /// No description provided for @livePhoto.
  ///
  /// In en, this message translates to:
  /// **'Live Photo'**
  String get livePhoto;

  /// No description provided for @loadEarlierMessages.
  ///
  /// In en, this message translates to:
  /// **'Load earlier messages'**
  String get loadEarlierMessages;

  /// No description provided for @lockChats.
  ///
  /// In en, this message translates to:
  /// **'Lock chats'**
  String get lockChats;

  /// No description provided for @lockedChatsStrictModeAlways.
  ///
  /// In en, this message translates to:
  /// **'Locked chats and strict mode always redact content'**
  String get lockedChatsStrictModeAlways;

  /// No description provided for @logExportedCleared.
  ///
  /// In en, this message translates to:
  /// **'Log exported and cleared.'**
  String get logExportedCleared;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logOut;

  /// No description provided for @logSavedToDocuments.
  ///
  /// In en, this message translates to:
  /// **'Log saved to Documents\\Helix Remote\\'**
  String get logSavedToDocuments;

  /// No description provided for @manageMembers.
  ///
  /// In en, this message translates to:
  /// **'Manage members'**
  String get manageMembers;

  /// No description provided for @manageStorage.
  ///
  /// In en, this message translates to:
  /// **'Manage storage'**
  String get manageStorage;

  /// No description provided for @markRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get markRead;

  /// No description provided for @markUnread.
  ///
  /// In en, this message translates to:
  /// **'Mark as unread'**
  String get markUnread;

  /// No description provided for @markUnreadNotAvailableYet.
  ///
  /// In en, this message translates to:
  /// **'Mark as unread is not available yet'**
  String get markUnreadNotAvailableYet;

  /// No description provided for @renameGroup.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get renameGroup;

  /// No description provided for @pollLabel.
  ///
  /// In en, this message translates to:
  /// **'Poll'**
  String get pollLabel;

  /// No description provided for @pollClosedLabel.
  ///
  /// In en, this message translates to:
  /// **'Poll closed'**
  String get pollClosedLabel;

  /// No description provided for @pollNoOptions.
  ///
  /// In en, this message translates to:
  /// **'No options'**
  String get pollNoOptions;

  /// No description provided for @pollMultipleChoices.
  ///
  /// In en, this message translates to:
  /// **'Multiple choices allowed'**
  String get pollMultipleChoices;

  /// No description provided for @eventLabel.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get eventLabel;

  /// No description provided for @eventCancelledLabel.
  ///
  /// In en, this message translates to:
  /// **'Event cancelled'**
  String get eventCancelledLabel;

  /// No description provided for @eventPlusOnes.
  ///
  /// In en, this message translates to:
  /// **'Plus ones allowed'**
  String get eventPlusOnes;

  /// No description provided for @locationLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationLabel;

  /// No description provided for @liveLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Live location'**
  String get liveLocationLabel;

  /// No description provided for @locationAccuracyUnknown.
  ///
  /// In en, this message translates to:
  /// **'Accuracy unknown'**
  String get locationAccuracyUnknown;

  /// No description provided for @locationSharingStopped.
  ///
  /// In en, this message translates to:
  /// **'Sharing stopped'**
  String get locationSharingStopped;

  /// No description provided for @stickerLabel.
  ///
  /// In en, this message translates to:
  /// **'Sticker'**
  String get stickerLabel;

  /// No description provided for @stickerImage.
  ///
  /// In en, this message translates to:
  /// **'Image sticker'**
  String get stickerImage;

  /// No description provided for @stickerVideo.
  ///
  /// In en, this message translates to:
  /// **'Video sticker'**
  String get stickerVideo;

  /// No description provided for @saveSticker.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveSticker;

  /// No description provided for @renameGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get renameGroupTitle;

  /// No description provided for @groupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupNameLabel;

  /// No description provided for @mediaLinksDocs.
  ///
  /// In en, this message translates to:
  /// **'Media, links, and docs'**
  String get mediaLinksDocs;

  /// No description provided for @memberManagement.
  ///
  /// In en, this message translates to:
  /// **'Member Management'**
  String get memberManagement;

  /// No description provided for @minute.
  ///
  /// In en, this message translates to:
  /// **'1 minute'**
  String get minute;

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'5 minutes'**
  String get minutes;

  /// No description provided for @minutes2.
  ///
  /// In en, this message translates to:
  /// **'15 minutes'**
  String get minutes2;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @muteNotifications.
  ///
  /// In en, this message translates to:
  /// **'Mute notifications'**
  String get muteNotifications;

  /// No description provided for @newCall.
  ///
  /// In en, this message translates to:
  /// **'New call'**
  String get newCall;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChat;

  /// No description provided for @noAnomaliesRecordedYet.
  ///
  /// In en, this message translates to:
  /// **'No anomalies recorded yet.'**
  String get noAnomaliesRecordedYet;

  /// No description provided for @noDisplayNameWasProvided.
  ///
  /// In en, this message translates to:
  /// **'No display name was provided. Your phone number will be used as your display name until you change it in Settings.'**
  String get noDisplayNameWasProvided;

  /// No description provided for @noGroupsYet.
  ///
  /// In en, this message translates to:
  /// **'No groups yet'**
  String get noGroupsYet;

  /// No description provided for @noMatchingCountries.
  ///
  /// In en, this message translates to:
  /// **'No matching countries'**
  String get noMatchingCountries;

  /// No description provided for @noMembers.
  ///
  /// In en, this message translates to:
  /// **'No members'**
  String get noMembers;

  /// No description provided for @noSecurityHistoryFound.
  ///
  /// In en, this message translates to:
  /// **'No security history found.'**
  String get noSecurityHistoryFound;

  /// No description provided for @noServerConnectedSoMessaging.
  ///
  /// In en, this message translates to:
  /// **'No server is connected, so messaging, calls, and contacts aren\'t available yet. Connect a server anytime to get started.'**
  String get noServerConnectedSoMessaging;

  /// No description provided for @noSharedMediaYet.
  ///
  /// In en, this message translates to:
  /// **'No shared media yet'**
  String get noSharedMediaYet;

  /// No description provided for @notAnswered.
  ///
  /// In en, this message translates to:
  /// **'Not answered'**
  String get notAnswered;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @notificationPolicy.
  ///
  /// In en, this message translates to:
  /// **'Notification Policy'**
  String get notificationPolicy;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @originalMessageNotFound.
  ///
  /// In en, this message translates to:
  /// **'Original message not found'**
  String get originalMessageNotFound;

  /// No description provided for @pasteInviteLink.
  ///
  /// In en, this message translates to:
  /// **'Paste your invite link'**
  String get pasteInviteLink;

  /// No description provided for @permanentlyDeleteAccountAllIts.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your account and all its data'**
  String get permanentlyDeleteAccountAllIts;

  /// No description provided for @previewApplyStrongestDefaults.
  ///
  /// In en, this message translates to:
  /// **'Preview and apply strongest defaults'**
  String get previewApplyStrongestDefaults;

  /// No description provided for @privacyCheckup.
  ///
  /// In en, this message translates to:
  /// **'Privacy checkup'**
  String get privacyCheckup;

  /// No description provided for @privacySecurity.
  ///
  /// In en, this message translates to:
  /// **'Privacy and security'**
  String get privacySecurity;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @protectedByAes.
  ///
  /// In en, this message translates to:
  /// **'Protected by military-grade AES-256 encryption'**
  String get protectedByAes;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @remoteConfigurationRequired.
  ///
  /// In en, this message translates to:
  /// **'Remote configuration required'**
  String get remoteConfigurationRequired;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @removeContact.
  ///
  /// In en, this message translates to:
  /// **'Remove contact'**
  String get removeContact;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @renameDevice.
  ///
  /// In en, this message translates to:
  /// **'Rename Device'**
  String get renameDevice;

  /// No description provided for @report.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get report;

  /// No description provided for @reportLost.
  ///
  /// In en, this message translates to:
  /// **'Report Lost'**
  String get reportLost;

  /// No description provided for @reportLostDevice.
  ///
  /// In en, this message translates to:
  /// **'Report Lost Device'**
  String get reportLostDevice;

  /// No description provided for @requireAdminApproval.
  ///
  /// In en, this message translates to:
  /// **'Require admin approval'**
  String get requireAdminApproval;

  /// No description provided for @resetHelixRemote.
  ///
  /// In en, this message translates to:
  /// **'Reset Helix Remote'**
  String get resetHelixRemote;

  /// No description provided for @resetRequired.
  ///
  /// In en, this message translates to:
  /// **'Reset Required'**
  String get resetRequired;

  /// No description provided for @restoreBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore Backup'**
  String get restoreBackup;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @revoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get revoke;

  /// No description provided for @revokeDevice.
  ///
  /// In en, this message translates to:
  /// **'Revoke Device'**
  String get revokeDevice;

  /// No description provided for @revokeLink.
  ///
  /// In en, this message translates to:
  /// **'Revoke link'**
  String get revokeLink;

  /// No description provided for @ringing.
  ///
  /// In en, this message translates to:
  /// **'Ringing'**
  String get ringing;

  /// No description provided for @runOwnHelixRemoteServer.
  ///
  /// In en, this message translates to:
  /// **'Run your own Helix Remote server'**
  String get runOwnHelixRemoteServer;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveJsonFileOutsideEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Save JSON file outside encrypted app DB'**
  String get saveJsonFileOutsideEncrypted;

  /// No description provided for @scannedDocument.
  ///
  /// In en, this message translates to:
  /// **'Scanned document'**
  String get scannedDocument;

  /// No description provided for @scannedLinksCheckedExpiryReplay.
  ///
  /// In en, this message translates to:
  /// **'Scanned links are checked for expiry and replay before a request is sent.'**
  String get scannedLinksCheckedExpiryReplay;

  /// No description provided for @scheduleCall.
  ///
  /// In en, this message translates to:
  /// **'Schedule a call'**
  String get scheduleCall;

  /// No description provided for @scheduledCalls.
  ///
  /// In en, this message translates to:
  /// **'Scheduled calls'**
  String get scheduledCalls;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @securityHistory.
  ///
  /// In en, this message translates to:
  /// **'Security History'**
  String get securityHistory;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @selectNewGroupOwnerWill.
  ///
  /// In en, this message translates to:
  /// **'Select the new group owner. You will remain an admin.'**
  String get selectNewGroupOwnerWill;

  /// No description provided for @selectedChatsLocked.
  ///
  /// In en, this message translates to:
  /// **'Selected chats locked'**
  String get selectedChatsLocked;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @sendContactRequest.
  ///
  /// In en, this message translates to:
  /// **'Send contact request?'**
  String get sendContactRequest;

  /// No description provided for @sendMedia.
  ///
  /// In en, this message translates to:
  /// **'Send media'**
  String get sendMedia;

  /// No description provided for @sendRequest.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get sendRequest;

  /// No description provided for @sendViaWhatsappEmailAny.
  ///
  /// In en, this message translates to:
  /// **'Send this via WhatsApp, email, or any other channel. The link expires in 7 days and opens a confirmation screen before any contact request is sent.'**
  String get sendViaWhatsappEmailAny;

  /// No description provided for @serverConnection.
  ///
  /// In en, this message translates to:
  /// **'Server connection'**
  String get serverConnection;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share...'**
  String get share;

  /// No description provided for @shareAccountIdOthersSo.
  ///
  /// In en, this message translates to:
  /// **'Share your account ID with others so they can add you as a contact.'**
  String get shareAccountIdOthersSo;

  /// No description provided for @shareLinkSomeoneSoThey.
  ///
  /// In en, this message translates to:
  /// **'Share this link with someone so they can add you as a contact.'**
  String get shareLinkSomeoneSoThey;

  /// No description provided for @shareProfile.
  ///
  /// In en, this message translates to:
  /// **'Share profile'**
  String get shareProfile;

  /// No description provided for @silenceUnknownCallers.
  ///
  /// In en, this message translates to:
  /// **'Silence unknown callers'**
  String get silenceUnknownCallers;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @skipDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Skip display name?'**
  String get skipDisplayName;

  /// No description provided for @somethingWentWrongLoadingScreen.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong loading this screen.'**
  String get somethingWentWrongLoadingScreen;

  /// No description provided for @sortByName.
  ///
  /// In en, this message translates to:
  /// **'Sort by name'**
  String get sortByName;

  /// No description provided for @sortByRecent.
  ///
  /// In en, this message translates to:
  /// **'Sort by recent'**
  String get sortByRecent;

  /// No description provided for @startingHelixRemote.
  ///
  /// In en, this message translates to:
  /// **'Starting Helix Remote...'**
  String get startingHelixRemote;

  /// No description provided for @startingSoon.
  ///
  /// In en, this message translates to:
  /// **'Starting soon'**
  String get startingSoon;

  /// No description provided for @startupError.
  ///
  /// In en, this message translates to:
  /// **'Startup Error'**
  String get startupError;

  /// No description provided for @strictAccountSettings.
  ///
  /// In en, this message translates to:
  /// **'Strict account settings'**
  String get strictAccountSettings;

  /// No description provided for @syncContacts.
  ///
  /// In en, this message translates to:
  /// **'Sync contacts'**
  String get syncContacts;

  /// No description provided for @transfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get transfer;

  /// No description provided for @transferOwnership.
  ///
  /// In en, this message translates to:
  /// **'Transfer Ownership'**
  String get transferOwnership;

  /// No description provided for @transferOwnership2.
  ///
  /// In en, this message translates to:
  /// **'Transfer ownership'**
  String get transferOwnership2;

  /// No description provided for @tryDifferentTitleDescription.
  ///
  /// In en, this message translates to:
  /// **'Try a different title or description.'**
  String get tryDifferentTitleDescription;

  /// No description provided for @typeDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Type DELETE to confirm.'**
  String get typeDeleteConfirm;

  /// No description provided for @unknownCallsDoNotRing.
  ///
  /// In en, this message translates to:
  /// **'Unknown calls do not ring and are rate-limited'**
  String get unknownCallsDoNotRing;

  /// No description provided for @validateLink.
  ///
  /// In en, this message translates to:
  /// **'Validate link'**
  String get validateLink;

  /// No description provided for @verificationCodePlaceholderNotSecure.
  ///
  /// In en, this message translates to:
  /// **'This verification code is a placeholder, not a secure delivery channel yet.'**
  String get verificationCodePlaceholderNotSecure;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @verifySecurityCode.
  ///
  /// In en, this message translates to:
  /// **'Verify security code'**
  String get verifySecurityCode;

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get video;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @viewContact.
  ///
  /// In en, this message translates to:
  /// **'View contact'**
  String get viewContact;

  /// No description provided for @viewOnce.
  ///
  /// In en, this message translates to:
  /// **'View once'**
  String get viewOnce;

  /// No description provided for @voiceMessagesNotAvailableYet.
  ///
  /// In en, this message translates to:
  /// **'Voice messages are not available yet'**
  String get voiceMessagesNotAvailableYet;

  /// No description provided for @waitingOtherPersonAcceptRequest.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the other person to accept your request.'**
  String get waitingOtherPersonAcceptRequest;

  /// No description provided for @welcomeHelixRemote.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Helix Remote'**
  String get welcomeHelixRemote;

  /// No description provided for @whatShouldPeopleSeeName.
  ///
  /// In en, this message translates to:
  /// **'What should people see as your name?'**
  String get whatShouldPeopleSeeName;

  /// No description provided for @agreeTermsAndPrivacy.
  ///
  /// In en, this message translates to:
  /// **'I agree to the Terms of Service and Privacy Policy'**
  String get agreeTermsAndPrivacy;

  /// No description provided for @legalVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get legalVersionLabel;

  /// No description provided for @enterRecoveryCode.
  ///
  /// In en, this message translates to:
  /// **'Enter recovery code'**
  String get enterRecoveryCode;

  /// No description provided for @legalEffectiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Effective'**
  String get legalEffectiveLabel;

  /// No description provided for @personalServerOperatorPolicies.
  ///
  /// In en, this message translates to:
  /// **'Personal servers are governed by their own operator policies.'**
  String get personalServerOperatorPolicies;

  /// No description provided for @phoneAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'Phone number already registered'**
  String get phoneAlreadyRegistered;

  /// No description provided for @phoneAlreadyRegisteredRecoveryMessage.
  ///
  /// In en, this message translates to:
  /// **'This phone number already has a Helix account. Would you like to enter a recovery code and restore that account?'**
  String get phoneAlreadyRegisteredRecoveryMessage;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @readLegalDocuments.
  ///
  /// In en, this message translates to:
  /// **'Read the legal documents'**
  String get readLegalDocuments;

  /// No description provided for @reviewGlobalLegalDocuments.
  ///
  /// In en, this message translates to:
  /// **'Review the legal documents before creating a Global account.'**
  String get reviewGlobalLegalDocuments;

  /// No description provided for @terms.
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get terms;

  /// No description provided for @willPermanentlyDeleteAllLocal.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete all local account data, the encrypted database, and all stored keys. This cannot be undone.'**
  String get willPermanentlyDeleteAllLocal;

  /// No description provided for @pendingDeviceLinkConfirmElsewhere.
  ///
  /// In en, this message translates to:
  /// **'Open Helix on that device and confirm the code it shows. The code is never sent to this device.'**
  String get pendingDeviceLinkConfirmElsewhere;

  /// No description provided for @sendCrashReports.
  ///
  /// In en, this message translates to:
  /// **'Send crash reports'**
  String get sendCrashReports;

  /// No description provided for @sendCrashReportsDescription.
  ///
  /// In en, this message translates to:
  /// **'Redacted crash details go only to the server you are connected to, and land in that server\'s own log. Off means nothing is ever sent.'**
  String get sendCrashReportsDescription;

  /// No description provided for @sendMinimalAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Send minimal analytics'**
  String get sendMinimalAnalytics;

  /// No description provided for @sendMinimalAnalyticsDescription.
  ///
  /// In en, this message translates to:
  /// **'No usage data is sent.'**
  String get sendMinimalAnalyticsDescription;

  /// No description provided for @sendMinimalAnalyticsActiveDescription.
  ///
  /// In en, this message translates to:
  /// **'Only the categories listed in the privacy policy, never message content.'**
  String get sendMinimalAnalyticsActiveDescription;

  /// No description provided for @telemetrySinkUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Reporting is not available right now: the reporter has no sink configured. The preference is saved and will apply once a connection is established.'**
  String get telemetrySinkUnavailable;

  /// No description provided for @telemetryPreferencesSaved.
  ///
  /// In en, this message translates to:
  /// **'Telemetry preferences saved.'**
  String get telemetryPreferencesSaved;

  /// No description provided for @reportDisclosure.
  ///
  /// In en, this message translates to:
  /// **'Your server operator will see that you reported this contact and the reason you chose. They will not see your messages.'**
  String get reportDisclosure;

  /// No description provided for @reportQueued.
  ///
  /// In en, this message translates to:
  /// **'Report queued for your server operator.'**
  String get reportQueued;

  /// No description provided for @reportOnlyOneToOne.
  ///
  /// In en, this message translates to:
  /// **'Open a one-to-one chat to report a contact.'**
  String get reportOnlyOneToOne;
}

class _HelixLocalizationsDelegate
    extends LocalizationsDelegate<HelixLocalizations> {
  const _HelixLocalizationsDelegate();

  @override
  Future<HelixLocalizations> load(Locale locale) {
    return SynchronousFuture<HelixLocalizations>(
      lookupHelixLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bn', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_HelixLocalizationsDelegate old) => false;
}

HelixLocalizations lookupHelixLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return HelixLocalizationsBn();
    case 'en':
      return HelixLocalizationsEn();
  }

  throw FlutterError(
    'HelixLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
