
# opus_dart
Wraps libopus in dart, and additionally provides a dart friendly API for encoding and decoding.

<a name="toc"></a>
##### Table of Contents  
1. [Versioning](#versioning)  
2. [Choosing The Right Library](#choosing)<br>
    2.1 [The Bindings](#choosing_bindings)<br>
    2.2 [The Dart Friendly API](#choosing_firendly)<br>
3. [Initialization](#init)<br>
    3.1 [The Dart Friendly API](#init_friendly)<br>
    3.2 [What is `lib`?](#init_lib)<br>
    3.3 [Flutter](#init_flutter)<br>

<a name="versioning"></a>
## Versioning
Current libopus version: 1.3.1

See the changelog for other versions of libopus.

On small patches, the patch version of this package will increase, if a new Opus version is wrapped (but there are no API changes), the minor version will increase, and on breaking API changes, the major version will increase. So to ensure to get a specific version of Opus, lock in on major and minor version (e.g. `opus_dart: ">=1.0.0 <1.1.0"`), to always use the newest Opus version with compatible API, lock on the major version (e.g. `opus_dart: ">=1.0.0 <2.0.0"`). 

<a name="choosing"></a>
## Choosing The Right Library
<a name="choosing_bindings"></a>
### The Bindings
There are automatically generated bindings for most functions of the Opus include headers.
Variadic (especially the CTL) functions are [not supported](https://github.com/dart-lang/sdk/issues/38578) in Dart at the moment,
so they are missing, as well as makros.
The generated bindings can all be found in the /wrappers section and are named after the group they are from.
Documentation of the bounded functions was copied from the Opus headers (and is thus not very well formated).
The tool folder contains the code that was used for generation (for sake of completeness; note that ffi_tool ^0.3.0 is needed for generation, which might not be yet available on pub, so it's used directly from GitHub).

<a name="choosing_firendly"></a>
### The Dart Friendly API
Most users are interested in a more Dart like API to encode and decode Opus packages.
The opus_dart library provides this, so you don't have to take care of memory allocation and
similar tasks. The OpusEncoder and OpusDecoder are both implemented in two ways:
* SimpleOpusEncoder / SimpleOpusDecoder <br>
  These coders are very simple to use as they handle memory allocation/deallocation for you.
  As consequence, they make heavy use of buffer allocation.
* BufferedOpusEncoder / BufferedOpusDecoder <br>
  These coders allocate native memory just once. You can then directly write to the memory.
  When writing to the memory, you have to update the corresponding input index.

Performance gains of using the buffered versions over the simple versions varies.
Befor trying to optimize your code using a buffered version, try the simple version first.

There are also StreamTransformers that can help you encoding PCM streams to Opus packets,
or decode Opus packets to PCM streams.

WARNING: All classes have to be destroyed manually by calling their appropriate methods,
so that the allocated native memory can be released. Otherwise, a memory leak may occur!


<a name="init"></a>
## Initialization

<a name="init_friendly"></a>
### The Dart Friendly API
If using the dart firendly library opus_dart, you also have to initialize it using the toplevel `initOpus` function,
but unlike the bindings, there is no need to import it with a prefix. This would look like:

```
import 'package:opus_dart/opus_dart.dart';

void main(){
    initOpus(lib);
    // Check if you loaded the right version
    print(getOpusVersion());
}
```

<a name="init_lib"></a>
### What is `lib`?
As you may have noticed above, both, the Dart friendly API and the bindings need `lib` to initalize.
`lib` is a [DynamicLibrary](https://api.dart.dev/stable/2.7.0/dart-ffi/DynamicLibrary-class.html) instance, pointing to libopus.
On a dart:vm platform, you can dynamically load it:

```
import 'dart:ffi';

void main() {
  DynamicLibrary lib;
  if (Platform.isWindows) {
    bool x64 = Platform.version.contains('x64');
    if (x64) {
      lib = new DynamicLibrary.open('path/to/libopus_x64.dll');
    } else {
      lib = new DynamicLibrary.open('path/to/libopus_x86.dll');
    }
  } else if (Platform.isLinux) {
    lib = new DynamicLibrary.open('libopus.so');
  }
}
```
This package does not contain any binaries, and even if libopus is open source, no source files are included in this package either,
since there is [no native build system for the dart:vm](https://github.com/dart-lang/sdk/issues/36712) at the moment.
It's up to you to get them and to distribute them with your application.
Keep in mind that you need a dynamic library for all operating systems and architectures you want to support.
Whether you use prebuild binaries or compile libopus from [source](https://github.com/xiph/opus/) yourself, the version you use should match this packages wrapped version (see above). An example to build Opus can be found in the Dockerfile on this packages GitHub page.

<a name="init_flutter"></a>
### Flutter
Since Flutter for iOS and Android has a [native build system](https://github.com/dart-lang/sdk/issues/36712), there is [opus_flutter](https://pub.dev/packages/opus_flutter) which includes Opus sources and build configurations.