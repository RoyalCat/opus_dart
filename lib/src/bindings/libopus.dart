import 'dart:ffi' as ffi;

import 'opus_bindings.dart';

LibOpus get libopus {
  if (_libopus != null) {
    return _libopus!;
  } else {
    throw NullThrownError();
  }
}

/// Dynamic library
LibOpus? _libopus;

/// Must be called to initalize this library.
///
/// The [DynamicLibrary] `opus` must point to a platform native libopus library with the appropriate version.
/// See the README for more information about loading and versioning.
void initOpus(ffi.DynamicLibrary library) {
  _libopus = LibOpus(library);
}
