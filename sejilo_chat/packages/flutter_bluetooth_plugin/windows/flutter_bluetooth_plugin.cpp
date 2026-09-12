#include "flutter_bluetooth_plugin.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif

// This must be included before many other Windows headers.
#include <windows.h>

#include <VersionHelpers.h>
#include <objbase.h>
#include <shellapi.h>

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cctype>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <exception>
#include <functional>
#include <future>
#include <iomanip>
#include <memory>
#include <mutex>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace flutter_bluetooth_plugin {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Devices::Bluetooth::BluetoothAdapter;
using winrt::Windows::Devices::Bluetooth::BluetoothCacheMode;
using winrt::Windows::Devices::Bluetooth::BluetoothError;
using winrt::Windows::Devices::Bluetooth::BluetoothConnectionStatus;
using winrt::Windows::Devices::Bluetooth::BluetoothLEDevice;
using winrt::Windows::Devices::Bluetooth::Advertisement::
    BluetoothLEAdvertisementDataSection;
using winrt::Windows::Devices::Bluetooth::Advertisement::
    BluetoothLEAdvertisementReceivedEventArgs;
using winrt::Windows::Devices::Bluetooth::Advertisement::
    BluetoothLEAdvertisementPublisher;
using winrt::Windows::Devices::Bluetooth::Advertisement::
    BluetoothLEAdvertisementWatcher;
using winrt::Windows::Devices::Bluetooth::Advertisement::
    BluetoothLEAdvertisementWatcherStatus;
using winrt::Windows::Devices::Bluetooth::Advertisement::
    BluetoothLEAdvertisementWatcherStoppedEventArgs;
using winrt::Windows::Devices::Bluetooth::Advertisement::
    BluetoothLEScanningMode;
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
    GattCharacteristic;
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
    GattCharacteristicProperties;
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
    GattCharacteristicsResult;

constexpr UINT kPlatformTaskMessage = WM_APP + 0x53A;

class DispatchingMethodResult final
    : public flutter::MethodResult<EncodableValue> {
 public:
  using Task = std::function<void()>;
  using Dispatcher = std::function<bool(Task)>;

  DispatchingMethodResult(
      std::shared_ptr<flutter::MethodResult<EncodableValue>> target,
      Dispatcher dispatcher)
      : target_(std::move(target)), dispatcher_(std::move(dispatcher)) {}

 protected:
  void SuccessInternal(const EncodableValue* result) override {
    const std::optional<EncodableValue> value =
        result ? std::optional<EncodableValue>(*result) : std::nullopt;
    Dispatch([target = target_, value]() {
      if (value) {
        target->Success(*value);
      } else {
        target->Success();
      }
    });
  }

  void ErrorInternal(const std::string& error_code,
                     const std::string& error_message,
                     const EncodableValue* error_details) override {
    const std::optional<EncodableValue> details =
        error_details ? std::optional<EncodableValue>(*error_details)
                      : std::nullopt;
    Dispatch([target = target_, error_code, error_message, details]() {
      if (details) {
        target->Error(error_code, error_message, *details);
      } else {
        target->Error(error_code, error_message);
      }
    });
  }

  void NotImplementedInternal() override {
    Dispatch([target = target_]() { target->NotImplemented(); });
  }

 private:
  void Dispatch(Task task) {
    // A missing dispatcher only occurs while the plugin is shutting down.
    // Do not issue a platform-channel reply from the BLE worker in that case.
    dispatcher_(std::move(task));
  }

  std::shared_ptr<flutter::MethodResult<EncodableValue>> target_;
  Dispatcher dispatcher_;
};
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
    GattClientCharacteristicConfigurationDescriptorValue;
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
    GattCommunicationStatus;
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
    GattDescriptor;
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
    GattDescriptorsResult;
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
    GattDeviceService;
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
    GattDeviceServicesResult;
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
    GattReadResult;
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
    GattWriteOption;
using winrt::Windows::Devices::Enumeration::DeviceInformation;
using winrt::Windows::Devices::Radios::Radio;
using winrt::Windows::Devices::Radios::RadioState;
using winrt::Windows::Foundation::IInspectable;
using winrt::Windows::Storage::Streams::DataReader;
using winrt::Windows::Storage::Streams::DataWriter;
using winrt::Windows::Storage::Streams::IBuffer;

constexpr char kBluetoothUnavailableCode[] = "bluetooth_unavailable";
constexpr char kInvalidArgumentsCode[] = "invalid_arguments";
constexpr char kOperationFailedCode[] = "operation_failed";

std::string AsciiErrorMessage(std::string message) {
  for (char& character : message) {
    const auto byte = static_cast<unsigned char>(character);
    if (byte < 0x20 || byte > 0x7e) {
      character = '?';
    }
  }
  return message;
}
constexpr char kUnsupportedCode[] = "unsupported";

void Put(EncodableMap& map, const char* key, EncodableValue value) {
  map[EncodableValue(std::string(key))] = std::move(value);
}

EncodableValue NullValue() {
  return EncodableValue();
}

EncodableValue StringValue(const std::string& value) {
  return EncodableValue(value);
}

EncodableValue ByteValue(const std::vector<uint8_t>& bytes) {
  return EncodableValue(bytes);
}

EncodableValue StringListValue(const std::vector<std::string>& values) {
  EncodableList list;
  list.reserve(values.size());
  for (const auto& value : values) {
    list.emplace_back(value);
  }
  return EncodableValue(std::move(list));
}

const EncodableMap* ArgumentsAsMap(
    const flutter::MethodCall<EncodableValue>& method_call) {
  const EncodableValue* arguments = method_call.arguments();
  if (!arguments) {
    return nullptr;
  }
  return std::get_if<EncodableMap>(arguments);
}

const EncodableValue* FindArg(const EncodableMap* args, const char* key) {
  if (!args) {
    return nullptr;
  }
  auto it = args->find(EncodableValue(std::string(key)));
  return it == args->end() ? nullptr : &it->second;
}

std::optional<std::string> GetStringArg(const EncodableMap* args,
                                        const char* key) {
  const EncodableValue* value = FindArg(args, key);
  if (!value || std::holds_alternative<std::monostate>(*value)) {
    return std::nullopt;
  }
  if (const auto* string_value = std::get_if<std::string>(value)) {
    return *string_value;
  }
  return std::nullopt;
}

std::string GetRequiredStringArg(const EncodableMap* args, const char* key) {
  auto value = GetStringArg(args, key);
  if (!value || value->empty()) {
    throw std::invalid_argument(std::string("Missing required argument: ") +
                                key);
  }
  return *value;
}

bool GetBoolArg(const EncodableMap* args, const char* key,
                bool default_value = false) {
  const EncodableValue* value = FindArg(args, key);
  if (!value) {
    return default_value;
  }
  if (const auto* bool_value = std::get_if<bool>(value)) {
    return *bool_value;
  }
  return default_value;
}

std::optional<int64_t> GetIntArg(const EncodableMap* args, const char* key) {
  const EncodableValue* value = FindArg(args, key);
  if (!value || std::holds_alternative<std::monostate>(*value)) {
    return std::nullopt;
  }
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    return *int32_value;
  }
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    return *int64_value;
  }
  if (const auto* double_value = std::get_if<double>(value)) {
    return static_cast<int64_t>(*double_value);
  }
  return std::nullopt;
}

std::vector<std::string> GetStringListArg(const EncodableMap* args,
                                          const char* key) {
  const EncodableValue* value = FindArg(args, key);
  if (!value || std::holds_alternative<std::monostate>(*value)) {
    return {};
  }
  const auto* list = std::get_if<EncodableList>(value);
  if (!list) {
    return {};
  }

  std::vector<std::string> result;
  result.reserve(list->size());
  for (const auto& item : *list) {
    if (const auto* string_value = std::get_if<std::string>(&item)) {
      result.push_back(*string_value);
    }
  }
  return result;
}

std::vector<uint8_t> GetByteListArg(const EncodableMap* args, const char* key) {
  const EncodableValue* value = FindArg(args, key);
  if (!value || std::holds_alternative<std::monostate>(*value)) {
    return {};
  }
  if (const auto* bytes = std::get_if<std::vector<uint8_t>>(value)) {
    return *bytes;
  }
  if (const auto* int32_values = std::get_if<std::vector<int32_t>>(value)) {
    std::vector<uint8_t> result;
    result.reserve(int32_values->size());
    for (int32_t item : *int32_values) {
      result.push_back(static_cast<uint8_t>(item));
    }
    return result;
  }
  if (const auto* int64_values = std::get_if<std::vector<int64_t>>(value)) {
    std::vector<uint8_t> result;
    result.reserve(int64_values->size());
    for (int64_t item : *int64_values) {
      result.push_back(static_cast<uint8_t>(item));
    }
    return result;
  }
  if (const auto* list = std::get_if<EncodableList>(value)) {
    std::vector<uint8_t> result;
    result.reserve(list->size());
    for (const auto& item : *list) {
      if (const auto* int32_value = std::get_if<int32_t>(&item)) {
        result.push_back(static_cast<uint8_t>(*int32_value));
      } else if (const auto* int64_value = std::get_if<int64_t>(&item)) {
        result.push_back(static_cast<uint8_t>(*int64_value));
      }
    }
    return result;
  }
  return {};
}

std::string ToLower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](char ch) {
    return static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
  });
  return value;
}

std::string HStringToString(const winrt::hstring& value) {
  return winrt::to_string(value);
}

std::string FormatBluetoothAddress(uint64_t address) {
  char buffer[13] = {};
  std::snprintf(buffer, sizeof(buffer), "%012llX",
                static_cast<unsigned long long>(address));
  return std::string(buffer);
}

std::string FormatBluetoothAddressDisplay(uint64_t address) {
  const std::string compact = FormatBluetoothAddress(address);
  std::ostringstream stream;
  for (size_t index = 0; index < compact.size(); index += 2) {
    if (index > 0) {
      stream << ':';
    }
    stream << compact.substr(index, 2);
  }
  return stream.str();
}

