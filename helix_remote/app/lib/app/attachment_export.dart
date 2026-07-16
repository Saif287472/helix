class RemoteAttachmentExport {
  static const String exportWarningMessage =
      'Warning: Saving this file outside Helix will remove it from '
      'end-to-end encryption protection. The decrypted file will be '
      'accessible to other apps and the operating system.';

  static bool verifyExportWarning(String message) {
    return message == exportWarningMessage;
  }
}
