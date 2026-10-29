import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the account's plan says about how long the server keeps the files it
/// sends. Null until the plan has been read (the You page reads it), and when
/// it cannot be: Storage then says nothing rather than guess. The plan feature
/// sets it; Settings only reads it, so core stays free of the features.
final serverRetentionProvider =
    NotifierProvider<ServerRetention, ServerRetentionTerms?>(
      ServerRetention.new,
    );

class ServerRetention extends Notifier<ServerRetentionTerms?> {
  @override
  ServerRetentionTerms? build() => null;

  void set(ServerRetentionTerms? terms) => state = terms;
}

/// [days] is what this account has now. [premiumDays] is set only while plans
/// are on and this account is not on Premium, which keeps files longer.
final class ServerRetentionTerms {
  const ServerRetentionTerms({required this.days, this.premiumDays});

  final int days;
  final int? premiumDays;

  /// "Files you send stay on the server for 30 days ..." in plain words.
  String get note {
    final upsell = premiumDays == null
        ? ''
        : ' Orbit Premium keeps them $premiumDays days.';
    return 'Files you send stay on the server for $days days so the people '
        'you sent them to can download them. After that they are removed from '
        'the server; your copy on this phone stays.$upsell';
  }
}
