import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings/libopus.dart';
import 'bindings/opus_bindings.dart' as opus_bindings;
import 'opus_dart_misc.dart';

int _packetDuration(int samples, int channels, int sampleRate) =>
    ((samples * 1000) ~/ channels) ~/ sampleRate;

/// Soft clips the [input] to a range from -1 to 1 and returns
/// the result.
///
/// If the samples are already in this range, nothing happens
/// to the samples.
///
/// [input] is copied into native memory.
/// If you are using a [BufferedOpusDecoder], take a look at it's [pcmSoftClipOutputBuffer]
/// method instead, since it avoids unnecessary memory copying.
Float32List pcmSoftClip({required Float32List input, required int channels}) {
  final nativePcm = malloc.allocate<Float>(sizeOf<Float>() * input.length);
  nativePcm.asTypedList(input.length).setAll(0, input);
  final nativeBuffer = malloc.allocate<Float>(sizeOf<Float>() * channels);
  try {
    libopus.opus_pcm_soft_clip(nativePcm, input.length ~/ channels, channels, nativeBuffer);
    return Float32List.fromList(nativePcm.asTypedList(input.length));
  } finally {
    malloc..free(nativePcm)..free(nativeBuffer);
  }
}

/// An easy to use implementation of [OpusDecoder].
/// Don't forget to call [destroy] once you are done with it.
///
/// All method calls in this calls allocate their own memory everytime they are called.
/// See the [BufferedOpusDecoder] for an implementation with less allocation calls.
class SimpleOpusDecoder {
  final int sampleRate;
  final int channels;

  int? _lastPacketDurationMs;

  final Pointer<Float> _softClipBuffer;

  final int _maxSamplesPerPacket;
  final Pointer<opus_bindings.OpusDecoder> _opusDecoder;
  bool _destroyed;

  bool get destroyed => _destroyed;
  int? get lastPacketDurationMs => _lastPacketDurationMs;

  SimpleOpusDecoder._(this._opusDecoder, this.sampleRate, this.channels, this._softClipBuffer)
      : _destroyed = false,
        _maxSamplesPerPacket = maxSamplesPerPacket(sampleRate, channels);

  /// Creates an new [SimpleOpusDecoder] based on the [sampleRate] and [channels].
  /// See the matching fields for more information about these parameters.
  factory SimpleOpusDecoder({required int sampleRate, required int channels}) {
    final error = malloc.allocate<Int32>(sizeOf<Int32>() * 1);
    final softClipBuffer = malloc.allocate<Float>(sizeOf<Float>() * channels);
    final decoder = libopus.opus_decoder_create(sampleRate, channels, error);
    try {
      if (error.value == opus_bindings.OPUS_OK) {
        return SimpleOpusDecoder._(decoder, sampleRate, channels, softClipBuffer);
      } else {
        malloc.free(softClipBuffer);
        throw OpusException(error.value);
      }
    } finally {
      malloc.free(error);
    }
  }

