import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'bindings/libopus.dart';
import 'bindings/opus_bindings.dart' as opus_bindings;
import 'opus_dart_misc.dart';

/// Bundles utility functions to examin opus packets.
///
/// All methods copy the input data into native memory.
abstract class OpusPacketUtils {
  /// Returns the amount of samples in a [packet] given a [sampleRate].
  static int getSampleCount({required Uint8List packet, required int sampleRate}) {
    final data = malloc.allocate<Uint8>(sizeOf<Uint8>() * packet.length);
    data.asTypedList(packet.length).setAll(0, packet);
    try {
      final sampleCount = libopus.opus_packet_get_nb_samples(data, packet.length, sampleRate);
      if (sampleCount >= opus_bindings.OPUS_OK) {
        return sampleCount;
      } else {
        throw OpusException(sampleCount);
      }
    } finally {
      malloc.free(data);
    }
  }

  /// Returns the amount of frames in a [packet].
  static int getFrameCount({required Uint8List packet}) {
    final data = malloc.allocate<Uint8>(sizeOf<Uint8>() * packet.length);
    data.asTypedList(packet.length).setAll(0, packet);
    try {
      final frameCount = libopus.opus_packet_get_nb_frames(data, packet.length);
      if (frameCount >= opus_bindings.OPUS_OK) {
        return frameCount;
      } else {
        throw OpusException(frameCount);
      }
    } finally {
      malloc.free(data);
    }
  }

  /// Returns the amount of samples per frame in a [packet] given a [sampleRate].
  static int getSamplesPerFrame({required Uint8List packet, required int sampleRate}) {
    final data = malloc.allocate<Uint8>(sizeOf<Uint8>() * packet.length);
    data.asTypedList(packet.length).setAll(0, packet);
    try {
      final samplesPerFrame = libopus.opus_packet_get_samples_per_frame(data, sampleRate);
      if (samplesPerFrame >= opus_bindings.OPUS_OK) {
        return samplesPerFrame;
      } else {
        throw OpusException(samplesPerFrame);
      }
    } finally {
      malloc.free(data);
    }
  }

  /// Returns the channel count from a [packet]
  static int getChannelCount({required Uint8List packet}) {
    final data = malloc.allocate<Uint8>(sizeOf<Uint8>() * packet.length);
    data.asTypedList(packet.length).setAll(0, packet);
    try {
      final channelCount = libopus.opus_packet_get_nb_channels(data);
      if (channelCount >= opus_bindings.OPUS_OK) {
        return channelCount;
      } else {
        throw OpusException(channelCount);
      }
    } finally {
      malloc.free(data);
    }
  }

  /// Returns the bandwidth from a [packet]
  static int getBandwidth({required Uint8List packet}) {
    final data = malloc.allocate<Uint8>(sizeOf<Uint8>() * packet.length);
    data.asTypedList(packet.length).setAll(0, packet);
    try {
      final bandwidth = libopus.opus_packet_get_bandwidth(data);
      if (bandwidth >= opus_bindings.OPUS_OK) {
        return bandwidth;
      } else {
        throw OpusException(bandwidth);
      }
    } finally {
      malloc.free(data);
    }
  }
}
