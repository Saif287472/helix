import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/account_runtime_registry.dart';

RemoteAccountRuntimeDescriptor _account(
  String accountId, {
  bool active = false,
  int lastUsedAtMs = 0,
}) {
  return RemoteAccountRuntimeDescriptor(
    accountId: accountId,
    displayName: accountId,
    databasePath: 'data/$accountId/remote.db',
    secureStorageNamespace: 'helix.remote.$accountId',
    attachmentCachePath: 'cache/$accountId/attachments',
    notificationChannelId: 'remote.account.$accountId',
    serverBaseUrl: 'https://$accountId.example',
    active: active,
    lastUsedAtMs: lastUsedAtMs,
  );
}

void main() {
  group('RemoteAccountRuntimeRegistry', () {
    test('switches active accounts with isolated runtime namespaces', () {
      final registry = RemoteAccountRuntimeRegistry(
        platform: RemotePlatformCapabilities.forKind(
          RemotePlatformKind.windows,
        ),
      );

      registry
        ..addAccount(_account('alice', active: true, lastUsedAtMs: 1000))
        ..addAccount(_account('work', lastUsedAtMs: 900));

      final work = registry.switchAccount('work', nowMs: 1200);
      final context = registry.accountBoundContext('composer');

      expect(work.accountId, equals('work'));
      expect(context['account_id'], equals('work'));
      expect(context['token_key_prefix'], contains('work'));
      expect(context['key_material_prefix'], contains('work'));
      expect(context['sync_task_namespace'], equals('remote.sync.work'));
      expect(context['call_task_namespace'], equals('remote.calls.work'));
      expect(context['share_target_namespace'], equals('remote.share.work'));
      expect(
        context['clipboard_namespace'],
        isNot(equals('remote.clipboard.alice')),
      );
      expect(
        registry.accounts
            .singleWhere((account) => account.accountId == 'alice')
            .active,
        isFalse,
      );
      expect(registry.featureAvailable('deep_links'), isTrue);
      expect(
        registry.featureAvailable('default_messaging_integration'),
        isFalse,
      );
    });

    test('rejects shared database, key, cache, or notification scopes', () {
      final registry = RemoteAccountRuntimeRegistry()
        ..addAccount(_account('alice', active: true));

      expect(
        () => registry.addAccount(
          RemoteAccountRuntimeDescriptor(
            accountId: 'work',
            displayName: 'work',
            databasePath: 'data/alice/remote.db',
            secureStorageNamespace: 'helix.remote.work',
            attachmentCachePath: 'cache/work/attachments',
            notificationChannelId: 'remote.account.work',
            serverBaseUrl: 'https://work.example',
          ),
        ),
        throwsA(isA<RemoteRuntimeException>()),
      );
      expect(
        () => registry.addAccount(
          RemoteAccountRuntimeDescriptor(
            accountId: 'personal',
            displayName: 'personal',
            databasePath: 'data/personal/remote.db',
            secureStorageNamespace: 'helix.remote.alice',
            attachmentCachePath: 'cache/personal/attachments',
            notificationChannelId: 'remote.account.personal',
            serverBaseUrl: 'https://personal.example',
          ),
        ),
        throwsA(isA<RemoteRuntimeException>()),
      );
    });

    test(
      'proxy diagnostics redact credentials and keep TURN media separate',
      () {
        final registry = RemoteAccountRuntimeRegistry()
          ..addAccount(_account('alice', active: true));

        registry.setProxy(
          'alice',
          const RemoteProxySettings(
            mode: RemoteProxyMode.http,
            host: 'proxy.example',
            port: 8443,
            username: 'alice-proxy',
            passwordRef: 'secure://proxy/alice',
          ),
        );

        final diagnostics = registry.redactedConnectivityDiagnostics('alice');
        final proxy = diagnostics['proxy'] as Map<String, dynamic>;

        expect(proxy['username_present'], isTrue);
        expect(proxy['password_ref_present'], isTrue);
        expect(proxy.containsKey('passwordRef'), isFalse);
        expect(proxy['rest'], equals('proxied'));
        expect(proxy['websocket'], equals('proxied'));
        expect(proxy['attachment_transfer'], equals('proxied'));
        expect(proxy['call_signaling'], equals('proxied'));
        expect(proxy['turn_media'], equals('separate'));
        expect(
          () => registry.setProxy(
            'alice',
            const RemoteProxySettings(
              mode: RemoteProxyMode.http,
              host: 'proxy.example',
              port: 8443,
              allowInvalidCertificates: true,
            ),
          ),
          throwsA(isA<RemoteRuntimeException>()),
        );
      },
    );

    test(
      'platform flags expose desktop/tablet and hide deferred platforms',
      () {
        final registry = RemoteAccountRuntimeRegistry(
          platform: RemotePlatformCapabilities.forKind(
            RemotePlatformKind.tablet,
          ),
        )..addAccount(_account('alice', active: true));

        expect(registry.featureAvailable('two_pane_chat'), isTrue);
        expect(registry.featureAvailable('drag_drop'), isTrue);
        expect(registry.featureAvailable('tray'), isFalse);

        registry.updatePlatform(
          RemotePlatformCapabilities.forKind(RemotePlatformKind.watch),
        );

        expect(registry.featureAvailable('notifications'), isFalse);
        expect(registry.featureAvailable('smartwatch_client'), isFalse);
        expect(
          registry.redactedConnectivityDiagnostics('alice')['platform'],
          containsPair('constrained_os', true),
        );
      },
    );

    test('cleanup evicts only oldest inactive accounts', () {
      final registry = RemoteAccountRuntimeRegistry()
        ..addAccount(_account('active', active: true, lastUsedAtMs: 3000))
        ..addAccount(_account('old_a', lastUsedAtMs: 100))
        ..addAccount(_account('old_b', lastUsedAtMs: 200))
        ..addAccount(_account('recent', lastUsedAtMs: 2500));

      final removed = registry.cleanupInactive(
        olderThanMs: 1000,
        maxInactiveAccounts: 1,
      );

      expect(removed.map((account) => account.accountId), ['old_a']);
      expect(
        registry.accounts.where((account) => account.accountId == 'old_a'),
        isEmpty,
      );
      expect(registry.activeAccount!.accountId, equals('active'));
    });
  });
}
