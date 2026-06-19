class RemoteAttachmentSafety {
  static const String malwareWarningMessage =
      "Warning: Because this file is end-to-end encrypted, the server cannot scan its contents for malware or viruses. Only open files from contacts you trust.";

  /// Verifies if a given safety warning matches the required E2EE warning.
  static bool verifyWarningMessage(String message) {
    return message == malwareWarningMessage;
  }
}
