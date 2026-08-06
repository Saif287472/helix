part of '../message_tile.dart';

class _CallEventData {
  const _CallEventData({
    required this.title,
    required this.subtitle,
    required this.video,
    required this.missed,
  });

  final String title;
  final String subtitle;
  final bool video;
  final bool missed;

  static _CallEventData? tryParse(String text) {
    final normalized = text.trim();
    final lower = normalized.toLowerCase();
    if (!lower.contains('call')) return null;
    final video = lower.contains('video');
    final missed = lower.contains('missed');
    final title = missed
        ? 'Missed ${video ? 'video' : 'voice'} call'
        : '${video ? 'Video' : 'Voice'} call';
    var subtitle = missed ? 'Tap to call back' : 'No answer';
    for (final line in normalized.split('\n')) {
      final trimmed = line.trim();
      final l = trimmed.toLowerCase();
      if (RegExp(r'\b(min|sec|hour|hr)\b').hasMatch(l) ||
          l.contains('no answer')) {
        subtitle = trimmed;
        break;
      }
    }
    return _CallEventData(
      title: title,
      subtitle: subtitle,
      video: video,
      missed: missed,
    );
  }
}

class _MediaMetadata extends StatelessWidget {
  const _MediaMetadata({required this.media});

  final RemoteMediaContent media;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Chip(
          visualDensity: VisualDensity.compact,
          avatar: Icon(_iconFor(media.kind), size: 16),
          label: Text(media.kind.replaceAll('_', ' ')),
        ),
        if (media.durationMs != null)
          Text(_duration(media.durationMs!), style: theme.textTheme.labelSmall),
        if (media.waveform.isNotEmpty)
          SizedBox(
            width: 96,
            height: 20,
            child: CustomPaint(painter: _WaveformPainter(media.waveform)),
          ),
      ],
    );
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case RemoteMediaContent.voiceNoteKind:
        return Icons.mic;
      case RemoteMediaContent.instantVideoKind:
        return Icons.videocam;
      case RemoteMediaContent.imageKind:
      case RemoteMediaContent.cameraCaptureKind:
      case RemoteMediaContent.livePhotoKind:
        return Icons.image;
      case RemoteMediaContent.videoKind:
        return Icons.movie;
      case RemoteMediaContent.scannerDocumentKind:
      case RemoteMediaContent.documentKind:
        return Icons.description;
      default:
        return Icons.perm_media;
    }
  }

  String _duration(int ms) {
    final totalSeconds = (ms / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter(this.samples);

  final List<int> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF25D366)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final step = size.width / samples.length;
    for (var i = 0; i < samples.length; i++) {
      final normalized = samples[i].clamp(0, 100) / 100;
      final height = (size.height * normalized).clamp(3.0, size.height);
      final x = i * step + step / 2;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.samples != samples;
}

// ---------------------------------------------------------------------------

class _MessageStatusIcon extends StatelessWidget {
  const _MessageStatusIcon({required this.status, required this.readColor});

  final String status;
  final Color readColor;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _resolve(status);
    return Tooltip(
      message: label,
      child: Icon(icon, size: 14, color: color, semanticLabel: label),
    );
  }

  (IconData, Color, String) _resolve(String status) {
    switch (status) {
      case 'PENDING':
        return (Icons.schedule, Colors.grey, 'Queued');
      case 'SENT':
        return (Icons.done, Colors.grey, 'Sent');
      case 'DELIVERED':
        return (Icons.done_all, Colors.grey, 'Delivered');
      case 'READ':
        return (Icons.done_all, readColor, 'Read');
      case 'RETRYING':
        return (Icons.autorenew, Colors.orange, 'Retrying');
      case 'FAILED':
        return (Icons.error_outline, Colors.red, 'Failed to send');
      case 'SECURE_SESSION_UNAVAILABLE':
        return (Icons.lock_open, Colors.red, 'Secure session unavailable');
      case 'EDITED':
        return (Icons.edit, Colors.grey, 'Edited');
      case 'DELETED':
        return (Icons.delete_outline, Colors.grey, 'Deleted');
      case 'TOMBSTONED':
        return (Icons.delete_forever, Colors.grey, 'Deleted for everyone');
      case 'OFFLINE':
        return (Icons.cloud_off, Colors.grey, 'Offline');
      case 'KEY_CHANGED':
        return (Icons.warning_amber, Colors.orange, 'Safety key changed');
      case 'REVOKED_DEVICE':
        return (Icons.no_accounts, Colors.red, 'Device revoked');
      default:
        return (Icons.help_outline, Colors.grey, status);
    }
  }
}
