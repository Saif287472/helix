part of '../bodies.dart';

/// The bodies that move history between one account's own devices
/// (CONTENT_V2.md §4, F2).

/// Where a device-to-device history transfer stands (CONTENT_V2.md §4).
enum DeviceTransferState implements WireEnum {
  /// The sender offers a history; [DeviceTransferOfferBody.relayMedia] says
  /// where to fetch it.
  offer('offer'),

  /// A receiver finished importing it.
  done('done'),

  /// A receiver does not want it.
  declined('declined'),

  /// The sender withdrew the offer; receivers drop what they fetched.
  cancelled('cancelled'),

  /// A step a newer device wrote that this client does not know. Ignored,
  /// never read as [cancelled]; there is no wire value for it, so it encodes
  /// as absent rather than as an offer or a withdrawal.
  unknown('unknown');

  const DeviceTransferState(this.wire);

  @override
  final String wire;
}

/// Own devices only: history moving from one device to another (F2).
///
/// An `offer` carries a pointer to a small encrypted manifest in the media
/// relay; the manifest lists the encrypted segments of the history. The other
/// states answer or withdraw an offer and carry no pointer. `state` and
/// `devices` are additive to CONTENT_V2.md §4: `devices` names the devices the
/// offer is for (absent: every other device of the account), and a client that
/// predates `state` reads any message as an offer, finds no pointer and
/// ignores it.
final class DeviceTransferOfferBody extends ContentBody {
  const DeviceTransferOfferBody({
    required this.transferId,
    this.relayMedia,
    this.state = DeviceTransferState.offer,
    this.devices,
  });

  static const typeName = 'device_transfer_offer';

  final String transferId;
  final MediaPointer? relayMedia;
  final DeviceTransferState state;

  /// The devices an offer is for; null means all of the account's others.
  final List<String>? devices;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => compact({
    'transfer_id': transferId,
    'relay_media': relayMedia?.toJson(),
    'state': switch (state) {
      DeviceTransferState.offer || DeviceTransferState.unknown => null,
      _ => state.wire,
    },
    'devices': devices,
  });

  factory DeviceTransferOfferBody.fromJson(JsonReader json) =>
      DeviceTransferOfferBody(
        transferId: json.id('transfer_id'),
        relayMedia: json.has('relay_media')
            ? MediaPointer.fromJson(json.object('relay_media'))
            : null,
        state:
            json.optEnum(
              'state',
              DeviceTransferState.values,
              orElse: DeviceTransferState.unknown,
            ) ??
            DeviceTransferState.offer,
        devices: json.has('devices')
            ? json.ids('devices', maxItems: ContentLimits.maxDevices)
            : null,
      );
}
