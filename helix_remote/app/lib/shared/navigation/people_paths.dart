/// The people routes, by path, so any feature can link to them without
/// importing the people feature (features never import each other). The routes
/// themselves are registered by `features/people/people_routes.dart`.
abstract final class PeoplePaths {
  /// The standalone people search (also what a `helix://contact` link opens).
  /// `?mode=calls` makes a tap start a call instead of opening a chat.
  static const home = '/home/people';
  static const search = '/home/people/search';

  static String searchFor({bool calls = false}) =>
      calls ? '$search?mode=calls' : search;

  /// The contact info screen of [accountId] (a bare uuid, or `uuid@domain`).
  static String person(String accountId) =>
      '$home/${Uri.encodeComponent(accountId)}';

  static String safetyNumber(String accountId) => '${person(accountId)}/safety';

  static String scan(String accountId) => '${person(accountId)}/scan';
}
