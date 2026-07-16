/// Canonical capability names used by clients, REST, realtime, storage, and UI
/// to gate wire/schema behavior.
class RemoteCapability {
  const RemoteCapability._();

  static const schemaVersion = 'helix.remote.schema.v1';
  static const realtimeEnvelopeV1 = 'helix.remote.realtime-envelope.v1';
  static const contentEnvelopeV1 = 'helix.remote.content-envelope.v1';
  static const contentTextV1 = 'helix.remote.content.text.v1';
  static const contentAttachmentV1 = 'helix.remote.content.attachment.v1';
  static const contentVoiceNoteV1 = 'helix.remote.content.voice-note.v1';
  static const contentInstantVideoV1 = 'helix.remote.content.instant-video.v1';
  static const contentMediaWithCaptionV1 =
      'helix.remote.content.media-with-caption.v1';
  static const contentMediaCollectionV1 =
      'helix.remote.content.media-collection.v1';
  static const richMediaPipelineV1 = 'helix.remote.rich-media-pipeline.v1';
  static const x3dhEnvelopeV1 = 'helix.remote.x3dh-envelope.v1';
  static const sessionEnvelopeV2 = 'helix.remote.session-envelope.v2';
  static const multiDeviceTrustV1 = 'helix.remote.multi-device-trust.v1';
  static const encryptedBackupRecoveryV2 =
      'helix.remote.encrypted-backup-recovery.v2';
  static const backupMediaObjectsV1 = 'helix.remote.backup-media-objects.v1';
  static const privacyControlsV1 = 'helix.remote.privacy-controls.v1';
  static const ephemeralContentV1 = 'helix.remote.ephemeral-content.v1';
  static const messagingProductivityV1 =
      'helix.remote.messaging-productivity.v1';
  static const localSearchIndexV1 = 'helix.remote.local-search-index.v1';
  static const contactLinksV1 = 'helix.remote.contact-links.v1';
  static const attachmentRecipientGrantsV1 =
      'helix.remote.attachment-recipient-grants.v1';
  static const localStorageSchemaV18 = 'helix.remote.local-storage-schema.v18';
  static const localStorageSchemaV19 = 'helix.remote.local-storage-schema.v19';
  static const backendSchemaV21 = 'helix.remote.backend-schema.v21';
  static const backendSchemaV22 = 'helix.remote.backend-schema.v22';
  static const groupsAdminV1 = 'helix.remote.groups-admin.v1';
  static const backendSchemaV23 = 'helix.remote.backend-schema.v23';
  static const callsReliabilityV1 = 'helix.remote.calls-reliability.v1';
  static const callPushWakeV1 = 'helix.remote.call-push-wake.v1';
  static const backendSchemaV24 = 'helix.remote.backend-schema.v24';
  static const localStorageSchemaV20 = 'helix.remote.local-storage-schema.v20';
  static const groupCallsV1 = 'helix.remote.group-calls.v1';
  static const callLinksV1 = 'helix.remote.call-links.v1';
  static const scheduledCallsV1 = 'helix.remote.scheduled-calls.v1';
  static const contentPollV1 = 'helix.remote.content.poll.v1';
  static const contentEventV1 = 'helix.remote.content.event.v1';
  static const contentLocationV1 = 'helix.remote.content.location.v1';
  static const collaborationContentV1 = 'helix.remote.collaboration-content.v1';
  static const localStorageSchemaV21 = 'helix.remote.local-storage-schema.v21';
  static const contentStickerV1 = 'helix.remote.content.sticker.v1';
  static const personalizationV1 = 'helix.remote.personalization.v1';
  static const localStorageSchemaV22 = 'helix.remote.local-storage-schema.v22';
  static const multiAccountRuntimeV1 = 'helix.remote.multi-account-runtime.v1';
  static const proxyDiagnosticsV1 = 'helix.remote.proxy-diagnostics.v1';
  static const platformExpansionV1 = 'helix.remote.platform-expansion.v1';
  static const localStorageSchemaV23 = 'helix.remote.local-storage-schema.v23';

  static const stable = <String>{
    schemaVersion,
    realtimeEnvelopeV1,
    contentEnvelopeV1,
    contentTextV1,
    contentAttachmentV1,
    contentVoiceNoteV1,
    contentInstantVideoV1,
    contentMediaWithCaptionV1,
    contentMediaCollectionV1,
    richMediaPipelineV1,
    x3dhEnvelopeV1,
    sessionEnvelopeV2,
    multiDeviceTrustV1,
    encryptedBackupRecoveryV2,
    backupMediaObjectsV1,
    privacyControlsV1,
    ephemeralContentV1,
    messagingProductivityV1,
    localSearchIndexV1,
    contactLinksV1,
    attachmentRecipientGrantsV1,
    localStorageSchemaV18,
    localStorageSchemaV19,
    backendSchemaV21,
    backendSchemaV22,
    groupsAdminV1,
    backendSchemaV23,
    callsReliabilityV1,
    callPushWakeV1,
    backendSchemaV24,
    localStorageSchemaV20,
    groupCallsV1,
    callLinksV1,
    scheduledCallsV1,
    contentPollV1,
    contentEventV1,
    contentLocationV1,
    collaborationContentV1,
    localStorageSchemaV21,
    contentStickerV1,
    personalizationV1,
    localStorageSchemaV22,
    multiAccountRuntimeV1,
    proxyDiagnosticsV1,
    platformExpansionV1,
    localStorageSchemaV23,
  };
}

class RemoteCapabilityRegistry {
  const RemoteCapabilityRegistry({required this.supported});

  factory RemoteCapabilityRegistry.current() {
    return const RemoteCapabilityRegistry(supported: RemoteCapability.stable);
  }

  final Set<String> supported;

  bool supports(String capability) => supported.contains(capability);

  Map<String, dynamic> toJson() => {
    'schema_version': 1,
    'capabilities': supported.toList()..sort(),
  };
}
