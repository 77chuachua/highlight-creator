#include "store_update.h"

// Windows.Foundation carries the async-operation plumbing and Collections the
// IVectorView the update list comes back in. MSVC needs both complete before it
// can instantiate the async get() below (C3779 otherwise).
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Services.Store.h>
#include <winrt/base.h>

#include <cstdio>
#include <sstream>
#include <thread>

namespace {

std::string VersionToString(
    const winrt::Windows::ApplicationModel::PackageVersion& version) {
  std::ostringstream out;
  out << version.Major << '.' << version.Minor << '.' << version.Build << '.'
      << version.Revision;
  return out.str();
}

std::string Describe(const winrt::hresult_error& error) {
  char code[16];
  std::snprintf(code, sizeof(code), "0x%08X",
                static_cast<unsigned int>(error.code().value));
  return std::string(code) + " " + winrt::to_string(error.message());
}

}  // namespace

StoreUpdateCheck::StoreUpdateCheck() : shared_(std::make_shared<Shared>()) {}

StoreUpdateCheck::~StoreUpdateCheck() = default;

const char* StoreUpdateCheck::StateName(State state) {
  switch (state) {
    case State::kAvailable:
      return "available";
    case State::kCurrent:
      return "current";
    case State::kUnavailable:
      return "unavailable";
    case State::kPending:
    default:
      return "pending";
  }
}

void StoreUpdateCheck::Start() {
  const std::shared_ptr<Shared> shared = shared_;
  {
    std::lock_guard<std::mutex> lock(shared->mutex);
    if (shared->started) {
      return;
    }
    shared->started = true;
  }

  std::thread([shared]() {
    Result result;
    try {
      // The check reaches the Store over the network, so it belongs off the
      // platform thread. C++/WinRT needs an apartment on whatever thread calls
      // it; MTA is the right one for a worker.
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
      auto context =
          winrt::Windows::Services::Store::StoreContext::GetDefault();
      auto updates = context.GetAppAndOptionalStorePackageUpdatesAsync().get();
      if (updates.Size() > 0) {
        result.state = State::kAvailable;
        result.version =
            VersionToString(updates.GetAt(0).Package().Id().Version());
      } else {
        result.state = State::kCurrent;
      }
    } catch (const winrt::hresult_error& error) {
      // A dev build, and a package the Store did not install, have no Store
      // context at all. Report that instead of pretending the app is current:
      // Dart logs the detail and simply does not prompt.
      result.state = State::kUnavailable;
      result.detail = Describe(error);
    } catch (...) {
      result.state = State::kUnavailable;
      result.detail = "unknown failure";
    }
    std::lock_guard<std::mutex> lock(shared->mutex);
    shared->result = result;
  }).detach();
}

StoreUpdateCheck::Result StoreUpdateCheck::Current() const {
  std::lock_guard<std::mutex> lock(shared_->mutex);
  return shared_->result;
}
