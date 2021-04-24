import 'dart:ffi';

import 'package:opus_codec/opus_dart.dart';

void main() {
  final lib = DynamicLibrary.open('libopus.so');

  initOpus(lib);
  print(getOpusVersion());
}
