/// Helix Remote v2 engine: the messaging core (ADR-027, plan §6). See
/// MODULE.md.
library;

export 'src/account/account_service.dart' show AccountService, NewDeviceLink;
export 'src/account/device_service.dart' show DeviceService;
export 'src/account/session_token_store.dart' show DbSessionTokenStore;
export 'src/config.dart' show EngineConfig;
export 'src/engine.dart' show Engine;
export 'src/errors.dart';
export 'src/events.dart';
export 'src/features/chats_service.dart' show ChatsService;
export 'src/features/people_service.dart'
    show PeopleService, PersonNaming, PhoneBookSyncResult;
export 'src/features/phone_book.dart';
export 'src/features/presence_service.dart' show PresenceService;
export 'src/features/push_service.dart' show PushService;
export 'src/features/settings_service.dart' show SettingsService;
export 'src/messaging/inbound_runner.dart' show SyncSummary;
export 'src/messaging/kinds.dart' show MessageKinds;
export 'src/settings_keys.dart' show EngineSettings;
export 'src/util/backoff.dart' show Backoff;
export 'src/util/ids.dart' show Clock;
export 'src/util/masking.dart' show maskPhone, shortId;
