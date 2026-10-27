#ifndef RUNNER_STORE_UPDATE_H_
#define RUNNER_STORE_UPDATE_H_

#include <memory>
#include <mutex>
#include <string>

// Asks the Microsoft Store whether a newer package of this app is waiting.
//
// Windows never tells a packaged app that it is out of date, and the Store's own
// UI offers only "Open" for an app it already considers installed - the app has
// to ask. StoreContext's check is asynchronous and does its own network I/O, so
// it runs once on a worker thread and the method channel, which runs on the
// platform thread, only ever reads the latest answer. Keeping the flow one-way
// (Dart polls) means this class never has to call back into Flutter.
class StoreUpdateCheck {
 public:
  enum class State {
    kPending,      // the worker thread has not answered yet
    kAvailable,    // the Store has a newer package for this app
    kCurrent,      // up to date
    kUnavailable,  // no Store context: unpackaged build, or not Store-installed
  };

  struct Result {
    State state = State::kPending;
    std::string version;  // "a.b.c.d" when state is kAvailable
    std::string detail;   // why the check could not run, when kUnavailable
  };

  StoreUpdateCheck();
  ~StoreUpdateCheck();

  StoreUpdateCheck(const StoreUpdateCheck&) = delete;
  StoreUpdateCheck& operator=(const StoreUpdateCheck&) = delete;

  // Starts the one-shot background check. Calling it again is a no-op.
  void Start();

  // Latest known result. Never blocks.
  Result Current() const;

  // Stable wire name for the method channel.
  static const char* StateName(State state);

 private:
  struct Shared {
    std::mutex mutex;
    Result result;
    bool started = false;
  };

  // Shared with the worker thread, so a window that closes mid-check cannot
  // leave that thread writing into freed memory.
  std::shared_ptr<Shared> shared_;
};

#endif  // RUNNER_STORE_UPDATE_H_
