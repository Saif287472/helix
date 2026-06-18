import 'dart:io';

// Protocol version
const int kProtocolMajor = 3;
const int kProtocolMinor = 2;

// Capability flags (bitmask)
const int kCapFileTransfer = 1 << 0;
const int kCapReactions = 1 << 1;
const int kCapTypingIndicator = 1 << 2;
const int kCapReadReceipt = 1 << 3;
const int kCapForwardSecrecy = 1 << 4;

// V4 capability flags — advertised only when the feature is active.
// Add each to kCapAll once the corresponding phase is implemented.
const int kCapFileResume = 1 << 5; // Phase 3.3: pause/resume transfers
const int kCapEphemeralMedia = 1 << 6; // Phase 3.4: RAM-only media
const int kCapGroups = 1 << 7; // Phase 4: P2P group chat
const int kCapWebRTC = 1 << 8; // Phase 5: local voice/video

// All capabilities this build supports. Update as phases are completed.
const int kCapAll =
    kCapFileTransfer |
    kCapReactions |
    kCapTypingIndicator |
    kCapReadReceipt |
    kCapForwardSecrecy |
    kCapFileResume |
    kCapEphemeralMedia |
    kCapGroups |
    kCapWebRTC;

// Discovery
const String kMdnsServiceType = '_helix._tcp';
const int kUdpDiscoveryPort = 42424;
const int kUdpMaxPacketSize = 512;
const int kUdpCodeLookupMaxSize = 1024;
const Duration kPresenceInterval = Duration(seconds: 5);
const Duration kPeerStaleDuration = Duration(seconds: 15);

// Requests
const Duration kRequestTtl = Duration(seconds: 60);
const int kMaxNearbyPeers = 20;
const int kMaxPendingRequests = 20;
const int kMaxActiveChats = 10;

// Messages
const int kMaxMessageBytes = 16 * 1024; // 16 KiB
const int kMaxThreadMessages = 5000;
const int kMaxThreadBytes = 25 * 1024 * 1024; // 25 MiB
const int kMaxGroupDedupIds = 1000;
const int kMaxRetainedGroupMessages = 500;
const int kMaxRetainedLobbyMessages = 500;

// Rate limiting
const int kMaxRequestsPerSourcePerMinute = 5;
const int kMaxGlobalRequestsPerMinute = 30;
const Duration kRequestCooldown = Duration(seconds: 10);

// One-way messages
const Duration kOneWayMessageTtl = Duration(minutes: 5);
const int kMaxOneWaySendsPerTargetPerMinute = 5;

// Rekey thresholds
const int kRekeyMessageCount = 10000;
const Duration kRekeyDuration = Duration(hours: 1);

// Keepalive
const Duration kKeepaliveInterval = Duration(seconds: 5);
const Duration kKeepaliveTimeout = Duration(seconds: 15);

// Secret code search
const Duration kCodeSearchTimeout = Duration(seconds: 10);

// Platform detection
bool get isAndroid => Platform.isAndroid;
bool get isWindows => Platform.isWindows;
bool get isDesktop => Platform.isWindows;

// Android foreground service method channel
const String kMethodChannelName = 'com.helix.app/foreground';

// App branding
const String kAppLogoAsset = 'assets/logo.png';

// Windows local-notification identity (flutter_local_notifications requires
// these to be fixed and stable across launches — do not regenerate the GUID).
const String kWindowsAppUserModelId = 'com.helix.app';
const String kWindowsNotificationGuid = '17b09742-cd2c-45d4-b0fe-52814bfd70ae';

// mDNS platform channels (native NsdManager on Android, WinRT on Windows)
const String kMdnsMethodChannel = 'com.helix.app/mdns';
const String kMdnsEventChannel = 'com.helix.app/mdns/events';

// QR code discovery
const Duration kQrValidityDuration = Duration(minutes: 5);

// Auto-reconnect (2.4)
const int kMaxReconnectAttempts = 5;
const Duration kReconnectBaseDelay = Duration(seconds: 3);
const Duration kReconnectMaxDelay = Duration(seconds: 30);
// Within this window a dropped connection resumes silently (no accept tap needed).
const Duration kAutoResumeWindow = Duration(minutes: 5);

// Stale peer threshold for fading visual (2.3)
const Duration kPeerStaleThreshold = Duration(seconds: 10);

