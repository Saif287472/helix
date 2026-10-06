import 'package:helix_remote_api/v2.dart'
    show ApiException, HelixApiException, NetworkException;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;

/// Why a people operation failed, in terms a screen can phrase. The exception
/// itself never reaches a screen (it may name an account or a number).
enum PeopleFailure {
  /// The daily lookup budget (5,000 numbers a day) or a rate limit is used up.
  rateLimited,

  /// No connection to the server.
  offline,

  /// Anything else; "try again" is all there is to say.
  other;

  static PeopleFailure of(Object error) => switch (error) {
    ApiException(code: ErrorCode.rateLimited) => PeopleFailure.rateLimited,
    NetworkException() => PeopleFailure.offline,
    HelixApiException() => PeopleFailure.other,
    _ => PeopleFailure.other,
  };
}
