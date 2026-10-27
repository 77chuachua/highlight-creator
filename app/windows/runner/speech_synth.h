#ifndef RUNNER_SPEECH_SYNTH_H_
#define RUNNER_SPEECH_SYNTH_H_

#include <string>
#include <vector>

// Lists the speech voices Windows has installed and renders text to a WAV file.
//
// The voices come from the speech packs the user installed (Narrator voices in
// Settings, or the language speech pack). Everything runs offline: no key, no
// network, and the audio never leaves the machine.
//
// Both calls need a COM apartment, and the platform thread does not have one,
// so each call runs on a short-lived worker thread and blocks for the result.
class WindowsSpeech {
 public:
  struct Voice {
    std::string id;
    std::string name;
    std::string locale;
    std::string gender;
    // Server voices are the network ones; everything else is local.
    bool local = true;
  };

  // Installed voices, optionally filtered by language prefix ("zh").
  std::vector<Voice> ListVoices(const std::string& language_prefix);

  // Renders [text] with [voice_id] into [output_path]. Returns false and fills
  // [error] when the voice is unknown or the synthesis fails.
  bool Synthesize(const std::string& text, const std::string& voice_id,
                  int rate, const std::string& output_path,
                  std::string* error);
};

#endif  // RUNNER_SPEECH_SYNTH_H_