  /// Decodes an opus packet to s16le samples, represented as [Int16List].
  /// Use `null` as [input] to indicate packet loss.
  ///
  /// On packet loss, the [loss] parameter needs to be exactly the duration
  /// of audio that is missing in milliseconds, otherwise the decoder will
  /// not be in the optimal state to decode the next incoming packet.
  /// If you don't know the duration, leave it `null` and [lastPacketDurationMs]
  /// will be used as an estimate instead.
  ///
  /// If you want to use forward error correction, don't report packet loss
  /// by calling this method with `null` as input (unless it is a real packet
  /// loss), but instead, wait for the next packet and call this method with
  /// the recieved packet, [fec] set to `true` and [loss] to the missing duration
  /// of the missing audio in ms (as above). Then, call this method a second time with
  /// the same packet, but with [fec] set to `false`. You can read more about the
  /// correct usage of forward error correction [here](https://stackoverflow.com/questions/49427579/how-to-use-fec-feature-for-opus-codec).
  /// Note: A real packet loss occurse if you lose two or more packets in a row.
  /// You are only able to restore the last lost packet and the other packets are
  /// really lost. So for them, you have to report packet loss.
  ///
  /// The input bytes need to represent a whole packet!
  Int16List decode({required Uint8List input, bool fec = false, int? loss}) {
    final outputNative = malloc.allocate<Int16>(sizeOf<Int16>() * _maxSamplesPerPacket);
    Pointer<Uint8> inputNative;
    inputNative = malloc.allocate<Uint8>(sizeOf<Uint8>() * input.length);
    inputNative.asTypedList(input.length).setAll(0, input);

    int frameSize;
    frameSize = (fec ? loss ?? lastPacketDurationMs : _maxSamplesPerPacket)!;
    final outputSamplesPerChannel = libopus.opus_decode(
      _opusDecoder,
      inputNative,
      input.length,
      outputNative,
      frameSize,
      fec ? 1 : 0,
    );
    try {
      if (outputSamplesPerChannel >= opus_bindings.OPUS_OK) {
        _lastPacketDurationMs = _packetDuration(outputSamplesPerChannel, channels, sampleRate);
        return Int16List.fromList(outputNative.asTypedList(outputSamplesPerChannel * channels));
      } else {
        throw OpusException(outputSamplesPerChannel);
      }
    } finally {
      malloc..free(inputNative)..free(outputNative);
    }
  }

  /// Decodes an opus packet to float samples, represented as [Float32List].
  /// Use `null` as [input] to indicate packet loss.
  ///
  /// If [autoSoftClip] is true, softcliping is applied to the output.
  /// This behaves just like  the top level [pcmSoftClip] function,
  /// but is more effective since it doesn't need to copy the samples,
  /// because they already are in the native buffer.
  ///
  /// Apart from that, this method behaves just as [decode], so see there for more information.
  Float32List decodeFloat({
    required Uint8List input,
    bool fec = false,
    bool autoSoftClip = false,
    int? loss,
  }) {
    final outputNative = malloc.allocate<Float>(sizeOf<Float>() * _maxSamplesPerPacket);
    Pointer<Uint8> inputNative;

    inputNative = malloc.allocate<Uint8>(sizeOf<Uint8>() * input.length);
    inputNative.asTypedList(input.length).setAll(0, input);

    int frameSize;
    frameSize = (fec ? loss ?? lastPacketDurationMs : _maxSamplesPerPacket)!;
    final outputSamplesPerChannel = libopus.opus_decode_float(
      _opusDecoder,
      inputNative,
      input.length,
      outputNative,
      frameSize,
      fec ? 1 : 0,
    );
    try {
      if (outputSamplesPerChannel >= opus_bindings.OPUS_OK) {
        _lastPacketDurationMs = _packetDuration(outputSamplesPerChannel, channels, sampleRate);
        if (autoSoftClip) {
          libopus.opus_pcm_soft_clip(
            outputNative,
            outputSamplesPerChannel ~/ channels,
            channels,
            _softClipBuffer,
          );
        }
        return Float32List.fromList(outputNative.asTypedList(outputSamplesPerChannel * channels));
      } else {
        throw OpusException(outputSamplesPerChannel);
      }
    } finally {
      malloc..free(inputNative)..free(outputNative);
    }
  }

  void destroy() {
    if (!_destroyed) {
      _destroyed = true;
      libopus.opus_decoder_destroy(_opusDecoder);
      malloc.free(_softClipBuffer);
    }
  }
}