std::optional<uint64_t> ParseBluetoothAddress(std::string value) {
  value.erase(std::remove_if(value.begin(), value.end(), [](char ch) {
                return ch == ':' || ch == '-' || std::isspace(
                                             static_cast<unsigned char>(ch));
              }),
              value.end());
  if (value.empty()) {
    return std::nullopt;
  }

  const bool looks_hex = value.size() <= 16 &&
                         std::all_of(value.begin(), value.end(), [](char ch) {
                           return std::isxdigit(
                                      static_cast<unsigned char>(ch)) != 0;
                         });
  try {
    size_t parsed = 0;
    uint64_t result = std::stoull(value, &parsed, looks_hex ? 16 : 10);
    if (parsed == value.size()) {
      return result;
    }
  } catch (...) {
  }
  return std::nullopt;
}

std::optional<winrt::guid> ParseGuid(const std::string& value) {
  std::wstring wide = winrt::to_hstring(value).c_str();
  if (wide.empty()) {
    return std::nullopt;
  }
  if (wide.front() != L'{') {
    wide.insert(wide.begin(), L'{');
    wide.push_back(L'}');
  }

  GUID parsed = {};
  if (FAILED(CLSIDFromString(wide.c_str(), &parsed))) {
    return std::nullopt;
  }

  winrt::guid result = {};
  static_assert(sizeof(result) == sizeof(parsed),
                "winrt::guid must match GUID layout");
  std::memcpy(&result, &parsed, sizeof(result));
  return result;
}

std::string GuidToString(const winrt::guid& guid) {
  GUID value = {};
  static_assert(sizeof(value) == sizeof(guid),
                "GUID must match winrt::guid layout");
  std::memcpy(&value, &guid, sizeof(value));

  wchar_t buffer[39] = {};
  if (StringFromGUID2(value, buffer, 39) == 0) {
    return {};
  }
  std::wstring wide(buffer);
  if (wide.size() >= 2 && wide.front() == L'{' && wide.back() == L'}') {
    wide = wide.substr(1, wide.size() - 2);
  }
  return ToLower(winrt::to_string(wide));
}

std::vector<uint8_t> BufferToBytes(const IBuffer& buffer) {
  if (!buffer) {
    return {};
  }
  DataReader reader = DataReader::FromBuffer(buffer);
  std::vector<uint8_t> bytes(reader.UnconsumedBufferLength());
  if (!bytes.empty()) {
    reader.ReadBytes(
        winrt::array_view<uint8_t>(bytes.data(), bytes.data() + bytes.size()));
  }
  return bytes;
}

IBuffer BytesToBuffer(const std::vector<uint8_t>& bytes) {
  DataWriter writer;
  if (!bytes.empty()) {
    writer.WriteBytes(winrt::array_view<const uint8_t>(
        bytes.data(), bytes.data() + bytes.size()));
  }
  return writer.DetachBuffer();
}

std::string AdapterStateString(RadioState state) {
  switch (state) {
    case RadioState::On:
      return "poweredOn";
    case RadioState::Off:
      return "poweredOff";
    case RadioState::Disabled:
      return "unauthorized";
    default:
      return "unknown";
  }
}

std::string ConnectionStateString(BluetoothConnectionStatus status) {
  return status == BluetoothConnectionStatus::Connected ? "connected"
                                                        : "disconnected";
}

std::string GattStatusMessage(GattCommunicationStatus status) {
  switch (status) {
    case GattCommunicationStatus::Success:
      return "Success";
    case GattCommunicationStatus::Unreachable:
      return "The Bluetooth device is unreachable.";
    case GattCommunicationStatus::ProtocolError:
      return "The GATT operation failed with a protocol error.";
    case GattCommunicationStatus::AccessDenied:
      return "Access to the GATT attribute was denied.";
    default:
      return "The GATT operation failed.";
  }
}

bool HasProperty(GattCharacteristicProperties properties,
                 GattCharacteristicProperties flag) {
  return (static_cast<uint32_t>(properties) & static_cast<uint32_t>(flag)) != 0;
}

std::vector<std::string> CharacteristicPropertiesToStrings(
    GattCharacteristicProperties properties) {
  std::vector<std::string> result;
  if (HasProperty(properties, GattCharacteristicProperties::Broadcast)) {
    result.push_back("broadcast");
  }
  if (HasProperty(properties, GattCharacteristicProperties::Read)) {
    result.push_back("read");
  }
  if (HasProperty(properties, GattCharacteristicProperties::WriteWithoutResponse)) {
    result.push_back("writeWithoutResponse");
  }
  if (HasProperty(properties, GattCharacteristicProperties::Write)) {
    result.push_back("write");
  }
  if (HasProperty(properties, GattCharacteristicProperties::Notify)) {
    result.push_back("notify");
  }
  if (HasProperty(properties, GattCharacteristicProperties::Indicate)) {
    result.push_back("indicate");
  }
  if (HasProperty(properties,
                  GattCharacteristicProperties::AuthenticatedSignedWrites)) {
    result.push_back("authenticatedSignedWrites");
  }
  if (HasProperty(properties, GattCharacteristicProperties::ReliableWrites)) {
    result.push_back("reliableWrite");
  }
  if (HasProperty(properties, GattCharacteristicProperties::WritableAuxiliaries)) {
    result.push_back("writableAuxiliaries");
  }
  return result;
}

EncodableMap RawWindowsMap() {
  EncodableMap raw;
  Put(raw, "platform", StringValue("windows"));
  return raw;
}

EncodableMap DeviceMapFromDevice(const BluetoothLEDevice& device) {
  EncodableMap map;
  if (!device) {
    return map;
  }

  const uint64_t address = device.BluetoothAddress();
  const std::string id = address == 0 ? HStringToString(device.DeviceId())
                                      : FormatBluetoothAddress(address);
  const std::string name = HStringToString(device.Name());

  Put(map, "id", StringValue(id));
  Put(map, "name", name.empty() ? NullValue() : StringValue(name));
  if (address != 0) {
    Put(map, "address", StringValue(FormatBluetoothAddressDisplay(address)));
  }
  Put(map, "type", StringValue("ble"));
  Put(map, "isConnected",
      EncodableValue(device.ConnectionStatus() ==
                     BluetoothConnectionStatus::Connected));
  bool paired = false;
  try {
    paired = device.DeviceInformation().Pairing().IsPaired();
  } catch (...) {
  }
  Put(map, "isBonded", EncodableValue(paired));

  EncodableMap raw = RawWindowsMap();
  Put(raw, "deviceId", StringValue(HStringToString(device.DeviceId())));
  Put(raw, "bluetoothAddress", StringValue(FormatBluetoothAddress(address)));
  Put(map, "raw", EncodableValue(std::move(raw)));
  return map;
}

EncodableMap DeviceMapFromDeviceInformation(const DeviceInformation& info) {
  EncodableMap map;
  const std::string id = HStringToString(info.Id());
  const std::string name = HStringToString(info.Name());
  Put(map, "id", StringValue(id));
  Put(map, "name", name.empty() ? NullValue() : StringValue(name));
  Put(map, "type", StringValue("ble"));
  Put(map, "isConnected", EncodableValue(false));
  Put(map, "isBonded", EncodableValue(info.Pairing().IsPaired()));

  EncodableMap raw = RawWindowsMap();
  Put(raw, "deviceId", StringValue(id));
  Put(map, "raw", EncodableValue(std::move(raw)));
  return map;
}

EncodableMap DescriptorMap(const GattDescriptor& descriptor,
                           const std::string& characteristic_uuid) {
  EncodableMap map;
  Put(map, "uuid", StringValue(GuidToString(descriptor.Uuid())));
  Put(map, "characteristicUuid", StringValue(characteristic_uuid));
  Put(map, "value", ByteValue({}));
  Put(map, "raw", EncodableValue(RawWindowsMap()));
  return map;
}

EncodableMap CharacteristicMap(const GattCharacteristic& characteristic,
                               const std::string& service_uuid) {
  EncodableMap map;
  const std::string characteristic_uuid = GuidToString(characteristic.Uuid());
  Put(map, "uuid", StringValue(characteristic_uuid));
  Put(map, "serviceUuid", StringValue(service_uuid));
  Put(map, "properties",
      StringListValue(
          CharacteristicPropertiesToStrings(characteristic.CharacteristicProperties())));
  Put(map, "permissions", StringListValue({}));
  Put(map, "value", ByteValue({}));

  EncodableList descriptors;
  try {
    GattDescriptorsResult descriptors_result =
        characteristic.GetDescriptorsAsync(BluetoothCacheMode::Uncached).get();
    if (descriptors_result.Status() != GattCommunicationStatus::Success) {
      descriptors_result =
          characteristic.GetDescriptorsAsync(BluetoothCacheMode::Cached).get();
    }
    if (descriptors_result.Status() == GattCommunicationStatus::Success) {
      for (const auto& descriptor : descriptors_result.Descriptors()) {
        descriptors.emplace_back(
            DescriptorMap(descriptor, characteristic_uuid));
      }
    }
  } catch (...) {
    // Descriptor discovery can fail for protected attributes; expose the
    // characteristic itself so callers can still address known descriptors.
  }
  Put(map, "descriptors", EncodableValue(std::move(descriptors)));
  Put(map, "raw", EncodableValue(RawWindowsMap()));
  return map;
}

EncodableMap ServiceMap(const GattDeviceService& service) {
  EncodableMap map;
  const std::string service_uuid = GuidToString(service.Uuid());
  Put(map, "uuid", StringValue(service_uuid));
  Put(map, "isPrimary", EncodableValue(true));
  Put(map, "includedServices", StringListValue({}));

  EncodableList characteristics;
  try {
    GattCharacteristicsResult characteristics_result =
        service.GetCharacteristicsAsync(BluetoothCacheMode::Uncached).get();
    if (characteristics_result.Status() != GattCommunicationStatus::Success ||
        characteristics_result.Characteristics().Size() == 0) {
      characteristics_result =
          service.GetCharacteristicsAsync(BluetoothCacheMode::Cached).get();
    }
    if (characteristics_result.Status() == GattCommunicationStatus::Success) {
      for (const auto& characteristic : characteristics_result.Characteristics()) {
        characteristics.emplace_back(
            CharacteristicMap(characteristic, service_uuid));
      }
    }
  } catch (...) {
    // Leave characteristics empty if Windows denies enumeration for a service.
  }
  Put(map, "characteristics", EncodableValue(std::move(characteristics)));
  Put(map, "raw", EncodableValue(RawWindowsMap()));
  return map;
}

}  // namespace