// Secure storage keys
const String kKeyIdentityCert = 'identity_cert_pem';
const String kKeyIdentityPrivate = 'identity_key_pem';
const String kKeyDisplayName = 'display_name';
const String kKeySecretCodeVerifier = 'secret_code_verifier';
const String kKeyDiscoverable = 'discoverable';
const String kKeyFirstRunDone = 'first_run_done';
const String kKeySecretCode = 'secret_code';
const String kKeyKnownPeers = 'known_peers';
const String kKeyNotifyShowSender = 'notify_show_sender';
const String kKeyNotifySound = 'notify_sound';
const String kKeyThemeMode = 'theme_mode';
const String kKeyAccentColor = 'accent_color';
const String kKeyAmoledDark = 'amoled_dark';
const String kKeyCopyEnabled = 'copy_enabled';
const String kKeyScreenshotProtect = 'screenshot_protect';
const String kKeyReadReceiptsEnabled = 'read_receipts_enabled';
const String kKeyTypingIndicatorsEnabled = 'typing_indicators_enabled';
const String kKeyHomeWelcomeDismissed = 'home_welcome_dismissed';
const String kKeyBiometricLock = 'biometric_lock';
const String kKeyLockAfterMinutes = 'lock_after_minutes';
const String kKeyRingtoneAsset = 'ringtone_asset';

// Incoming-call ringtones — bundled under assets/sounds/, selectable in
// Settings → Other Settings. kDefaultRingtoneAsset is the fixed fallback
// and must always remain present in kAvailableRingtoneAssets.
const String kDefaultRingtoneAsset = 'Helix_Default.mp3';
const List<String> kAvailableRingtoneAssets = [
  kDefaultRingtoneAsset,
  'Bright_Horizon.mp3',
  'Classic_Call.mp3',
  'Crystal_Chime.mp3',
  'Deep_Blue_Dream.mp3',
  'Echo_Drop.mp3',
  'Euphoria.mp3',
  'Gentle_Notify.mp3',
  'Modern_Ring.mp3',
  'Morning_Light.mp3',
  'Mystic_Quest.mp3',
  'Night_Drive.mp3',
  'Pulse_Drop.mp3',
  'Quiet_Keys.mp3',
  'Rising_Tide.mp3',
  'Silver_Bell.mp3',
  'Soft_Pulse.mp3',
  'Soft_Whisper.mp3',
  'Tranquil_Shore.mp3',
  'Twilight_Ring.mp3',
  'Velvet_Tone.mp3',
];

// Argon2id parameters (tuned for ~500ms on mid-range 2022 Android)
const int kArgon2Time = 3;
const int kArgon2Memory = 65536; // 64 MiB
const int kArgon2Parallelism = 1;
const int kArgon2HashLength = 32;

// TLS / identity
const int kDeviceSuffixBytes = 2;
const int kRequestIdBytes = 16;
const int kSessionIdBytes = 16;
const int kChallengeBytes = 32;
const int kSaltBytes = 16;

// Display name constraints
const int kDisplayNameMin = 2;
const int kDisplayNameMax = 32;

// Secret code constraints
const int kSecretCodeMin = 8;
const int kSecretCodeMax = 64;

// Diceware passphrase generation (uses assets/eff_large_wordlist.txt, the
// canonical 7776-word EFF large list).
const int kDicewareWordCount = 3;

// Frame / TCP
const int kFrameLengthPrefixBytes = 4;
const int kMaxFrameBytes = 16 * 1024 * 1024; // 16 MiB — accommodates file chunks
const int kMaxTextFrameBytes = 65536; // 64 KiB cap for text/control frames
const int kMaxFileFrameBytes =
    16 * 1024 * 1024; // 16 MiB for file transfer chunks

// File transfer (3.1).
const int kFileChunkSize = 512 * 1024; // 512 KiB per chunk
const int kMaxFileBytes = 16 * 1024 * 1024; // 16 MiB max file size
const int kFileAutoAcceptImageBytes =
    5 * 1024 * 1024; // 5 MiB auto-accept threshold for images

// Ephemeral media (3.4) — chunk size is smaller than kMaxFrameBytes to leave
// room for CBOR field overhead when the frame is encoded.
const int kEphemeralMediaChunkSize = 60 * 1024; // 60 KiB per chunk
const int kEphemeralImageMaxBytes =
    3 * 1024 * 1024; // 3 MiB max after compression
const int kEphemeralVoiceMaxBytes =
    5 * 1024 * 1024; // 5 MiB max for voice notes
const int kEphemeralCacheMaxBytes = 50 * 1024 * 1024; // 50 MiB total RAM budget

// Database
const int kMaxDbSizeBytes = 256 * 1024 * 1024; // 256 MiB
const int kDefaultMessagePageSize = 50;
const String kDatabaseFileName = 'helix.db';

// Session watchdog
const Duration kSessionStartTimeout = Duration(seconds: 10);

// Peer heartbeat
const Duration kPeerHeartbeatInterval = Duration(seconds: 5);
