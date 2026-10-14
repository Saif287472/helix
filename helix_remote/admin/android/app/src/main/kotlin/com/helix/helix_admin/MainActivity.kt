package com.helix.helix_admin

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity rather than FlutterActivity: local_auth's system
// unlock prompt (the console's App lock) is a fragment and refuses to run in
// anything but a FragmentActivity (NOT_FRAGMENT_ACTIVITY), which locked the
// operator out of a console with App lock on (review B-01).
class MainActivity : FlutterFragmentActivity()
