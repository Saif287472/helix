/// Per-device encrypted key slots for multi-device attachment key delivery.
/// Each entry maps a device_id to the attachment key encrypted for that device.
class AttachmentKeyPackage {
  const AttachmentKeyPackage({
    required this.attachmentId,
    required this.deviceKeys,
  });

  final String attachmentId;
  final Map<String, String> deviceKeys;

  Map<String, dynamic> toJson() => {
    'attachment_id': attachmentId,
    'device_keys': deviceKeys,
  };

  factory AttachmentKeyPackage.fromJson(Map<String, dynamic> json) {
    return AttachmentKeyPackage(
      attachmentId: json['attachment_id'] as String,
      deviceKeys: Map<String, String>.from(json['device_keys'] as Map),
    );
  }
}

class RemoteAttachmentManifest {
  const RemoteAttachmentManifest({
    required this.fileId,
    required this.fileSize,
    required this.fileHash,
    required this.mimeType,
    this.thumbnailFileId,
    this.thumbnailFileSize,
    this.thumbnailFileHash,
  });

  final String fileId;
  final int fileSize;
  final String fileHash;
  final String mimeType;
  final String? thumbnailFileId;
  final int? thumbnailFileSize;
  final String? thumbnailFileHash;

  Map<String, dynamic> toJson() => {
    'file_id': fileId,
    'file_size': fileSize,
    'file_hash': fileHash,
    'mime_type': mimeType,
    if (thumbnailFileId != null) 'thumbnail_file_id': thumbnailFileId,
    if (thumbnailFileSize != null) 'thumbnail_file_size': thumbnailFileSize,
    if (thumbnailFileHash != null) 'thumbnail_file_hash': thumbnailFileHash,
  };

  factory RemoteAttachmentManifest.fromJson(Map<String, dynamic> json) {
    return RemoteAttachmentManifest(
      fileId: json['file_id'] as String,
      fileSize: json['file_size'] as int,
      fileHash: json['file_hash'] as String,
      mimeType: json['mime_type'] as String,
      thumbnailFileId: json['thumbnail_file_id'] as String?,
      thumbnailFileSize: json['thumbnail_file_size'] as int?,
      thumbnailFileHash: json['thumbnail_file_hash'] as String?,
    );
  }
}
