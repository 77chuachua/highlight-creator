#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "speech_synth.h"
#include "store_update.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Answers Dart's "does the Store have a newer package for this app?" question.
  // The channel is declared after the controller so it is destroyed first: it
  // borrows the engine's messenger.
  StoreUpdateCheck store_update_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      store_update_channel_;

  // Lists the installed Windows speech voices and renders text to WAV files.
  // Declared after the controller so it is destroyed first: it borrows the
  // engine's messenger through its channel.
  WindowsSpeech speech_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      speech_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
