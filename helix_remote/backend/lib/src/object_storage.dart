import 'dart:io';

abstract interface class ObjectStorageAdapter {
  Future<void> putObject(String objectId, List<int> ciphertext);
  Future<List<int>> getObject(String objectId);
  Future<void> deleteObject(String objectId);
  Future<bool> exists(String objectId);
}

final class LocalFileSystemObjectStorage implements ObjectStorageAdapter {
  LocalFileSystemObjectStorage(this.root);

  final Directory root;

  File _fileFor(String objectId) {
    if (objectId.contains('/') ||
        objectId.contains(r'\') ||
        objectId.contains('..')) {
      throw ArgumentError.value(objectId, 'objectId', 'Invalid object id');
    }
    return File('${root.path}${Platform.pathSeparator}$objectId.blob');
  }

  @override
  Future<void> putObject(String objectId, List<int> ciphertext) async {
    await root.create(recursive: true);
    await _fileFor(objectId).writeAsBytes(ciphertext, flush: true);
  }

  @override
  Future<List<int>> getObject(String objectId) =>
      _fileFor(objectId).readAsBytes();

  @override
  Future<void> deleteObject(String objectId) async {
    final file = _fileFor(objectId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> exists(String objectId) => _fileFor(objectId).exists();
}
