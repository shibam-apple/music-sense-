import 'package:audio_service/audio_service.dart';

import '../library/models.dart';
import 'playback_controller.dart';

/// Connects the player to Android's media session: the notification,
/// lock screen, headset buttons and Bluetooth controls.
class MusicSenseAudioHandler extends BaseAudioHandler with SeekHandler {
  MusicSenseAudioHandler(this._player) {
    _player.addListener(_publish);
    _publish();
  }

  final PlaybackController _player;
  String? _lastKey;

  void _publish() {
    final track = _player.track;
    if (track != null && track.key != _lastKey) {
      _lastKey = track.key;
      mediaItem.add(
        MediaItem(
          id: track.key,
          title: track.title,
          artist: track.artist,
          album: track.album,
          duration: track.duration == Duration.zero ? null : track.duration,
          artUri: switch (track.artwork) {
            NetworkArtwork(:final url) => Uri.parse(url),
            LocalArtwork(:final mediaId) => Uri.parse(
              'content://media/external/audio/media/$mediaId/albumart',
            ),
            PaintedArtwork() => null,
          },
        ),
      );
    }
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          _player.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: track == null
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        playing: _player.playing,
        updatePosition: _player.position,
      ),
    );
  }

  @override
  Future<void> play() async => _player.play();
  @override
  Future<void> pause() async => _player.pause();
  @override
  Future<void> skipToNext() async => _player.next();
  @override
  Future<void> skipToPrevious() async => _player.previous();

  @override
  Future<void> seek(Duration position) async {
    final total = _player.duration.inMilliseconds;
    if (total > 0) _player.seek(position.inMilliseconds / total);
  }
}
