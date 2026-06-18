const String kLobbyMulticastGroup     = '239.1.2.3';
const int    kLobbyMulticastPort      = 42420;
const int    kLobbyProtocolVersion    = 1;

const Duration kLobbyBroadcastInterval  = Duration(seconds: 3);
const Duration kLobbyDiscoveryWindow    = Duration(seconds: 7);
const Duration kLobbyHostTimeout        = Duration(seconds: 10);
const Duration kLobbyElectionJitterBase = Duration(milliseconds: 500);
const int      kLobbyElectionJitterNoise = 100;
const Duration kLobbyHandoffReadyTimeout  = Duration(seconds: 5);
const Duration kLobbyHandoffCommitTimeout = Duration(seconds: 10);
const Duration kLobbyRecoveryWindow      = Duration(seconds: 10);

const int kLobbyMaxUdpBytes      = 1400;
const int kLobbyMaxTcpFrameBytes = 65536;
const int kLobbyMsgIdCacheSize   = 500;

const String kLobbyMulticastChannel = 'com.helix.app/multicast_lock';

// Frame type constants
const String kFtAnnounce          = 'A';
const String kFtDiscoveryRequest  = 'DR';
const String kFtJoin              = 'JOIN';
const String kFtJoined            = 'JOINED';
const String kFtMemberUpdate      = 'MU';
const String kFtMsg               = 'MSG';
const String kFtPing              = 'PING';
const String kFtPong              = 'PONG';
const String kFtHostXferPrepare   = 'HTP';
const String kFtHostXferReady     = 'HTR';
const String kFtHostXferCommit    = 'HTC';
const String kFtLeave             = 'LEAVE';
const String kFtError             = 'ERR';
