import 'package:test/test.dart';
import 'package:helix_local_domain/core/product_descriptor.dart';

void main() {
  group('ProductDescriptor', () {
    const local = LocalProductDescriptor();
    const remote = RemoteProductDescriptor();

    test('all configurations are distinct between Local and Remote', () {
      expect(local.productId, isNot(equals(remote.productId)));
      expect(local.displayName, isNot(equals(remote.displayName)));
      expect(local.packageId, isNot(equals(remote.packageId)));
      expect(local.appDataFolder, isNot(equals(remote.appDataFolder)));
      expect(local.databaseFilename, isNot(equals(remote.databaseFilename)));
      expect(local.secureStoragePrefix, isNot(equals(remote.secureStoragePrefix)));
      expect(local.notificationNamespace, isNot(equals(remote.notificationNamespace)));
      expect(local.urlScheme, isNot(equals(remote.urlScheme)));
      expect(local.methodChannelNamespace, isNot(equals(remote.methodChannelNamespace)));
      expect(local.logNamespace, isNot(equals(remote.logNamespace)));
      expect(local.exportPrefix, isNot(equals(remote.exportPrefix)));
      expect(local.protocolLabel, isNot(equals(remote.protocolLabel)));
      expect(local.windowsNotificationGuid, isNot(equals(remote.windowsNotificationGuid)));
    });
  });
}