/// An implementation of [OpusDecoder] that uses preallocated buffers.
/// Don't forget to call [destroy] once you are done with it.
///
/// The idea behind this implementation is to reduce the amount of memory allocation calls.
/// Instead of allocating new buffers everytime something is decoded, the buffers are
/// allocated at initalization. Then, an opus packet is directly written into the [inputBuffer],
/// the [inputBufferIndex] is updated, based on how many bytes where written, and
/// one of the deocde methods is called. The decoded pcm samples can then be accessed using
/// the [outputBuffer] getter (or one of the [outputBufferAsInt16List] or [outputBufferAsFloat32List] convenience getters).
/// ```
/// BufferedOpusDecoder decoder;
///
/// void example() {
///   // Get an opus packet
///   Uint8List packet = receivePacket();
///   // Set the bytes to the input buffer
///   decoder.inputBuffer.setAll(0, packet);
///   // Update the inputBufferIndex with amount of bytes written
///   decoder.inputBufferIndex = packet.length;
///   // decode
///   decoder.decode();
///   // Interpret the output as s16le
///   Int16List pcm = decoder.outputBufferAsInt16List;
///   doSomething(pcm);
/// }
/// ```
class BufferedOpusDecoder extends OpusDecoder {
  @override
  final int sampleRate;
  @override
  final int channels;

  /// The size of the allocated the input buffer in bytes.
  /// Should be choosen big enough to hold a maximal opus packet
  /// with size of [maxDataBytes] bytes.
  final int maxInputBufferSizeBytes;

  /// Indicates, how many bytes of data are currently stored in the [inputBuffer].
  int inputBufferIndex;

  /// The size of the allocated the output buffer. If this value is choosen
  /// to small, this decoder will not be capable of decoding some packets.
  ///
  /// See the constructor for information, how to choose this.
  final int maxOutputBufferSizeBytes;

  final Pointer<opus_bindings.OpusDecoder> _opusDecoder;

  bool _destroyed;
  int _lastPacketDurationMs = 0;

  final Pointer<Uint8> _inputBuffer;

  int _outputBufferIndex;
  final Pointer<Uint8> _outputBuffer;
  final Pointer<Float> _softClipBuffer;

  @override
  bool get destroyed => _destroyed;
  @override
  int get lastPacketDurationMs => _lastPacketDurationMs;

  /// Returns the native input buffer backed by native memory.
  ///
  /// You should write the opus packet you want to decode as bytes into this buffer,
  /// update the [inputBufferIndex] accordingly and call one of the decode methods.
  ///
  /// You must not put more bytes then [maxInputBufferSizeBytes] into this buffer.
  Uint8List get inputBuffer => _inputBuffer.asTypedList(maxInputBufferSizeBytes);

  /// The portion of the allocated output buffer that is currently filled with data.
  /// The data are pcm samples, either encoded as s16le or floats, depending on
  /// what method was used to decode the input packet.
  ///
  /// This method does not copy data from native memory to dart memory but
  /// rather gives a view backed by native memory.
  Uint8List get outputBuffer => _outputBuffer.asTypedList(_outputBufferIndex);

  /// Convenience method to get the current output buffer as s16le.
  Int16List get outputBufferAsInt16List =>
      _outputBuffer.cast<Int16>().asTypedList(_outputBufferIndex ~/ 2);

  /// Convenience method to get the current output buffer as floats.
  Float32List get outputBufferAsFloat32List =>
      _outputBuffer.cast<Float>().asTypedList(_outputBufferIndex ~/ 4);

  BufferedOpusDecoder._(
    this._opusDecoder,
    this.sampleRate,
    this.channels,
    this._inputBuffer,
    this.maxInputBufferSizeBytes,
    this._outputBuffer,
    this.maxOutputBufferSizeBytes,
    this._softClipBuffer,
  )   : _destroyed = false,
        inputBufferIndex = 0,
        _outputBufferIndex = 0;

