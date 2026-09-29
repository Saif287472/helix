import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/app_lock.dart';

void main() {
  var enabled = true;
  var relock = 0;
  var inCall = false;

  setUp(() {
    enabled = true;
    relock = 0;
    inCall = false;
    AppLock.attach(
      read: () => (enabled: enabled, relockAfterSeconds: relock),
      callActive: () => inCall,
    );
  });

  tearDown(AppLock.detach);

  test('locks on open when enabled, not when disabled', () {
    AppLock.lockIfEnabled();
    expect(AppLock.locked.value, isTrue);

    AppLock.locked.value = false;
    enabled = false;
    AppLock.lockIfEnabled();
    expect(AppLock.locked.value, isFalse);
  });

  test('never locks during a call', () {
    inCall = true;
    AppLock.lockIfEnabled();
    expect(AppLock.locked.value, isFalse);
  });

  test('relocks after the chosen time in the background', () {
    relock = 0;
    AppLock.onBackgrounded();
    AppLock.onResumed();
    expect(AppLock.locked.value, isTrue);
  });

  test('a short trip away within the relock window stays unlocked', () {
    relock = 900;
    AppLock.onBackgrounded();
    AppLock.onResumed();
    expect(AppLock.locked.value, isFalse);
  });

  test('the unlock prompt pausing the app does not relock it', () async {
    relock = 0;
    AppLock.locked.value = true;
    AppLock.authenticator = (_) async {
      // What Android does while the system prompt is up.
      AppLock.onBackgrounded();
      AppLock.onResumed();
      return true;
    };
    expect(await AppLock.unlock('test'), isTrue);
    expect(AppLock.locked.value, isFalse);
  });

  test('signing out detaches and unlocks', () {
    AppLock.lockIfEnabled();
    AppLock.detach();
    expect(AppLock.locked.value, isFalse);
    expect(AppLock.enabled, isFalse);
  });
}