class FlutterBluetoothPlugin::Impl
    : public std::enable_shared_from_this<FlutterBluetoothPlugin::Impl> {
 public:
  Impl() : worker_thread_([this]() { WorkerLoop(); }) {}

  ~Impl() {
    try {
      RunOnWorkerSync([this]() {
        StopScanInternal();
        ClearGattServer();
        CloseDevicesInternal();
      });
    } catch (...) {
    }
    StopWorker();
    ClearEventSink();
    if (const HWND window = platform_window_.exchange(nullptr)) {
      DestroyWindow(window);
    }
  }

  void OnListen(std::unique_ptr<flutter::EventSink<EncodableValue>> events) {
    {
      std::lock_guard<std::mutex> lock(event_mutex_);
      event_sink_ = std::move(events);
    }

    try {
      RunOnWorkerSync([this]() { SendAdapterStateEvent(); });
    } catch (...) {
    }
  }

  void OnCancel() { ClearEventSink(); }

  bool CreatePlatformDispatcher() {
    constexpr wchar_t kWindowClass[] =
        L"SejiloFlutterBluetoothPlatformDispatcher";
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = PlatformWindowProc;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.lpszClassName = kWindowClass;
    if (RegisterClassW(&window_class) == 0 &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      return false;
    }
    const HWND window = CreateWindowExW(
        0, kWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
        window_class.hInstance, this);
    platform_window_.store(window);
    return window != nullptr;
  }

  void DrainPlatformTasks() {
    std::deque<std::function<void()>> tasks;
    {
      std::lock_guard<std::mutex> lock(platform_mutex_);
      tasks.swap(platform_tasks_);
    }
    for (auto& task : tasks) {
      task();
    }
  }

  void HandleMethodCall(
      const flutter::MethodCall<EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const std::string method = method_call.method_name();
    const EncodableMap* args = ArgumentsAsMap(method_call);
    const EncodableMap args_copy = args ? *args : EncodableMap{};
    auto shared_result =
        std::shared_ptr<flutter::MethodResult<EncodableValue>>(
            std::move(result));
    if (!PostWorkerTask(
            [this, method, args_copy, shared_result]() mutable {
              DispatchingMethodResult dispatched_result(
                  shared_result,
                  [this](std::function<void()> task) {
                    return PostPlatformTask(std::move(task));
                  });
              HandleMethodCallOnWorker(method, &args_copy,
                                       &dispatched_result);
            })) {
      shared_result->Error(kOperationFailedCode,
                           "Windows Bluetooth worker is stopping.");
    }
  }

 private:
  static LRESULT CALLBACK PlatformWindowProc(HWND window,
                                             UINT message,
                                             WPARAM wparam,
                                             LPARAM lparam) {
    Impl* impl = reinterpret_cast<Impl*>(
        GetWindowLongPtr(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      const auto* create = reinterpret_cast<CREATESTRUCT*>(lparam);
      impl = static_cast<Impl*>(create->lpCreateParams);
      SetWindowLongPtr(window, GWLP_USERDATA,
                       reinterpret_cast<LONG_PTR>(impl));
    }
    if (message == kPlatformTaskMessage && impl != nullptr) {
      impl->DrainPlatformTasks();
      return 0;
    }
    return DefWindowProc(window, message, wparam, lparam);
  }

  bool PostPlatformTask(std::function<void()> task) {
    const HWND window = platform_window_.load();
    if (window == nullptr) {
      // Native unit tests do not create a Flutter window.
      task();
      return true;
    }
    {
      std::lock_guard<std::mutex> lock(platform_mutex_);
      platform_tasks_.push_back(std::move(task));
    }
    if (PostMessage(window, kPlatformTaskMessage, 0, 0)) {
      return true;
    }
    return false;
  }

  void HandleMethodCallOnWorker(
      const std::string& method,
      const EncodableMap* args,
      flutter::MethodResult<EncodableValue>* result) {
    try {
      if (method == "getPlatformVersion") {
        result->Success(EncodableValue(GetPlatformVersion()));
      } else if (method == "isSupported") {
        result->Success(EncodableValue(IsSupported()));
      } else if (method == "getAdapterState") {
        result->Success(EncodableValue(CurrentAdapterStateString()));
      } else if (method == "getAdapterInfo") {
        result->Success(EncodableValue(AdapterInfoMap()));
      } else if (method == "isScanning") {
        result->Success(EncodableValue(IsScanning()));
      } else if (method == "setAdapterName") {
        result->Success(EncodableValue(false));
      } else if (method == "checkPermissions" || method == "requestPermissions") {
        result->Success(EncodableValue(PermissionMap()));
      } else if (method == "requestEnable") {
        result->Success(EncodableValue(false));
      } else if (method == "openBluetoothSettings") {
        OpenBluetoothSettings();
        result->Success();
      } else if (method == "startScan") {
        StartScan(args, result);
      } else if (method == "stopScan") {
        StopScanInternal();
        result->Success();
      } else if (method == "getBondedDevices") {
        result->Success(EncodableValue(GetBondedDevices()));
      } else if (method == "getConnectedDevices") {
        result->Success(EncodableValue(GetConnectedDevices(args)));
      } else if (method == "getDevice") {
        GetDevice(args, result);
      } else if (method == "getDevices") {
        result->Success(EncodableValue(GetDevices(args)));
      } else if (method == "connect") {
        // Acknowledge the queued request before WinRT performs uncached GATT
        // discovery. Holding Flutter's native reply callback across that
        // multi-second operation can invalidate the response envelope. Calls
        // made after connect remain ordered on this same BLE worker.
        result->Success();
        try {
          Connect(args);
        } catch (...) {
          const std::string device_id =
              GetStringArg(args, "deviceId").value_or("");
          SendConnectionStateEvent(device_id, "disconnected", -1);
        }
      } else if (method == "disconnect") {
        Disconnect(args);
        result->Success();
      } else if (method == "getConnectionState") {
        result->Success(EncodableValue(GetConnectionState(args)));
      } else if (method == "discoverServices") {
        result->Success(EncodableValue(DiscoverServices(args)));
      } else if (method == "readCharacteristic") {
        result->Success(ByteValue(ReadCharacteristic(args)));
      } else if (method == "writeCharacteristic") {
        WriteCharacteristic(args);
        result->Success();
      } else if (method == "setCharacteristicNotification") {
        SetCharacteristicNotification(args);
        result->Success();
      } else if (method == "readDescriptor") {
        result->Success(ByteValue(ReadDescriptor(args)));
      } else if (method == "writeDescriptor") {
        WriteDescriptor(args);
        result->Success();
      } else if (method == "readRssi") {
        result->Success(EncodableValue(ReadRssi(args)));
      } else if (method == "requestMtu") {
        result->Success(EncodableValue(RequestMtu(args)));
      } else if (method == "getMaximumWriteLength") {
        result->Success(EncodableValue(0));
      } else if (method == "setPreferredPhy") {
        result->Success();
      } else if (method == "readPhy") {
        result->Success(EncodableValue(ReadPhy(args)));
      } else if (method == "requestConnectionPriority") {
        result->Success(EncodableValue(false));
      } else if (method == "createBond" || method == "removeBond") {
        result->Success(EncodableValue(false));
      } else if (method == "isPeripheralSupported") {
        result->Success(EncodableValue(true));
      } else if (method == "startAdvertising") {
        StartAdvertising(args);
        result->Success();
      } else if (method == "stopAdvertising") {
        StopAdvertising();
        result->Success();
      } else if (method == "setGattServerServices") {
        SetGattServerServices(args);
        result->Success();
      } else if (method == "clearGattServerServices") {
        ClearGattServer();
        result->Success();
      } else if (method == "updateLocalCharacteristicValue") {
        local_characteristic_value_ = GetByteListArg(args, "value");
        result->Success();
      } else if (method == "notifyGattServerCharacteristic") {
        result->Success(EncodableValue(NotifyGattServer(args)));
      } else if (method == "connectClassic" || method == "startClassicServer" ||
                 method == "writeClassic") {
        result->Error(kUnsupportedCode,
                      "Classic Bluetooth RFCOMM is not implemented on Windows.");
      } else if (method == "stopClassicServer" || method == "disconnectClassic") {
        result->Success();
      } else {
        result->NotImplemented();
      }
    } catch (const std::invalid_argument& error) {
      result->Error(kInvalidArgumentsCode,
                    AsciiErrorMessage(error.what()));
    } catch (const winrt::hresult_error& error) {
      result->Error(kOperationFailedCode,
                    AsciiErrorMessage(winrt::to_string(error.message())));
    } catch (const std::exception& error) {
      result->Error(kOperationFailedCode,
                    AsciiErrorMessage(error.what()));
    }
  }

  void WorkerLoop() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    for (;;) {
      std::function<void()> task;
      {
        std::unique_lock<std::mutex> lock(worker_mutex_);
        worker_cv_.wait(lock, [this]() {
          return worker_stopping_ || !worker_tasks_.empty();
        });
        if (worker_stopping_ && worker_tasks_.empty()) {
          break;
        }
        task = std::move(worker_tasks_.front());
        worker_tasks_.pop_front();
      }

      try {
        task();
      } catch (...) {
      }
    }
    winrt::uninit_apartment();
  }

  bool PostWorkerTask(std::function<void()> task) {
    {
      std::lock_guard<std::mutex> lock(worker_mutex_);
      if (worker_stopping_) {
        return false;
      }
      worker_tasks_.push_back(std::move(task));
    }
    worker_cv_.notify_one();
    return true;
  }

  void RunOnWorkerSync(std::function<void()> task) {
    if (worker_thread_.joinable() &&
        std::this_thread::get_id() == worker_thread_.get_id()) {
      task();
      return;
    }

    std::promise<void> completed;
    auto completed_future = completed.get_future();
    std::exception_ptr exception;
    if (!PostWorkerTask([&task, &completed, &exception]() {
          try {
            task();
          } catch (...) {
            exception = std::current_exception();
          }
          completed.set_value();
        })) {
      throw std::runtime_error("Bluetooth worker is stopping.");
    }

    completed_future.wait();
    if (exception) {
      std::rethrow_exception(exception);
    }
  }

  void StopWorker() {
    {
      std::lock_guard<std::mutex> lock(worker_mutex_);
      worker_stopping_ = true;
    }
    worker_cv_.notify_one();
    if (worker_thread_.joinable() &&
        std::this_thread::get_id() != worker_thread_.get_id()) {
      worker_thread_.join();
    }
  }

  std::string GetPlatformVersion() const {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    } else {
      version_stream << "Unknown";
    }
    return version_stream.str();
  }

  BluetoothAdapter DefaultAdapter() const {
    return BluetoothAdapter::GetDefaultAsync().get();
  }

  Radio AdapterRadio(const BluetoothAdapter& adapter) const {
    if (!adapter) {
      return nullptr;
    }
    try {
      return adapter.GetRadioAsync().get();
    } catch (...) {
      return nullptr;
    }
  }

  bool IsSupported() const {
    BluetoothAdapter adapter = DefaultAdapter();
    return adapter && adapter.IsLowEnergySupported();
  }

  std::string CurrentAdapterStateString() const {
    BluetoothAdapter adapter = DefaultAdapter();
    if (!adapter || !adapter.IsLowEnergySupported()) {
      return "unsupported";
    }
    Radio radio = AdapterRadio(adapter);
    if (!radio) {
      return "unknown";
    }
    return AdapterStateString(radio.State());
  }

  EncodableMap AdapterInfoMap() const {
    BluetoothAdapter adapter = DefaultAdapter();
    const bool supported = adapter && adapter.IsLowEnergySupported();
    EncodableMap map;
    Put(map, "isSupported", EncodableValue(supported));
    Put(map, "state", StringValue(CurrentAdapterStateString()));
    Put(map, "name", NullValue());
    if (adapter && adapter.BluetoothAddress() != 0) {
      Put(map, "address",
          StringValue(FormatBluetoothAddressDisplay(adapter.BluetoothAddress())));
    }
    Put(map, "isBleSupported", EncodableValue(supported));
    Put(map, "isMultipleAdvertisementSupported", EncodableValue(false));
    Put(map, "isOffloadedFilteringSupported", EncodableValue(false));
    Put(map, "isOffloadedScanBatchingSupported", EncodableValue(false));
    Put(map, "isLe2MPhySupported", EncodableValue(false));
    Put(map, "isLeCodedPhySupported", EncodableValue(false));
    Put(map, "isLeExtendedAdvertisingSupported", EncodableValue(false));
    Put(map, "isLePeriodicAdvertisingSupported", EncodableValue(false));
    Put(map, "isDiscovering", EncodableValue(IsScanning()));

    EncodableMap raw = RawWindowsMap();
    if (adapter) {
      Put(raw, "deviceId", StringValue(HStringToString(adapter.DeviceId())));
      Put(raw, "bluetoothAddress",
          StringValue(FormatBluetoothAddress(adapter.BluetoothAddress())));
      Put(raw, "isCentralRoleSupported",
          EncodableValue(adapter.IsCentralRoleSupported()));
      Put(raw, "isPeripheralRoleSupported",
          EncodableValue(adapter.IsPeripheralRoleSupported()));
    }
    Put(map, "raw", EncodableValue(std::move(raw)));
    return map;
  }

  bool IsScanning() const {
    return watcher_ && watcher_.Status() == BluetoothLEAdvertisementWatcherStatus::Started;
  }

  EncodableMap PermissionMap() const {
    EncodableMap map;
    Put(map, "bluetooth", StringValue(IsSupported() ? "granted" : "notApplicable"));
    return map;
  }

  void OpenBluetoothSettings() const {
    ShellExecuteW(nullptr, L"open", L"ms-settings:bluetooth", nullptr, nullptr,
                  SW_SHOWNORMAL);
  }

  void StartScan(const EncodableMap* args,
                 flutter::MethodResult<EncodableValue>* result) {
    const std::string scan_mode = GetStringArg(args, "scanMode").value_or("ble");
    if (scan_mode == "classic") {
      result->Error(kUnsupportedCode,
                    "Windows implementation currently supports BLE scanning only.");
      return;
    }
    if (CurrentAdapterStateString() != "poweredOn") {
      result->Error(kBluetoothUnavailableCode,
                    "Bluetooth is not powered on or unavailable.");
      return;
    }

    StopScanInternal();
    {
      std::lock_guard<std::mutex> lock(scan_mutex_);
      allow_duplicates_ = GetBoolArg(args, "allowDuplicates", false);
      seen_scan_devices_.clear();
    }

    BluetoothLEAdvertisementWatcher watcher;
    watcher.ScanningMode(BluetoothLEScanningMode::Active);
    // Do not install a native 128-bit service filter here. Some Windows BLE
    // stacks omit active-scan responses when that filter is present, hiding
    // otherwise valid connectable peers. Scan results still expose UUIDs and
    // the Dart mesh layer performs the requested Sejilo/name validation.

    received_token_ = watcher.Received(
        [weak_self = weak_from_this()](const BluetoothLEAdvertisementWatcher&,
                                       const BluetoothLEAdvertisementReceivedEventArgs& args) {
          if (auto self = weak_self.lock()) {
            self->OnAdvertisementReceived(args);
          }
        });
    stopped_token_ = watcher.Stopped(
        [weak_self = weak_from_this()](const BluetoothLEAdvertisementWatcher&,
                                       const BluetoothLEAdvertisementWatcherStoppedEventArgs&) {
          if (auto self = weak_self.lock()) {
            self->PostWorkerTask([weak_self]() {
              if (auto self = weak_self.lock()) {
                self->SendAdapterStateEvent();
              }
            });
          }
        });

    watcher_ = watcher;
    watcher_.Start();
    // Some Windows 11 Bluetooth stacks register a nearby GATT device with the
    // system but do not forward its advertisements to
    // BluetoothLEAdvertisementWatcher. Enumerate known BLE endpoints as a
    // bounded fallback so callers can still connect to a requested service.
    const auto requested_service_uuids =
        GetStringListArg(args, "serviceUuids");
    std::thread(
        [weak_self = weak_from_this(), requested_service_uuids]() {
          winrt::init_apartment(winrt::apartment_type::multi_threaded);
          if (auto self = weak_self.lock()) {
            self->EmitKnownBleDevices(requested_service_uuids);
          }
          winrt::uninit_apartment();
        })
        .detach();
    const int generation = ++scan_generation_;

    if (auto timeout_ms = GetIntArg(args, "timeoutMs"); timeout_ms && *timeout_ms > 0) {
      std::weak_ptr<Impl> weak_self = weak_from_this();
      std::thread([weak_self, generation, timeout = *timeout_ms]() {
        std::this_thread::sleep_for(std::chrono::milliseconds(timeout));
        if (auto self = weak_self.lock()) {
          self->PostWorkerTask([weak_self, generation]() {
            if (auto self = weak_self.lock()) {
              self->StopScanIfGeneration(generation);
            }
          });
        }
      }).detach();
    }

    result->Success();
  }

  void EmitKnownBleDevices(const std::vector<std::string>& service_uuids) {
    try {
      auto infos = DeviceInformation::FindAllAsync(
          BluetoothLEDevice::GetDeviceSelector()).get();
      for (const auto& info : infos) {
        try {
          BluetoothLEDevice device =
              BluetoothLEDevice::FromIdAsync(info.Id()).get();
          if (!device ||
              (!service_uuids.empty() &&
               !HasAnyService(device, service_uuids))) {
            continue;
          }
          const std::string device_id = RememberDevice(device);
          {
            std::lock_guard<std::mutex> lock(scan_mutex_);
            if (!allow_duplicates_ && seen_scan_devices_.count(device_id) > 0) {
              continue;
            }
            seen_scan_devices_.insert(device_id);
          }

          EncodableMap scan_result;
          Put(scan_result, "device",
              EncodableValue(DeviceMapFromDevice(device)));
          Put(scan_result, "rssi", EncodableValue(static_cast<int32_t>(-127)));
          const std::string name = HStringToString(device.Name());
          Put(scan_result, "localName",
              name.empty() ? NullValue() : StringValue(name));
          Put(scan_result, "serviceUuids", StringListValue(service_uuids));
          Put(scan_result, "manufacturerData", EncodableValue(EncodableMap{}));
          Put(scan_result, "serviceData", EncodableValue(EncodableMap{}));
          Put(scan_result, "raw", EncodableValue(RawWindowsMap()));
          Put(scan_result, "type", StringValue("scanResult"));
          SendEvent(std::move(scan_result));
        } catch (...) {
          // One inaccessible/stale endpoint must not fail the whole scan.
        }
      }
    } catch (...) {
      // AdvertisementWatcher remains active if endpoint enumeration is denied.
    }
  }

  void StopScanIfGeneration(int generation) {
    if (scan_generation_.load() != generation) {
      return;
    }
    StopScanInternal();
  }

  void StopScanInternal() {
    ++scan_generation_;
    if (watcher_) {
      try {
        if (watcher_.Status() == BluetoothLEAdvertisementWatcherStatus::Started) {
          watcher_.Stop();
        }
        if (received_token_.value != 0) {
          watcher_.Received(received_token_);
          received_token_ = {};
        }
        if (stopped_token_.value != 0) {
          watcher_.Stopped(stopped_token_);
          stopped_token_ = {};
        }
      } catch (...) {
      }
      watcher_ = nullptr;
    }
  }

  void OnAdvertisementReceived(
      const BluetoothLEAdvertisementReceivedEventArgs& args) {
    const uint64_t address = args.BluetoothAddress();
    const std::string device_id = FormatBluetoothAddress(address);
    {
      std::lock_guard<std::mutex> lock(scan_mutex_);
      if (!allow_duplicates_ && seen_scan_devices_.count(device_id) > 0) {
        return;
      }
      seen_scan_devices_.insert(device_id);
      last_rssi_[device_id] = args.RawSignalStrengthInDBm();
    }

    EncodableMap scan_result;
    EncodableMap device_map;
    const std::string local_name = HStringToString(args.Advertisement().LocalName());
    Put(device_map, "id", StringValue(device_id));
    Put(device_map, "name",
        local_name.empty() ? NullValue() : StringValue(local_name));
    Put(device_map, "address", StringValue(FormatBluetoothAddressDisplay(address)));
    Put(device_map, "type", StringValue("ble"));
    Put(device_map, "isConnected", EncodableValue(false));
    Put(device_map, "isBonded", EncodableValue(false));
    Put(device_map, "raw", EncodableValue(RawWindowsMap()));
    Put(scan_result, "device", EncodableValue(std::move(device_map)));

    Put(scan_result, "rssi",
        EncodableValue(static_cast<int32_t>(args.RawSignalStrengthInDBm())));
    Put(scan_result, "localName", local_name.empty() ? NullValue() : StringValue(local_name));

    std::vector<std::string> service_uuids;
    for (const auto& uuid : args.Advertisement().ServiceUuids()) {
      service_uuids.push_back(GuidToString(uuid));
    }
    Put(scan_result, "serviceUuids", StringListValue(service_uuids));

    EncodableMap manufacturer_data;
    for (const auto& item : args.Advertisement().ManufacturerData()) {
      manufacturer_data[EncodableValue(std::to_string(item.CompanyId()))] =
          ByteValue(BufferToBytes(item.Data()));
    }
    Put(scan_result, "manufacturerData", EncodableValue(std::move(manufacturer_data)));
    Put(scan_result, "serviceData", EncodableValue(ExtractServiceData(args)));
    Put(scan_result, "raw", EncodableValue(RawWindowsMap()));

    Put(scan_result, "type", StringValue("scanResult"));
    SendEvent(std::move(scan_result));
  }

  EncodableMap ExtractServiceData(
      const BluetoothLEAdvertisementReceivedEventArgs& args) const {
    EncodableMap service_data;
    for (const BluetoothLEAdvertisementDataSection& section :
         args.Advertisement().DataSections()) {
      const uint8_t data_type = section.DataType();
      if (data_type != 0x16 && data_type != 0x20 && data_type != 0x21) {
        continue;
      }
      std::vector<uint8_t> bytes = BufferToBytes(section.Data());
      if (bytes.empty()) {
        continue;
      }
      std::string key;
      size_t uuid_length = 0;
      if (data_type == 0x16 && bytes.size() >= 2) {
        std::ostringstream stream;
        stream << std::hex << std::setfill('0') << std::setw(4)
               << (static_cast<int>(bytes[1]) << 8 | static_cast<int>(bytes[0]));
        key = stream.str();
        uuid_length = 2;
      } else if (data_type == 0x20 && bytes.size() >= 4) {
        std::ostringstream stream;
        for (int index = 3; index >= 0; --index) {
          stream << std::hex << std::setfill('0') << std::setw(2)
                 << static_cast<int>(bytes[index]);
        }
        key = stream.str();
        uuid_length = 4;
      } else if (data_type == 0x21 && bytes.size() >= 16) {
        GUID guid = {};
        std::memcpy(&guid, bytes.data(), 16);
        winrt::guid winrt_guid = {};
        std::memcpy(&winrt_guid, &guid, sizeof(winrt_guid));
        key = GuidToString(winrt_guid);
        uuid_length = 16;
      }
      if (!key.empty()) {
        std::vector<uint8_t> value(bytes.begin() + uuid_length, bytes.end());
        service_data[EncodableValue(key)] = ByteValue(value);
      }
    }
    return service_data;
  }

  EncodableList GetBondedDevices() {
    EncodableList devices;
    try {
      auto selector = BluetoothLEDevice::GetDeviceSelectorFromPairingState(true);
      auto infos = DeviceInformation::FindAllAsync(selector).get();
      for (const auto& info : infos) {
        try {
          BluetoothLEDevice device = BluetoothLEDevice::FromIdAsync(info.Id()).get();
          if (device) {
            RememberDevice(device);
            devices.emplace_back(DeviceMapFromDevice(device));
          } else {
            devices.emplace_back(DeviceMapFromDeviceInformation(info));
          }
        } catch (...) {
          devices.emplace_back(DeviceMapFromDeviceInformation(info));
        }
      }
    } catch (...) {
      // Pairing enumeration can be unavailable on older Windows configurations.
    }
    return devices;
  }

  EncodableList GetConnectedDevices(const EncodableMap* args) {
    EncodableList devices;
    const std::vector<std::string> service_uuids =
        GetStringListArg(args, "serviceUuids");

    std::lock_guard<std::mutex> lock(device_mutex_);
    for (const auto& entry : devices_) {
      const BluetoothLEDevice& device = entry.second;
      if (!device || device.ConnectionStatus() != BluetoothConnectionStatus::Connected) {
        continue;
      }
      if (!service_uuids.empty() && !HasAnyService(device, service_uuids)) {
        continue;
      }
      devices.emplace_back(DeviceMapFromDevice(device));
    }
    return devices;
  }

  void GetDevice(const EncodableMap* args,
                 flutter::MethodResult<EncodableValue>* result) {
    const std::string device_id = GetRequiredStringArg(args, "deviceId");
    BluetoothLEDevice device = ResolveDevice(device_id, true);
    if (!device) {
      result->Success(EncodableValue(EncodableMap{}));
      return;
    }
    result->Success(EncodableValue(DeviceMapFromDevice(device)));
  }

  EncodableList GetDevices(const EncodableMap* args) {
    EncodableList devices;
    const EncodableValue* device_ids_value = FindArg(args, "deviceIds");
    const auto* device_ids = device_ids_value
                                 ? std::get_if<EncodableList>(device_ids_value)
                                 : nullptr;
    if (!device_ids) {
      return devices;
    }

    for (const auto& item : *device_ids) {
      const auto* id = std::get_if<std::string>(&item);
      if (!id) {
        continue;
      }
      BluetoothLEDevice device = ResolveDevice(*id, true);
      if (device) {
        devices.emplace_back(DeviceMapFromDevice(device));
      }
    }
    return devices;
  }

  void Connect(const EncodableMap* args) {
    const std::string device_id = GetRequiredStringArg(args, "deviceId");
    BluetoothLEDevice device = ResolveDevice(device_id, true);
    if (!device) {
      throw std::runtime_error("Device not found: " + device_id);
    }

    SendConnectionStateEvent(DeviceKey(device), "connecting", std::nullopt);
    GattDeviceServicesResult services_result =
        device.GetGattServicesAsync(BluetoothCacheMode::Uncached).get();
    if (services_result.Status() != GattCommunicationStatus::Success ||
        services_result.Services().Size() == 0) {
      services_result =
          device.GetGattServicesAsync(BluetoothCacheMode::Cached).get();
    }
    if (services_result.Status() != GattCommunicationStatus::Success) {
      SendConnectionStateEvent(DeviceKey(device), "disconnected", std::nullopt);
      throw std::runtime_error(GattStatusMessage(services_result.Status()));
    }

    {
      std::lock_guard<std::mutex> lock(device_mutex_);
      std::vector<GattDeviceService> cached_services;
      for (const auto& service : services_result.Services()) {
        cached_services.push_back(service);
      }
      service_cache_.insert_or_assign(DeviceKey(device), std::move(cached_services));
      connected_device_keys_.insert(DeviceKey(device));
    }
    SendConnectionStateEvent(DeviceKey(device), "connected", std::nullopt);
  }

  void Disconnect(const EncodableMap* args) {
    const std::string device_id = GetRequiredStringArg(args, "deviceId");
    BluetoothLEDevice device = ResolveDevice(device_id, false);
    if (!device) {
      SendConnectionStateEvent(device_id, "disconnected", std::nullopt);
      return;
    }

    const std::string key = DeviceKey(device);
    {
      std::lock_guard<std::mutex> lock(device_mutex_);
      for (auto it = subscriptions_.begin(); it != subscriptions_.end();) {
        if (it->first.rfind(key + "|", 0) == 0) {
          try {
            it->second.characteristic.ValueChanged(it->second.token);
          } catch (...) {
          }
          it = subscriptions_.erase(it);
        } else {
          ++it;
        }
      }
      service_cache_.erase(key);
      characteristic_cache_.clear();
      descriptor_cache_.clear();
      auto token = connection_tokens_.find(key);
      if (token != connection_tokens_.end()) {
        try {
          device.ConnectionStatusChanged(token->second);
        } catch (...) {
        }
        connection_tokens_.erase(token);
      }
      devices_.erase(key);
      connected_device_keys_.erase(key);
      last_rssi_.erase(key);
    }
    SendConnectionStateEvent(key, "disconnected", std::nullopt);
  }

  std::string GetConnectionState(const EncodableMap* args) {
    const std::string device_id = GetRequiredStringArg(args, "deviceId");
    BluetoothLEDevice device = ResolveDevice(device_id, false);
    if (!device) {
      return "disconnected";
    }
    return ConnectionStateString(device.ConnectionStatus());
  }

  EncodableList DiscoverServices(const EncodableMap* args) {
    BluetoothLEDevice device = ResolveRequiredDevice(args);
    const std::string key = DeviceKey(device);
    GattDeviceServicesResult services_result =
        device.GetGattServicesAsync(BluetoothCacheMode::Uncached).get();
    if (services_result.Status() != GattCommunicationStatus::Success ||
        services_result.Services().Size() == 0) {
      services_result =
          device.GetGattServicesAsync(BluetoothCacheMode::Cached).get();
    }
    if (services_result.Status() != GattCommunicationStatus::Success) {
      throw std::runtime_error(GattStatusMessage(services_result.Status()));
    }

    EncodableList services;
    std::vector<GattDeviceService> cache;
    for (const auto& service : services_result.Services()) {
      cache.push_back(service);
      services.emplace_back(ServiceMap(service));
    }
    {
      std::lock_guard<std::mutex> lock(device_mutex_);
      service_cache_.insert_or_assign(key, std::move(cache));
    }
    return services;
  }

  std::vector<uint8_t> ReadCharacteristic(const EncodableMap* args) {
    const std::string device_id = GetRequiredStringArg(args, "deviceId");
    const std::string service_uuid = GetRequiredStringArg(args, "serviceUuid");
    const std::string characteristic_uuid =
        GetRequiredStringArg(args, "characteristicUuid");
    GattCharacteristic characteristic =
        ResolveCharacteristic(device_id, service_uuid, characteristic_uuid);

    GattReadResult read_result = characteristic.ReadValueAsync().get();
    if (read_result.Status() != GattCommunicationStatus::Success) {
      throw std::runtime_error(GattStatusMessage(read_result.Status()));
    }
    std::vector<uint8_t> bytes = BufferToBytes(read_result.Value());
    SendCharacteristicValueEvent(device_id, service_uuid, characteristic_uuid,
                                 bytes);
    return bytes;
  }

  void WriteCharacteristic(const EncodableMap* args) {
    const std::string device_id = GetRequiredStringArg(args, "deviceId");
    const std::string service_uuid = GetRequiredStringArg(args, "serviceUuid");
    const std::string characteristic_uuid =
        GetRequiredStringArg(args, "characteristicUuid");
    const std::vector<uint8_t> value = GetByteListArg(args, "value");
    const std::string write_type =
        GetStringArg(args, "writeType").value_or("withResponse");
    GattCharacteristic characteristic =
        ResolveCharacteristic(device_id, service_uuid, characteristic_uuid);

    const GattWriteOption option = write_type == "withoutResponse"
                                      ? GattWriteOption::WriteWithoutResponse
                                      : GattWriteOption::WriteWithResponse;
    GattCommunicationStatus status =
        characteristic.WriteValueAsync(BytesToBuffer(value), option).get();
    if (status != GattCommunicationStatus::Success) {
      throw std::runtime_error(GattStatusMessage(status));
    }
  }

  void SetCharacteristicNotification(const EncodableMap* args) {
    const std::string device_id = GetRequiredStringArg(args, "deviceId");
    const std::string service_uuid = GetRequiredStringArg(args, "serviceUuid");
    const std::string characteristic_uuid =
        GetRequiredStringArg(args, "characteristicUuid");
    const bool enable = GetBoolArg(args, "enable", false);
    GattCharacteristic characteristic =
        ResolveCharacteristic(device_id, service_uuid, characteristic_uuid);
    const std::string key = CharacteristicKey(device_id, service_uuid,
                                              characteristic_uuid);

    {
      std::lock_guard<std::mutex> lock(device_mutex_);
      auto existing = subscriptions_.find(key);
      if (existing != subscriptions_.end()) {
        try {
          existing->second.characteristic.ValueChanged(existing->second.token);
        } catch (...) {
        }
        subscriptions_.erase(existing);
      }
    }

    if (!enable) {
      characteristic.WriteClientCharacteristicConfigurationDescriptorAsync(
          GattClientCharacteristicConfigurationDescriptorValue::None).get();
      return;
    }

    const auto properties = characteristic.CharacteristicProperties();
    GattClientCharacteristicConfigurationDescriptorValue descriptor_value =
        HasProperty(properties, GattCharacteristicProperties::Notify)
            ? GattClientCharacteristicConfigurationDescriptorValue::Notify
            : GattClientCharacteristicConfigurationDescriptorValue::Indicate;

    auto token = characteristic.ValueChanged(
        [weak_self = weak_from_this(), device_id, service_uuid,
         characteristic_uuid](const GattCharacteristic&,
                              const winrt::Windows::Devices::Bluetooth::
                                  GenericAttributeProfile::
                                      GattValueChangedEventArgs& event_args) {
          if (auto self = weak_self.lock()) {
            self->SendCharacteristicValueEvent(
                device_id, service_uuid, characteristic_uuid,
                BufferToBytes(event_args.CharacteristicValue()));
          }
        });

    GattCommunicationStatus status =
        characteristic.WriteClientCharacteristicConfigurationDescriptorAsync(
            descriptor_value)
            .get();
    if (status != GattCommunicationStatus::Success) {
      characteristic.ValueChanged(token);
      throw std::runtime_error(GattStatusMessage(status));
    }

    std::lock_guard<std::mutex> lock(device_mutex_);
    subscriptions_.insert_or_assign(key, CharacteristicSubscription{characteristic, token});
  }

  std::vector<uint8_t> ReadDescriptor(const EncodableMap* args) {
    const std::string device_id = GetRequiredStringArg(args, "deviceId");
    const std::string service_uuid = GetRequiredStringArg(args, "serviceUuid");
    const std::string characteristic_uuid =
        GetRequiredStringArg(args, "characteristicUuid");
    const std::string descriptor_uuid = GetRequiredStringArg(args, "descriptorUuid");
    GattDescriptor descriptor =
        ResolveDescriptor(device_id, service_uuid, characteristic_uuid,
                          descriptor_uuid);

    GattReadResult read_result = descriptor.ReadValueAsync().get();
    if (read_result.Status() != GattCommunicationStatus::Success) {
      throw std::runtime_error(GattStatusMessage(read_result.Status()));
    }
    std::vector<uint8_t> bytes = BufferToBytes(read_result.Value());
    SendDescriptorValueEvent(device_id, service_uuid, characteristic_uuid,
                             descriptor_uuid, bytes);
    return bytes;
  }

  void WriteDescriptor(const EncodableMap* args) {
    const std::string device_id = GetRequiredStringArg(args, "deviceId");
    const std::string service_uuid = GetRequiredStringArg(args, "serviceUuid");
    const std::string characteristic_uuid =
        GetRequiredStringArg(args, "characteristicUuid");
    const std::string descriptor_uuid = GetRequiredStringArg(args, "descriptorUuid");
    const std::vector<uint8_t> value = GetByteListArg(args, "value");
    GattDescriptor descriptor =
        ResolveDescriptor(device_id, service_uuid, characteristic_uuid,
                          descriptor_uuid);

    GattCommunicationStatus status = descriptor.WriteValueAsync(BytesToBuffer(value)).get();
    if (status != GattCommunicationStatus::Success) {
      throw std::runtime_error(GattStatusMessage(status));
    }
    SendDescriptorValueEvent(device_id, service_uuid, characteristic_uuid,
                             descriptor_uuid, value);
  }

  int32_t ReadRssi(const EncodableMap* args) {
    const std::string device_id = GetRequiredStringArg(args, "deviceId");
    int32_t rssi = 0;
    {
      std::lock_guard<std::mutex> lock(scan_mutex_);
      auto it = last_rssi_.find(device_id);
      if (it == last_rssi_.end()) {
        if (auto address = ParseBluetoothAddress(device_id)) {
          it = last_rssi_.find(FormatBluetoothAddress(*address));
        }
      }
      if (it != last_rssi_.end()) {
        rssi = it->second;
      }
    }
    EncodableMap event;
    Put(event, "type", StringValue("rssi"));
    Put(event, "deviceId", StringValue(device_id));
    Put(event, "rssi", EncodableValue(rssi));
    SendEvent(std::move(event));
    return rssi;
  }

  int32_t RequestMtu(const EncodableMap* args) {
    const std::string device_id = GetRequiredStringArg(args, "deviceId");
    EncodableMap event;
    Put(event, "type", StringValue("mtu"));
    Put(event, "deviceId", StringValue(device_id));
    Put(event, "mtu", EncodableValue(0));
    SendEvent(std::move(event));
    return 0;
  }

  EncodableMap ReadPhy(const EncodableMap* args) {
    EncodableMap map;
    Put(map, "deviceId", StringValue(GetStringArg(args, "deviceId").value_or("")));
    Put(map, "txPhy", StringValue("unknown"));
    Put(map, "rxPhy", StringValue("unknown"));
    return map;
  }

  BluetoothLEDevice ResolveRequiredDevice(const EncodableMap* args) {
    const std::string device_id = GetRequiredStringArg(args, "deviceId");
    BluetoothLEDevice device = ResolveDevice(device_id, true);
    if (!device) {
      throw std::runtime_error("Device not found: " + device_id);
    }
    return device;
  }

  BluetoothLEDevice ResolveDevice(const std::string& device_id,
                                  bool create) {
    {
      std::lock_guard<std::mutex> lock(device_mutex_);
      auto it = devices_.find(device_id);
      if (it != devices_.end()) {
        return it->second;
      }
      auto alias = device_aliases_.find(device_id);
      if (alias != device_aliases_.end()) {
        auto device_it = devices_.find(alias->second);
        if (device_it != devices_.end()) {
          return device_it->second;
        }
      }
    }

    if (!create) {
      return nullptr;
    }

    BluetoothLEDevice device = nullptr;
    if (auto address = ParseBluetoothAddress(device_id)) {
      device = BluetoothLEDevice::FromBluetoothAddressAsync(*address).get();
    }
    if (!device) {
      try {
        device = BluetoothLEDevice::FromIdAsync(winrt::to_hstring(device_id)).get();
      } catch (...) {
        device = nullptr;
      }
    }
    if (device) {
      RememberDevice(device);
    }
    return device;
  }

  GattDeviceService ResolveService(const std::string& device_id,
                                   const std::string& service_uuid) {
    BluetoothLEDevice device = ResolveDevice(device_id, true);
    if (!device) {
      throw std::runtime_error("Device not found: " + device_id);
    }
    auto uuid = ParseGuid(service_uuid);
    if (!uuid) {
      throw std::invalid_argument("Invalid service UUID: " + service_uuid);
    }

    GattDeviceServicesResult result =
        device
            .GetGattServicesForUuidAsync(*uuid, BluetoothCacheMode::Uncached)
            .get();
    if (result.Status() != GattCommunicationStatus::Success ||
        result.Services().Size() == 0) {
      result = device
                   .GetGattServicesForUuidAsync(*uuid,
                                                BluetoothCacheMode::Cached)
                   .get();
    }
    if (result.Status() != GattCommunicationStatus::Success ||
        result.Services().Size() == 0) {
      throw std::runtime_error("GATT service not found: " + service_uuid);
    }
    return result.Services().GetAt(0);
  }

  GattCharacteristic ResolveCharacteristic(
      const std::string& device_id,
      const std::string& service_uuid,
      const std::string& characteristic_uuid) {
    const std::string key =
        CharacteristicKey(device_id, service_uuid, characteristic_uuid);
    {
      std::lock_guard<std::mutex> lock(device_mutex_);
      auto it = characteristic_cache_.find(key);
      if (it != characteristic_cache_.end()) {
        return it->second;
      }
    }

    auto uuid = ParseGuid(characteristic_uuid);
    if (!uuid) {
      throw std::invalid_argument("Invalid characteristic UUID: " + characteristic_uuid);
    }
    GattDeviceService service = ResolveService(device_id, service_uuid);
    GattCharacteristicsResult result =
        service
            .GetCharacteristicsForUuidAsync(*uuid,
                                            BluetoothCacheMode::Uncached)
            .get();
    if (result.Status() != GattCommunicationStatus::Success ||
        result.Characteristics().Size() == 0) {
      result = service
                   .GetCharacteristicsForUuidAsync(*uuid,
                                                   BluetoothCacheMode::Cached)
                   .get();
    }
    if (result.Status() != GattCommunicationStatus::Success ||
        result.Characteristics().Size() == 0) {
      throw std::runtime_error("GATT characteristic not found: " + characteristic_uuid);
    }
    GattCharacteristic characteristic = result.Characteristics().GetAt(0);
    {
      std::lock_guard<std::mutex> lock(device_mutex_);
      characteristic_cache_.insert_or_assign(key, characteristic);
    }
    return characteristic;
  }

  GattDescriptor ResolveDescriptor(const std::string& device_id,
                                   const std::string& service_uuid,
                                   const std::string& characteristic_uuid,
                                   const std::string& descriptor_uuid) {
    const std::string key = device_id + "|" + service_uuid + "|" +
                            characteristic_uuid + "|" + descriptor_uuid;
    {
      std::lock_guard<std::mutex> lock(device_mutex_);
      auto it = descriptor_cache_.find(key);
      if (it != descriptor_cache_.end()) {
        return it->second;
      }
    }

    auto uuid = ParseGuid(descriptor_uuid);
    if (!uuid) {
      throw std::invalid_argument("Invalid descriptor UUID: " + descriptor_uuid);
    }
    GattCharacteristic characteristic =
        ResolveCharacteristic(device_id, service_uuid, characteristic_uuid);
    GattDescriptorsResult result = characteristic.GetDescriptorsForUuidAsync(*uuid).get();
    if (result.Status() != GattCommunicationStatus::Success ||
        result.Descriptors().Size() == 0) {
      throw std::runtime_error("GATT descriptor not found: " + descriptor_uuid);
    }
    GattDescriptor descriptor = result.Descriptors().GetAt(0);
    {
      std::lock_guard<std::mutex> lock(device_mutex_);
      descriptor_cache_.insert_or_assign(key, descriptor);
    }
    return descriptor;
  }

  bool HasAnyService(const BluetoothLEDevice& device,
                     const std::vector<std::string>& service_uuids) {
    for (const auto& service_uuid : service_uuids) {
      auto uuid = ParseGuid(service_uuid);
      if (!uuid) {
        continue;
      }
      try {
        // Candidate enumeration intentionally uses the Windows cache. Some
        // stacks suppress advertisements and reject uncached UUID probing
        // until a GATT session is opened. Connect/discover below always uses
        // uncached reads before exposing the actual service tree.
        GattDeviceServicesResult result =
            device.GetGattServicesForUuidAsync(*uuid).get();
        if (result.Status() == GattCommunicationStatus::Success &&
            result.Services().Size() > 0) {
          return true;
        }
      } catch (...) {
      }
    }
    return false;
  }

  std::string RememberDevice(const BluetoothLEDevice& device) {
    const std::string key = DeviceKey(device);
    std::lock_guard<std::mutex> lock(device_mutex_);
    devices_.insert_or_assign(key, device);
    device_aliases_[HStringToString(device.DeviceId())] = key;
    if (device.BluetoothAddress() != 0) {
      device_aliases_[FormatBluetoothAddress(device.BluetoothAddress())] = key;
      device_aliases_[FormatBluetoothAddressDisplay(device.BluetoothAddress())] = key;
    }

    if (connection_tokens_.find(key) == connection_tokens_.end()) {
      connection_tokens_[key] = device.ConnectionStatusChanged(
          [weak_self = weak_from_this()](const BluetoothLEDevice& sender,
                                         const IInspectable&) {
            if (auto self = weak_self.lock()) {
              const std::string device_key = self->DeviceKey(sender);
              const bool is_connected =
                  sender.ConnectionStatus() == BluetoothConnectionStatus::Connected;
              bool should_report = false;
              {
                std::lock_guard<std::mutex> lock(self->device_mutex_);
                if (is_connected) {
                  self->connected_device_keys_.insert(device_key);
                  should_report = true;
                } else {
                  should_report = self->connected_device_keys_.erase(device_key) > 0;
                }
              }
              if (should_report) {
                self->SendConnectionStateEvent(
                    device_key,
                    is_connected ? "connected" : "disconnected",
                    std::nullopt);
              }
            }
          });
    }
    return key;
  }

  std::string DeviceKey(const BluetoothLEDevice& device) const {
    if (!device) {
      return {};
    }
    return device.BluetoothAddress() == 0 ? HStringToString(device.DeviceId())
                                          : FormatBluetoothAddress(device.BluetoothAddress());
  }

  std::string CharacteristicKey(const std::string& device_id,
                                const std::string& service_uuid,
                                const std::string& characteristic_uuid) const {
    return device_id + "|" + ToLower(service_uuid) + "|" +
           ToLower(characteristic_uuid);
  }

  void SetGattServerServices(const EncodableMap* args) {
    ClearGattServer();
    const EncodableValue* services_value = FindArg(args, "services");
    const auto* services = services_value
                               ? std::get_if<EncodableList>(services_value)
                               : nullptr;
    if (!services || services->empty()) {
      throw std::invalid_argument("At least one local GATT service is required.");
    }
    const auto* service = std::get_if<EncodableMap>(&services->front());
    if (!service) {
      throw std::invalid_argument("Invalid local GATT service definition.");
    }
    const std::string service_uuid = GetRequiredStringArg(service, "uuid");
    const EncodableValue* characteristics_value =
        FindArg(service, "characteristics");
    const auto* characteristics = characteristics_value
                                      ? std::get_if<EncodableList>(
                                            characteristics_value)
                                      : nullptr;
    if (!characteristics || characteristics->empty()) {
      throw std::invalid_argument("A local GATT characteristic is required.");
    }
    const auto* characteristic =
        std::get_if<EncodableMap>(&characteristics->front());
    if (!characteristic) {
      throw std::invalid_argument("Invalid local GATT characteristic definition.");
    }
    const std::string characteristic_uuid =
        GetRequiredStringArg(characteristic, "uuid");
    auto service_guid = ParseGuid(service_uuid);
    auto characteristic_guid = ParseGuid(characteristic_uuid);
    if (!service_guid || !characteristic_guid) {
      throw std::invalid_argument("Local GATT UUID is invalid.");
    }

    using namespace winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;
    // Keep enough state to publish a discoverable fallback advertisement when
    // Windows cannot host a GATT service on this adapter.  Many laptop radios
    // can scan as a central but reject GATT-provider creation.
    local_service_uuid_ = ToLower(service_uuid);
    local_characteristic_uuid_ = ToLower(characteristic_uuid);
    auto provider_result = GattServiceProvider::CreateAsync(*service_guid).get();
    if (provider_result.Error() != BluetoothError::Success) {
      return;
    }
    gatt_provider_ = provider_result.ServiceProvider();

    GattLocalCharacteristicParameters parameters;
    parameters.CharacteristicProperties(
        GattCharacteristicProperties::Read |
        GattCharacteristicProperties::Write |
        GattCharacteristicProperties::WriteWithoutResponse |
        GattCharacteristicProperties::Notify);
    parameters.ReadProtectionLevel(GattProtectionLevel::Plain);
    parameters.WriteProtectionLevel(GattProtectionLevel::Plain);
    auto characteristic_result =
        gatt_provider_.Service()
            .CreateCharacteristicAsync(*characteristic_guid, parameters)
            .get();
    if (characteristic_result.Error() != BluetoothError::Success) {
      gatt_provider_ = nullptr;
      return;
    }
    local_characteristic_ = characteristic_result.Characteristic();
    std::weak_ptr<Impl> weak = weak_from_this();
    write_requested_token_ = local_characteristic_.WriteRequested(
        [weak](const GattLocalCharacteristic&,
               const GattWriteRequestedEventArgs& event_args) {
          if (auto self = weak.lock()) {
            try {
              auto deferral = event_args.GetDeferral();
              auto request = event_args.GetRequestAsync().get();
              if (request) {
                const auto bytes = BufferToBytes(request.Value());
                request.Respond();
                self->SendGattServerRequest("characteristicWrite", bytes);
              }
              deferral.Complete();
            } catch (...) {
            }
          }
        });
    read_requested_token_ = local_characteristic_.ReadRequested(
        [weak](const GattLocalCharacteristic&,
               const GattReadRequestedEventArgs& event_args) {
          if (auto self = weak.lock()) {
            try {
              auto deferral = event_args.GetDeferral();
              auto request = event_args.GetRequestAsync().get();
              if (request) {
                request.RespondWithValue(
                    BytesToBuffer(self->local_characteristic_value_));
              }
              deferral.Complete();
            } catch (...) {
            }
          }
        });
    subscribed_changed_token_ = local_characteristic_.SubscribedClientsChanged(
        [weak](const GattLocalCharacteristic& sender,
               const IInspectable&) {
          if (auto self = weak.lock()) {
            const bool subscribed = sender.SubscribedClients().Size() > 0;
            self->SendGattServerRequest(subscribed ? "subscribed"
                                                   : "unsubscribed",
                                        {});
          }
        });
  }

  void StartAdvertising(const EncodableMap* args) {
    using namespace winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;
    if (gatt_provider_) {
      try {
        GattServiceProviderAdvertisingParameters parameters;
        parameters.IsConnectable(true);
        parameters.IsDiscoverable(true);
        gatt_provider_.StartAdvertising(parameters);
        SendAdvertisingState(true, std::nullopt, "started");
        return;
      } catch (...) {
        // Fall through to a non-connectable service advertisement.  It keeps
        // Windows discoverable and lets it connect back to an Android GATT
        // server, which preserves two-way chat for adapters without hosting.
      }
    }
    auto service_guid = ParseGuid(local_service_uuid_);
    if (!service_guid) {
      throw std::runtime_error("Configure the local GATT service before advertising.");
    }
    BluetoothLEAdvertisementPublisher publisher;
    publisher.Advertisement().ServiceUuids().Append(*service_guid);
    const EncodableValue* data_value = FindArg(args, "advertisementData");
    const auto* data = data_value ? std::get_if<EncodableMap>(data_value) : nullptr;
    if (data) {
      if (const auto local_name = GetStringArg(data, "localName")) {
        publisher.Advertisement().LocalName(winrt::to_hstring(*local_name));
      }
    }
    publisher.Start();
    advertisement_publisher_ = publisher;
    SendAdvertisingState(true, std::nullopt, "started");
  }

  void StopAdvertising() {
    if (advertisement_publisher_) {
      try {
        advertisement_publisher_.Stop();
      } catch (...) {
      }
      advertisement_publisher_ = nullptr;
    }
    if (gatt_provider_) {
      try {
        gatt_provider_.StopAdvertising();
      } catch (...) {
      }
    }
    SendAdvertisingState(false, std::nullopt, "stopped");
  }

  bool NotifyGattServer(const EncodableMap* args) {
    if (!local_characteristic_) {
      return false;
    }
    const auto value = GetByteListArg(args, "value");
    local_characteristic_value_ = value;
    auto results = local_characteristic_.NotifyValueAsync(BytesToBuffer(value)).get();
    return results.Size() > 0;
  }

  void SendGattServerRequest(const std::string& request_event,
                             const std::vector<uint8_t>& value) {
    EncodableMap event;
    Put(event, "type", StringValue("gattServerRequest"));
    Put(event, "event", StringValue(request_event));
    Put(event, "deviceId", StringValue("windows-central"));
    Put(event, "serviceUuid", StringValue(local_service_uuid_));
    Put(event, "characteristicUuid",
        StringValue(local_characteristic_uuid_));
    Put(event, "value", ByteValue(value));
    Put(event, "responseNeeded", EncodableValue(false));
    SendEvent(std::move(event));
  }

  void ClearGattServer() {
    StopAdvertising();
    try {
      if (local_characteristic_) {
        local_characteristic_.WriteRequested(write_requested_token_);
        local_characteristic_.ReadRequested(read_requested_token_);
        local_characteristic_.SubscribedClientsChanged(
            subscribed_changed_token_);
      }
    } catch (...) {
    }
    local_characteristic_ = nullptr;
    gatt_provider_ = nullptr;
    local_characteristic_value_.clear();
    local_service_uuid_.clear();
    local_characteristic_uuid_.clear();
  }

  void SendAdapterStateEvent() {
    EncodableMap event;
    Put(event, "type", StringValue("adapterState"));
    Put(event, "state", StringValue(CurrentAdapterStateString()));
    SendEvent(std::move(event));
  }

  void SendConnectionStateEvent(const std::string& device_id,
                                const std::string& state,
                                std::optional<int32_t> status) {
    EncodableMap event;
    Put(event, "type", StringValue("connectionState"));
    Put(event, "deviceId", StringValue(device_id));
    Put(event, "state", StringValue(state));
    if (status) {
      Put(event, "status", EncodableValue(*status));
    }
    SendEvent(std::move(event));
  }

  void SendCharacteristicValueEvent(const std::string& device_id,
                                    const std::string& service_uuid,
                                    const std::string& characteristic_uuid,
                                    const std::vector<uint8_t>& value) {
    EncodableMap event;
    Put(event, "type", StringValue("characteristicValue"));
    Put(event, "deviceId", StringValue(device_id));
    Put(event, "serviceUuid", StringValue(service_uuid));
    Put(event, "characteristicUuid", StringValue(characteristic_uuid));
    Put(event, "value", ByteValue(value));
    SendEvent(std::move(event));
  }

  void SendDescriptorValueEvent(const std::string& device_id,
                                const std::string& service_uuid,
                                const std::string& characteristic_uuid,
                                const std::string& descriptor_uuid,
                                const std::vector<uint8_t>& value) {
    EncodableMap event;
    Put(event, "type", StringValue("descriptorValue"));
    Put(event, "deviceId", StringValue(device_id));
    Put(event, "serviceUuid", StringValue(service_uuid));
    Put(event, "characteristicUuid", StringValue(characteristic_uuid));
    Put(event, "descriptorUuid", StringValue(descriptor_uuid));
    Put(event, "value", ByteValue(value));
    SendEvent(std::move(event));
  }

  void SendAdvertisingState(bool is_advertising,
                            std::optional<int32_t> error_code,
                            const std::string& message) {
    EncodableMap event;
    Put(event, "type", StringValue("advertisingState"));
    Put(event, "isAdvertising", EncodableValue(is_advertising));
    if (error_code) {
      Put(event, "errorCode", EncodableValue(*error_code));
    }
    Put(event, "message", StringValue(message));
    SendEvent(std::move(event));
  }

  void SendEvent(EncodableMap event) {
    auto weak_self = weak_from_this();
    PostPlatformTask([weak_self, event = std::move(event)]() mutable {
      const auto self = weak_self.lock();
      if (!self) {
        return;
      }
      std::lock_guard<std::mutex> lock(self->event_mutex_);
      if (self->event_sink_) {
        self->event_sink_->Success(EncodableValue(std::move(event)));
      }
    });
  }

  void ClearEventSink() {
    std::lock_guard<std::mutex> lock(event_mutex_);
    event_sink_.reset();
  }

  void CloseDevicesInternal() {
    std::lock_guard<std::mutex> lock(device_mutex_);
    for (auto& entry : subscriptions_) {
      try {
        entry.second.characteristic.ValueChanged(entry.second.token);
      } catch (...) {
      }
    }
    subscriptions_.clear();

    for (const auto& entry : connection_tokens_) {
      auto device = devices_.find(entry.first);
      if (device == devices_.end()) {
        continue;
      }
      try {
        device->second.ConnectionStatusChanged(entry.second);
      } catch (...) {
      }
    }
    connection_tokens_.clear();
    connected_device_keys_.clear();
    service_cache_.clear();
    characteristic_cache_.clear();
    descriptor_cache_.clear();
    devices_.clear();
    device_aliases_.clear();
  }

  struct CharacteristicSubscription {
    GattCharacteristic characteristic{nullptr};
    winrt::event_token token{};
  };

  mutable std::mutex worker_mutex_;
  std::condition_variable worker_cv_;
  std::deque<std::function<void()>> worker_tasks_;
  bool worker_stopping_ = false;
  std::thread worker_thread_;

  std::atomic<HWND> platform_window_{nullptr};
  std::mutex platform_mutex_;
  std::deque<std::function<void()>> platform_tasks_;

  mutable std::mutex event_mutex_;
  std::unique_ptr<flutter::EventSink<EncodableValue>> event_sink_;

  mutable std::mutex scan_mutex_;
  BluetoothLEAdvertisementWatcher watcher_{nullptr};
  winrt::event_token received_token_{};
  winrt::event_token stopped_token_{};
  bool allow_duplicates_ = false;
  std::atomic<int> scan_generation_{0};
  std::unordered_set<std::string> seen_scan_devices_;
  std::unordered_map<std::string, int32_t> last_rssi_;

  mutable std::mutex device_mutex_;
  std::unordered_map<std::string, BluetoothLEDevice> devices_;
  std::unordered_map<std::string, std::string> device_aliases_;
  std::unordered_set<std::string> connected_device_keys_;
  std::unordered_map<std::string, winrt::event_token> connection_tokens_;
  std::unordered_map<std::string, std::vector<GattDeviceService>> service_cache_;
  std::unordered_map<std::string, GattCharacteristic> characteristic_cache_;
  std::unordered_map<std::string, GattDescriptor> descriptor_cache_;
  std::unordered_map<std::string, CharacteristicSubscription> subscriptions_;

  winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattServiceProvider
      gatt_provider_{nullptr};
  BluetoothLEAdvertisementPublisher advertisement_publisher_{nullptr};
  winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
      GattLocalCharacteristic local_characteristic_{nullptr};
  winrt::event_token write_requested_token_{};
  winrt::event_token read_requested_token_{};
  winrt::event_token subscribed_changed_token_{};
  std::vector<uint8_t> local_characteristic_value_;
  std::string local_service_uuid_;
  std::string local_characteristic_uuid_;
};

// static
void FlutterBluetoothPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), "flutter_bluetooth_plugin",
          &flutter::StandardMethodCodec::GetInstance());

  auto event_channel =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar->messenger(), "flutter_bluetooth_plugin/events",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FlutterBluetoothPlugin>();
  auto* plugin_pointer = plugin.get();
  plugin_pointer->impl_->CreatePlatformDispatcher();

  channel->SetMethodCallHandler(
      [plugin_pointer](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  event_channel->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [plugin_pointer](const EncodableValue*,
                           std::unique_ptr<flutter::EventSink<EncodableValue>>&& events) {
            plugin_pointer->impl_->OnListen(std::move(events));
            return nullptr;
          },
          [plugin_pointer](const EncodableValue*) {
            plugin_pointer->impl_->OnCancel();
            return nullptr;
          }));

  registrar->AddPlugin(std::move(plugin));
}

FlutterBluetoothPlugin::FlutterBluetoothPlugin()
    : impl_(std::make_shared<Impl>()) {}

FlutterBluetoothPlugin::~FlutterBluetoothPlugin() = default;

void FlutterBluetoothPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  impl_->HandleMethodCall(method_call, std::move(result));
}

}  // namespace flutter_bluetooth_plugin
