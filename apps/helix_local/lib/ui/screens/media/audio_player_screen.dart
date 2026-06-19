import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class AudioPlayerScreen extends StatefulWidget {
  const AudioPlayerScreen.fromFile({
    super.key,
    required this.filePath,
    required this.title,
  }) : bytes = null;

  const AudioPlayerScreen.fromBytes({
    super.key,
    required this.bytes,
    required this.title,
  }) : filePath = null;

  final String? filePath;
  final Uint8List? bytes;
  final String title;

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  File? _tempFile;
  bool _ready = false;
  bool _disposed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _player.onPositionChanged.listen((d) {
      if (mounted) setState(() => _position = d);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _init();
  }

  Future<void> _init() async {
    File? created;
    try {
      String path;
      if (widget.bytes != null) {
        final tmp = await getTemporaryDirectory();
        created = File(p.join(tmp.path, 'wa_${const Uuid().v4()}.tmp'));
        await created.writeAsBytes(widget.bytes!);
        if (_disposed) return;
        _tempFile = created;
        path = created.path;
      } else {
        path = widget.filePath!;
      }
      if (_disposed) return;
      await _player.setSource(DeviceFileSource(path));
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (_disposed) {
        created?.delete().ignore();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _player.dispose();
    _tempFile?.delete().ignore();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final playing = _state == PlayerState.playing;
    final total = _duration.inMilliseconds;
    final progress = total > 0 ? _position.inMilliseconds / total : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.audiotrack,
                size: 96,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 32),
              Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: _ready && total > 0
                    ? (v) => _player.seek(
                        Duration(milliseconds: (v * total).round()),
                      )
                    : null,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _fmt(_position),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    _fmt(_duration),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(
                  'Failed to load audio: $_error',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (!_ready)
                const CircularProgressIndicator()
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 48,
                      icon: const Icon(Icons.replay_10),
                      onPressed: () => _player.seek(
                        Duration(
                          milliseconds: (_position.inMilliseconds - 10000)
                              .clamp(0, total),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      iconSize: 64,
                      icon: Icon(
                        playing ? Icons.pause_circle : Icons.play_circle,
                      ),
                      onPressed: () =>
                          playing ? _player.pause() : _player.resume(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      iconSize: 48,
                      icon: const Icon(Icons.forward_10),
                      onPressed: () => _player.seek(
                        Duration(
                          milliseconds: (_position.inMilliseconds + 10000)
                              .clamp(0, total),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
