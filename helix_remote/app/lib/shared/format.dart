// The formatters presentation may use. A widget never formats a time or a size
// itself, but a few pages draw ones their notifier already finished; the one
// implementation lives in `core/format/labels.dart` and is re-exported here
// because presentation may import `shared/`, not `core/`.
export 'package:helix_remote/core/format/labels.dart'
    show formatAgo, formatBytes, formatFileSize;
