// Phase 5 composition tests.
// P5-007: LocalCompositionRoot smoke test.
// P5-008: Deterministic disposal.
// P5-019: Two roots share no mutable state.

import 'package:flutter_test/flutter_test.dart';

import 'package:helix_local_domain/core/product_descriptor.dart';
import 'package:helix/app/composition_root.dart';

void main() {
  group('LocalCompositionRoot', () {
    test(
      'P5-007: production() instantiates all required dependencies',
      () async {
        const descriptor = LocalProductDescriptor();
        final root = LocalCompositionRoot.production(descriptor);

        expect(root.conversationRepository, isNotNull);
        expect(root.connectionRequestRepository, isNotNull);
        expect(root.groupRepository, isNotNull);
        expect(root.transferRepository, isNotNull);
        expect(root.ephemeralMediaCache, isNotNull);
        expect(root.trustRepository, isNotNull);
        expect(root.sessionRepository, isNotNull);
        expect(root.foregroundServiceGateway, isNotNull);
        expect(root.notificationGateway, isNotNull);
        expect(root.diagnosticsGateway, isNotNull);
        expect(root.callEngine, isNotNull);
        expect(root.wipeScheduler, isNotNull);

        await root.dispose();
      },
    );

    test('P5-008: dispose() completes without error', () async {
      const descriptor = LocalProductDescriptor();
      final root = LocalCompositionRoot.production(descriptor);
      await expectLater(root.dispose(), completes);
    });

    test(
      'P5-019: two roots produce independent repository instances',
      () async {
        const descriptor = LocalProductDescriptor();
        final root1 = LocalCompositionRoot.production(descriptor);
        final root2 = LocalCompositionRoot.production(descriptor);

        expect(
          root1.conversationRepository,
          isNot(same(root2.conversationRepository)),
          reason: 'Each root must own independent in-memory storage',
        );
        expect(root1.groupRepository, isNot(same(root2.groupRepository)));
        expect(root1.wipeScheduler, isNot(same(root2.wipeScheduler)));

        await root1.dispose();
        await root2.dispose();
      },
    );
  });
}
