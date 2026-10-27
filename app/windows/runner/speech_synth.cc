#include "speech_synth.h"

// Windows.Foundation carries the async-operation plumbing, Collections the
// voice list comes back in, and the stream types the synthesized audio is
// read from. MSVC needs them all complete before the async get() below
// (C3779 otherwise).
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.SpeechSynthesis.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

#include <cstdio>
#include <fstream>
#include <future>
#include <vector>

namespace {

std::string Describe(const winrt::hresult_error& error) {
  char code[16];
  std::snprintf(code, sizeof(code), "0x%08X",
                static_cast<unsigned int>(error.code().value));
  return std::string(code) + " " + winrt::to_string(error.message());
}

}  // namespace

std::vector<WindowsSpeech::Voice> WindowsSpeech::ListVoices(
    const std::string& language_prefix) {
  return std::async(std::launch::async, [language_prefix]() {
    std::vector<WindowsSpeech::Voice> voices;
    // C++/WinRT needs an apartment on whatever thread calls it; MTA is the
    // right one for a worker.
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    winrt::Windows::Media::SpeechSynthesis::SpeechSynthesizer synth;
    for (const auto& info : synth.AllVoices()) {
      WindowsSpeech::Voice voice;
      voice.id = winrt::to_string(info.Id());
      voice.name = winrt::to_string(info.DisplayName());
      voice.locale = winrt::to_string(info.Language());
      switch (info.Gender()) {
        case winrt::Windows::Media::SpeechSynthesis::VoiceGender::Male:
          voice.gender = "male";
          break;
        case winrt::Windows::Media::SpeechSynthesis::VoiceGender::Female:
          voice.gender = "female";
          break;
        default:
          voice.gender = "";
          break;
      }
      voice.local = voice.id.rfind("Microsoft Server", 0) != 0;
      if (!language_prefix.empty() &&
          voice.locale.rfind(language_prefix, 0) != 0) {
        continue;
      }
      voices.push_back(voice);
    }
    return voices;
  }).get();
}

bool WindowsSpeech::Synthesize(const std::string& text,
                               const std::string& voice_id, int rate,
                               const std::string& output_path,
                               std::string* error) {
  // The speaking rate lives on ISpeechSynthesizerOptions2, which the C++
  // projection does not expose (only the ABI helpers do), so [rate] is
  // accepted and ignored: the voice keeps its own pace.
  (void)rate;
  try {
    return std::async(std::launch::async, [&]() -> bool {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
      winrt::Windows::Media::SpeechSynthesis::SpeechSynthesizer synth;
      if (!voice_id.empty()) {
        bool found = false;
        for (const auto& info : synth.AllVoices()) {
          if (winrt::to_string(info.Id()) == voice_id) {
            synth.Voice(info);
            found = true;
            break;
          }
        }
        if (!found) {
          if (error != nullptr) *error = "unknown voice: " + voice_id;
          return false;
        }
      }

      auto stream =
          synth.SynthesizeTextToStreamAsync(winrt::to_hstring(text)).get();
      // SpeechSynthesisStream is an IRandomAccessStream, so the reader takes
      // it directly. The stream already carries a RIFF header, so the bytes
      // are a valid .wav file as they are.
      const uint64_t size = stream.Size();
      winrt::Windows::Storage::Streams::DataReader reader(stream);
      reader.LoadAsync(static_cast<uint32_t>(size)).get();
      std::vector<uint8_t> bytes(static_cast<size_t>(size));
      reader.ReadBytes(bytes);

      std::ofstream out(output_path, std::ios::binary);
      if (!out) {
        if (error != nullptr) *error = "cannot open " + output_path;
        return false;
      }
      out.write(reinterpret_cast<const char*>(bytes.data()),
                static_cast<std::streamsize>(bytes.size()));
      return out.good();
    }).get();
  } catch (const winrt::hresult_error& e) {
    if (error != nullptr) *error = Describe(e);
    return false;
  } catch (...) {
    if (error != nullptr) *error = "unknown failure";
    return false;
  }
}
