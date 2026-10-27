#include "flutter_window.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // "Is there a Store update for this app?" - the only way a packaged Windows app
  // can find out, and the reason the app can prompt at all. The check starts now
  // and answers asynchronously; Dart polls this channel, so the window never has
  // to call into Flutter.
  store_update_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "highlight_creator/store_update",
          &flutter::StandardMethodCodec::GetInstance());
  store_update_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "check") {
          result->NotImplemented();
          return;
        }
        const StoreUpdateCheck::Result update = store_update_.Current();
        flutter::EncodableMap payload;
        payload[flutter::EncodableValue("state")] = flutter::EncodableValue(
            std::string(StoreUpdateCheck::StateName(update.state)));
        payload[flutter::EncodableValue("version")] =
            flutter::EncodableValue(update.version);
        payload[flutter::EncodableValue("detail")] =
            flutter::EncodableValue(update.detail);
        result->Success(flutter::EncodableValue(payload));
      });
  store_update_.Start();

  // "Which voices does this Windows have, and read this text in one of them?"
  // The voices come from the speech packs the user installed, so the list
  // changes whenever they add one. The synthesis runs entirely offline.
  speech_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "highlight_creator/speech",
          &flutter::StandardMethodCodec::GetInstance());
  speech_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "voices") {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          std::string prefix;
          if (arguments != nullptr) {
            const auto found = arguments->find(
                flutter::EncodableValue("languagePrefix"));
            if (found != arguments->end()) {
              prefix = std::get<std::string>(found->second);
            }
          }
          const std::vector<WindowsSpeech::Voice> voices =
              speech_.ListVoices(prefix);
          flutter::EncodableList payload;
          for (const auto& voice : voices) {
            flutter::EncodableMap entry;
            entry[flutter::EncodableValue("id")] =
                flutter::EncodableValue(voice.id);
            entry[flutter::EncodableValue("name")] =
                flutter::EncodableValue(voice.name);
            entry[flutter::EncodableValue("locale")] =
                flutter::EncodableValue(voice.locale);
            entry[flutter::EncodableValue("gender")] =
                flutter::EncodableValue(voice.gender);
            entry[flutter::EncodableValue("local")] =
                flutter::EncodableValue(voice.local);
            payload.push_back(flutter::EncodableValue(entry));
          }
          result->Success(flutter::EncodableValue(payload));
          return;
        }
        if (call.method_name() == "synthesize") {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          std::string text;
          std::string voice_id;
          std::string output_path;
          int rate = 0;
          if (arguments != nullptr) {
            const auto value = [&](const char* key) -> std::string {
              const auto found = arguments->find(flutter::EncodableValue(key));
              if (found == arguments->end()) return std::string();
              const auto* text_value =
                  std::get_if<std::string>(&found->second);
              return text_value != nullptr ? *text_value : std::string();
            };
            text = value("text");
            voice_id = value("voiceId");
            output_path = value("outputPath");
            const auto found = arguments->find(flutter::EncodableValue("rate"));
            if (found != arguments->end()) {
              rate = std::get<int>(found->second);
            }
          }
          std::string error;
          const bool ok =
              speech_.Synthesize(text, voice_id, rate, output_path, &error);
          flutter::EncodableMap payload;
          payload[flutter::EncodableValue("ok")] = flutter::EncodableValue(ok);
          payload[flutter::EncodableValue("path")] =
              flutter::EncodableValue(output_path);
          payload[flutter::EncodableValue("error")] =
              flutter::EncodableValue(error);
          result->Success(flutter::EncodableValue(payload));
          return;
        }
        result->NotImplemented();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Drop the channel before the engine it borrows, and let the update check
  // finish on its own thread (it holds its own shared state).
  store_update_channel_ = nullptr;
  speech_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