  /// Creates an new [BufferedOpusDecoder] based on the [sampleRate] and [channels].
  /// The native allocated buffer size is determined by [maxInputBufferSizeBytes] and [maxOutputBufferSizeBytes].
  ///
  /// You should choose [maxInputBufferSizeBytes] big enough to put every opus packet you want to decode in it.
  /// If you omit this parameter, [maxDataByes] is used, which guarantees that there is enough space for every
  /// valid opus packet.
  ///
  /// [maxOutputBufferSizeBytes] is the size of the output buffer, which will hold the decoded frames.
  /// If this value is choosen to small, this decoder will not be capable of decoding some packets.
  /// If you are unsure, just let it `null`, so the maximum size of resulting frames will be calculated
  /// Here is some more theory about that:
  /// A single opus packet may contain up to 120ms of audio, so assuming you are decoding
  /// packets with [sampleRate] and [channels] and want them stored as s16le (2 bytes per sample),
  /// then `maxOutputBufferSizeBytes = [sampleRate]~/1000 * 120 * channels * 2`.
  /// If you want your samples stored as floats (using the [decodeFloat] method), you need to
  /// multiply by `4` instead of `2` (since a float takes 4 bytes per value).
  /// If you know the frame time in advance, you can use the above formula to choose a smaller value.
  /// Also note that there is a [maxSamplesPerPacket] function.
  ///
  /// For the other parameters, see the matching fields for more information.
  factory BufferedOpusDecoder({
    required int sampleRate,
    required int channels,
    int? maxInputBufferSizeBytes,
    int? maxOutputBufferSizeBytes,
  }) {
    maxInputBufferSizeBytes ??= maxDataBytes;
    maxOutputBufferSizeBytes ??= maxSamplesPerPacket(sampleRate, channels);
    final error = malloc.allocate<Int32>(sizeOf<Int32>() * 1);
    final input = malloc.allocate<Uint8>(sizeOf<Uint8>() * maxInputBufferSizeBytes);
    final output = malloc.allocate<Uint8>(sizeOf<Uint8>() * maxOutputBufferSizeBytes);
    final softClipBuffer = malloc.allocate<Float>(sizeOf<Float>() * channels);
    final encoder = libopus.opus_decoder_create(sampleRate, channels, error);
    try {
      if (error.value == opus_bindings.OPUS_OK) {
        return BufferedOpusDecoder._(
          encoder,
          sampleRate,
          channels,
          input,
          maxInputBufferSizeBytes,
          output,
          maxOutputBufferSizeBytes,
          softClipBuffer,
        );
      } else {
        malloc..free(input)..free(output)..free(softClipBuffer);
        throw OpusException(error.value);
      }
    } finally {
      malloc.free(error);
    }
  }

  /// Interpretes [inputBufferIndex] bytes from the [inputBuffer] as a whole
  /// opus packet and decodes them to s16le samples, stored in the [outputBuffer].
  /// Set [inputBufferIndex] to `0` to indicate packet loss.
  ///
  /// On packet loss, the [loss] parameter needs to be exactly the duration
  /// of audio that is missing in milliseconds, otherwise the decoder will
  /// not be in the optimal state to decode the next incoming packet.
  /// If you don't know the duration, leave it `null` and [lastPacketDurationMs]
  /// will be used as an estimate instead.
  ///
  /// If you want to use forward error correction, don't report packet loss
  /// by setting the [inputBufferIndex] to `0` (unless it is a real packet
  /// loss), but instead, wait for the next packet and write this to the [inputBuffer],
  /// with [inputBufferIndex] set accordingly. Then and call this method with
  /// [fec] set to `true` and [loss] to the missing duration of the missing audio
  /// in ms (as above). Then, call this method a second time with
  /// the same packet, but with [fec] set to `false`. You can read more about the
  /// correct usage of forward error correction [here](https://stackoverflow.com/questions/49427579/how-to-use-fec-feature-for-opus-codec).
  /// Note: A real packet loss occurse if you lose two or more packets in a row.
  /// You are only able to restore the last lost packet and the other packets are
  /// really lost. So for them, you have to report packet loss.
  ///
  /// The input bytes need to represent a whole packet!
  ///
  /// The returned list is actually just the [outputBufferAsInt16List].
  @override
  Int16List decode({bool fec = false, int? loss}) {
    Pointer<Uint8> inputNative;
    int frameSize;
    if (inputBufferIndex > 0) {
      inputNative = _inputBuffer;
      frameSize = maxOutputBufferSizeBytes ~/ (channels * 2);
    } else {
      inputNative = nullptr;
      frameSize = loss ?? lastPacketDurationMs;
    }
    final outputSamplesPerChannel = libopus.opus_decode(
      _opusDecoder,
      inputNative,
      inputBufferIndex,
      _outputBuffer.cast<Int16>(),
      frameSize,
      fec ? 1 : 0,
    );
    if (outputSamplesPerChannel >= opus_bindings.OPUS_OK) {
      _lastPacketDurationMs = _packetDuration(outputSamplesPerChannel, channels, sampleRate);
      _outputBufferIndex = outputSamplesPerChannel * channels * 2;
      return outputBufferAsInt16List;
    } else {
      throw OpusException(outputSamplesPerChannel);
    }
  }

