class RemoteApiEndpoints {
  RemoteApiEndpoints(Uri baseUri) : _origin = _normalizeOrigin(baseUri);

  final Uri _origin;

  Uri get accountsRegister => api('accounts/register');
  Uri get accountsPhoneOtpRequest => api('accounts/phone/otp/request');
  Uri accountsInviteLookup(String inviteCode) => api(
    'accounts/invite/lookup',
    queryParameters: {'invite_code': inviteCode},
  );
  Uri get accountsInviteAutoIssue => api('accounts/invite/auto-issue');
  Uri get serverInfo => api('server/info');
  Uri get contactsDiscoverySalt => api('contacts/discovery-salt');
  Uri get contactsMatch => api('contacts/match');
  Uri accountsChallenge({
    required String accountId,
    required String deviceId,
    String? purpose,
  }) => api(
    'accounts/challenge',
    queryParameters: {
      'account_id': accountId,
      'device_id': deviceId,
      'purpose': ?purpose,
    },
  );
  Uri get accountsLogin => api('accounts/login');
  Uri get accountsRefresh => api('accounts/refresh');
  Uri get accountsDevices => api('accounts/devices');
  Uri get accountsDevicesRename => api('accounts/devices/rename');
  Uri get accountsDevicesRevoke => api('accounts/devices/revoke');
  Uri get accountsDevicesLostDevice => api('accounts/devices/lost-device');
  Uri accountsDeviceSecurityHistory(String deviceId) => api(
    'accounts/devices/security-history',
    queryParameters: {'device_id': deviceId},
  );

  Uri get prekeysPublish => api('prekeys/publish');
  Uri prekeysBundle(String accountId) =>
      api('prekeys/bundle', queryParameters: {'account_id': accountId});

  Uri get contactsRequests => api('contacts/requests');
  Uri get contactsRequestsAccept => api('contacts/requests/accept');

  Uri get attachmentsUpload => api('attachments/upload');
  Uri attachmentUploadStatus(String attachmentId) =>
      api('attachments/upload/status/$attachmentId');
  Uri attachmentDownload(String fileId) => api('attachments/download/$fileId');
  Uri get attachmentsRegisterReference => api('attachments/register-reference');

  Uri get callsSignal => api('calls/signal');
  Uri get accountDelete => api('account/delete');
  Uri get privacyExport => api('privacy/export');
  Uri get backups => api('backups/');
  Uri get messagesDeviceEvents => api('messages/device-events');

  // --- Group calls, call links, scheduled calls ---
  //
  // Mounted at /api/v1/group-calls. Room creation posts to the collection
  // root, so `groupCallRooms` is the bare path rather than a trailing-slash
  // form: the shelf router has no redirect on that route, and a redirect on a
  // POST loses the body.

  Uri get groupCallRooms => api('group-calls');
  Uri groupCallRoom(String roomId) => api('group-calls/$roomId');
  Uri groupCallRoomJoin(String roomId) => api('group-calls/$roomId/join');
  Uri groupCallRoomLeave(String roomId) => api('group-calls/$roomId/leave');
  Uri groupCallRoomEnd(String roomId) => api('group-calls/$roomId/end');
  Uri groupCallRoomKick(String roomId) => api('group-calls/$roomId/kick');
  Uri groupCallRoomKey(String roomId) => api('group-calls/$roomId/key');
  Uri groupCallRoomScreenSharing(String roomId) =>
      api('group-calls/$roomId/screen-sharing');

  Uri get groupCallLinks => api('group-calls/links');
  Uri groupCallLink(String token) => api('group-calls/links/$token');

  Uri get groupCallScheduled => api('group-calls/scheduled');
  Uri groupCallScheduledRsvp(String id) =>
      api('group-calls/scheduled/$id/rsvp');
  Uri groupCallScheduledCall(String id) => api('group-calls/scheduled/$id');

  Uri api(String path, {Map<String, String>? queryParameters}) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final apiPath = normalizedPath.startsWith('api/v1/')
        ? normalizedPath
        : 'api/v1/$normalizedPath';
    return _origin.replace(
      path: _joinPath(_origin.path, apiPath),
      queryParameters: queryParameters,
    );
  }

  Uri resolveServerPath(String serverPath) {
    final normalized = serverPath.startsWith('/')
        ? serverPath.substring(1)
        : serverPath;
    return _origin.replace(path: _joinPath(_origin.path, normalized));
  }

  static Uri _normalizeOrigin(Uri uri) {
    final normalizedPath = uri.path.replaceFirst(RegExp(r'/api/v1/?$'), '');
    return uri.replace(path: normalizedPath, query: null, fragment: null);
  }

  static String _joinPath(String basePath, String childPath) {
    final base = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    final child = childPath.startsWith('/')
        ? childPath.substring(1)
        : childPath;
    if (base.isEmpty) return '/$child';
    return '$base/$child';
  }
}
