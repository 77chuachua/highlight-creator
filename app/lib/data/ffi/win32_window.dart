import 'dart:ffi';
import 'dart:io' show Platform;

/// Minimal Win32 bindings to maximize/restore the OS window hosting the
/// Flutter view, so the Auto Gen dialog can go full screen (not just fill
/// the current app window).
///
/// ponytail: ceiling = GetActiveWindow assumes the Flutter view is the
/// thread's active window (true while the user clicks inside it); upgrade
/// path is window_manager if more window control is ever needed.
class Win32Window {
  static const int _swMaximize = 3;
  static const int _swRestore = 9;

  static DynamicLibrary? _user32;

  static DynamicLibrary? get _lib {
    if (!Platform.isWindows) return null;
    return _user32 ??= DynamicLibrary.open('user32.dll');
  }

  static int _getActiveWindow() {
    final lib = _lib;
    if (lib == null) return 0;
    final f = lib.lookupFunction<IntPtr Function(), int Function()>('GetActiveWindow');
    return f();
  }

  static bool get isMaximized {
    final lib = _lib;
    if (lib == null) return false;
    final f = lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsZoomed');
    return f(_getActiveWindow()) != 0;
  }

  static void maximize() => _show(_swMaximize);

  static void restore() => _show(_swRestore);

  static void _show(int cmd) {
    final lib = _lib;
    if (lib == null) return;
    final f = lib.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
    f(_getActiveWindow(), cmd);
  }
}
