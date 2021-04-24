import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:opus_codec/opus_dart.dart';

/// Should be run from the example
Future<void> main() async {
  init();
  await example();
}

void init() {
  final lib = DynamicLibrary.open('libopus.so');

  initOpus(lib);
  print(getOpusVersion());
}

/// Get a stream, encode it and decode it, then save it to the harddrive
/// with a wav header.
Future<void> example() async {
  const sampleRate = 16000;
  const channels = 1;
  final input = File('s16le_16000hz_mono.raw').openRead();
  final file = File('output.raw');
  final output = file.openWrite()..add(Uint8List(wavHeaderSize));
  await input
      .transform(StreamOpusEncoder.bytes(
        floatInput: false,
        frameTime: FrameTime.ms20,
        sampleRate: sampleRate,
        channels: channels,
        application: Application.audio,
        copyOutput: true,
        fillUpLastFrame: true,
      ))
      .transform(StreamOpusDecoder.bytes(
        floatOutput: false,
        sampleRate: sampleRate,
        channels: channels,
        copyOutput: true,
        forwardErrorCorrection: false,
      ))
      .cast<List<int>>()
      .pipe(output);
  await output.close();
  //Write the wav header
  // RandomAccessFile r = await file.open(mode: FileMode.append);
  // await r.setPosition(0);
  // Uint8List header =
  //     wavHeader(channels: channels, sampleRate: sampleRate, fileSize: await file.length());
  // await r.writeFrom(header);
  // await r.close();
}

const int wavHeaderSize = 44;

Uint8List wavHeader({required int sampleRate, required int channels, required int fileSize}) {
  const sampleBits = 16; //We know this since we used opus
  const endian = Endian.little;
  final frameSize = ((sampleBits + 7) ~/ 8) * channels;
  final data = ByteData(wavHeaderSize)
    ..setUint32(4, fileSize - 4, endian)
    ..setUint32(16, 16, endian)
    ..setUint16(20, 1, endian)
    ..setUint16(22, channels, endian)
    ..setUint32(24, sampleRate, endian)
    ..setUint32(28, sampleRate * frameSize, endian)
    ..setUint16(30, frameSize, endian)
    ..setUint16(34, sampleBits, endian)
    ..setUint32(40, fileSize - 44, endian);
  final bytes = data.buffer.asUint8List()
    ..setAll(0, ascii.encode('RIFF'))
    ..setAll(8, ascii.encode('WAVE'))
    ..setAll(12, ascii.encode('fmt '))
    ..setAll(36, ascii.encode('data'));
  return bytes;
}