  /// Interpretes [inputBufferIndex] bytes from the [inputBuffer] as a whole
  /// opus packet and decodes them to float samples, stored in the [outputBuffer].
  /// Set [inputBufferIndex] to `0` to indicate packet loss.
  ///
  /// If [autoSoftClip] is true, this decoders [pcmSoftClipOutputBuffer] method is automatically called.
  ///
  /// Apart from that, this method behaves just as [decode], so see there for more information.
  @override
  Float32List decodeFloat({bool autoSoftClip = false, bool fec = false, int? loss}) {
    Pointer<Uint8> inputNative;
    int frameSize;
    if (inputBufferIndex > 0) {
      inputNative = _inputBuffer;
      frameSize = maxOutputBufferSizeBytes ~/ (channels * 4);
    } else {
      inputNative = nullptr;
      frameSize = loss ?? lastPacketDurationMs;
    }
    final outputSamplesPerChannel = libopus.opus_decode_float(
      _opusDecoder,
      inputNative,
      inputBufferIndex,
      _outputBuffer.cast<Float>(),
      frameSize,
      fec ? 1 : 0,
    );
    if (outputSamplesPerChannel >= opus_bindings.OPUS_OK) {
      _lastPacketDurationMs = _packetDuration(outputSamplesPerChannel, channels, sampleRate);
      _outputBufferIndex = outputSamplesPerChannel * channels * 4;
      return autoSoftClip ? pcmSoftClipOutputBuffer() : outputBufferAsFloat32List;
    } else {
      throw OpusException(outputSamplesPerChannel);
    }
  }

  @override
  void destroy() {
    if (!_destroyed) {
      _destroyed = true;
      libopus.opus_decoder_destroy(_opusDecoder);
      malloc..free(_inputBuffer)..free(_outputBuffer)..free(_softClipBuffer);
    }
  }

  /// Performs soft clipping on the [outputBuffer].
  ///
  /// Behaves like the toplevel [pcmSoftClip] function, but without unnecessary copying.
  Float32List pcmSoftClipOutputBuffer() {
    libopus.opus_pcm_soft_clip(
      _outputBuffer.cast<Float>(),
      _outputBufferIndex ~/ (channels * 4),
      channels,
      _softClipBuffer,
    );
    return outputBufferAsFloat32List;
  }
}

/// Abstract base class for opus decoders.
abstract class OpusDecoder {
  /// The sample rate in Hz for this decoder.
  /// Opus supports sample rates from 8kHz to 48kHz so this value must be between 8000 and 48000.
  int get sampleRate;

  /// Number of channels, must be 1 for mono or 2 for stereo.
  int get channels;

  /// Wheter this decoder was already destroyed by calling [destroy].
  /// If so, calling any method will result in an [OpusDestroyedError].
  bool get destroyed;

  /// The duration of the last decoded packet in ms.
  int get lastPacketDurationMs;

  Int16List decode({bool fec = false, int loss});
  Float32List decodeFloat({bool autoSoftClip, bool fec = false, int loss});

  /// Destroys this decoder by releasing all native resources.
  /// After this, it is no longer possible to decode using this decoder, so any further method call will throw an [OpusDestroyedError].
  void destroy();
}
