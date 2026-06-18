import 'package:helix_domain/application/contracts/repositories.dart';
import 'package:helix_domain/domain/models.dart';

class InMemoryTransferRepository implements TransferRepository {
  final Map<String, FileTransferSession> _transfers = {};

  @override
  List<FileTransferSession> listTransfers() {
    return List.unmodifiable(_transfers.values);
  }

  @override
  FileTransferSession? loadTransfer(String fileId) {
    return _transfers[fileId];
  }

  @override
  Future<void> saveTransfer(FileTransferSession transfer) async {
    _transfers[transfer.fileId] = transfer;
  }

  @override
  Future<void> removeTransfer(String fileId) async {
    _transfers.remove(fileId);
  }
}
