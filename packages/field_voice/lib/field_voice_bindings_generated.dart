// Application shim bindings. Vendor signatures verified against pinned needle.h.
import 'dart:ffi';

@Native<Int32 Function()>(symbol: 'fa_available')
external int faAvailable();
@Native<Int32 Function(Pointer<Uint8>, Uint64)>(symbol: 'fa_load')
external int faLoad(Pointer<Uint8> bytes, int size);
@Native<Pointer<Char> Function()>(symbol: 'fa_last_error')
external Pointer<Char> faLastError();
@Native<Int32 Function(Pointer<Char>, Pointer<Char>)>(symbol: 'fa_init')
external int faInit(Pointer<Char> system, Pointer<Char> tools);
@Native<
  Int32 Function(Pointer<Float>, Int32, Pointer<Char>, Pointer<Char>, Int32)
>(symbol: 'fa_transcribe')
external int faTranscribe(
  Pointer<Float> pcm,
  int samples,
  Pointer<Char> language,
  Pointer<Char> output,
  int capacity,
);
@Native<Int32 Function(Pointer<Char>, Pointer<Char>, Int32)>(
  symbol: 'fa_complete',
)
external int faComplete(Pointer<Char> text, Pointer<Char> output, int capacity);
@Native<Void Function()>(symbol: 'fa_reset')
external void faReset();
