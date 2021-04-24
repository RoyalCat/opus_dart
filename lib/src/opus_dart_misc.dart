import 'package:ffi/ffi.dart';

import 'bindings/libopus.dart';

/// Max bitstream size of a single opus packet.
///
/// See [here](https://stackoverflow.com/questions/55698317/what-value-to-use-for-libopus-encoder-max-data-bytes-field)
/// for an explanation how this was calculated.
const int maxDataBytes = 3 * 1275;

/// Calculates, how much sampels a single opus package at [sampleRate] with [channels] may contain.
///
/// A single package may contain up 120ms of audio. This value is reached by combining up to 3 frames of 40ms audio.
int maxSamplesPerPacket(int sampleRate, int channels) => ((sampleRate * channels * 120) / 1000)
    .ceil(); //Some sample rates may not be dividable by 1000, so use ceiling instead of integer division.

/// Returns the version of the native libopus library.
String getOpusVersion() => libopus.opus_get_version_string().cast<Utf8>().toDartString();

/// Thrown when a native exception occurs.
class OpusException implements Exception {
  final int errorCode;
  const OpusException(this.errorCode);
  @override
  String toString() {
    final error = libopus.opus_strerror(errorCode).cast<Utf8>().toDartString();
    return 'OpusException $errorCode: $error';
  }
}

/// Thrown when attempting to call an method on an already destroyed encoder or decoder.
class OpusDestroyedError extends StateError {
  OpusDestroyedError.encoder()
      : super('OpusDestroyedException: This OpusEncoder was already destroyed!');
  OpusDestroyedError.decoder()
      : super('OpusDestroyedException: This OpusDecoder was already destroyed!');
}
