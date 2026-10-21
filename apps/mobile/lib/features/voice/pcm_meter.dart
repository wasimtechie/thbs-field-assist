import 'dart:math' as math;
import 'dart:typed_data';

/// Measures actual 20 ms PCM frames, rather than a platform peak-hold meter.
/// Handles arbitrary stream chunks, including a split 16-bit sample.
class PcmLevelMeter {
  PcmLevelMeter(this.onLevel);
  final void Function(double) onLevel;
  int? _lowByte;
  int _samples = 0;
  double _power = 0;

  void add(Uint8List bytes) {
    for (final byte in bytes) {
      if (_lowByte == null) {
        _lowByte = byte;
        continue;
      }
      var sample = _lowByte! | (byte << 8);
      _lowByte = null;
      if (sample >= 32768) sample -= 65536;
      final normalized = sample / 32768;
      _power += normalized * normalized;
      if (++_samples == 320) {
        final rms = math.sqrt(_power / _samples);
        _power = 0;
        _samples = 0;
        onLevel(rms);
      }
    }
  }
}
