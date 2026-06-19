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
