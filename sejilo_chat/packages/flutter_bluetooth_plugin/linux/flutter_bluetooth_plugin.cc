#include "include/flutter_bluetooth_plugin/flutter_bluetooth_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <optional>
#include <string>
#include <unordered_set>
#include <vector>

#include "flutter_bluetooth_plugin_private.h"

#define FLUTTER_BLUETOOTH_PLUGIN(obj)                         \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_bluetooth_plugin_get_type(), \
                              FlutterBluetoothPlugin))

struct PluginState {
  GDBusConnection* system_bus = nullptr;
  FlEventChannel* event_channel = nullptr;
  bool emit_events = false;
  guint interfaces_added_subscription = 0;
  guint properties_changed_subscription = 0;
  guint scan_timeout_id = 0;
  std::string adapter_path;
  std::unordered_set<std::string> notifying_characteristics;
};

struct _FlutterBluetoothPlugin {
  GObject parent_instance;
  PluginState* state;
};

namespace {

constexpr char kBluezName[] = "org.bluez";
constexpr char kObjectManagerPath[] = "/";
constexpr char kObjectManagerInterface[] = "org.freedesktop.DBus.ObjectManager";
constexpr char kPropertiesInterface[] = "org.freedesktop.DBus.Properties";
constexpr char kAdapterInterface[] = "org.bluez.Adapter1";
constexpr char kDeviceInterface[] = "org.bluez.Device1";
constexpr char kGattServiceInterface[] = "org.bluez.GattService1";
constexpr char kGattCharacteristicInterface[] = "org.bluez.GattCharacteristic1";
constexpr char kGattDescriptorInterface[] = "org.bluez.GattDescriptor1";

constexpr char kBluetoothUnavailableCode[] = "bluetooth_unavailable";
constexpr char kInvalidArgumentsCode[] = "invalid_arguments";
constexpr char kOperationFailedCode[] = "operation_failed";
constexpr char kUnsupportedCode[] = "unsupported";

void map_set_take(FlValue* map, const gchar* key, FlValue* value) {
  fl_value_set_string_take(map, key, value);
}

FlValue* string_or_null(const gchar* value) {
  return value == nullptr || value[0] == '\0' ? fl_value_new_null()
                                               : fl_value_new_string(value);
}

std::string to_lower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return value;
}

std::string normalize_address(const std::string& value) {
  std::string normalized;
  normalized.reserve(value.size());
  for (char c : value) {
    if (c == ':' || c == '-' || std::isspace(static_cast<unsigned char>(c))) {
      continue;
    }
    normalized.push_back(static_cast<char>(std::toupper(static_cast<unsigned char>(c))));
  }
  return normalized;
}

bool same_uuid(const gchar* left, const std::string& right) {
  if (left == nullptr) {
    return false;
  }
  return to_lower(left) == to_lower(right);
}

FlMethodResponse* success_response(FlValue* value = nullptr) {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(value));
}

FlMethodResponse* error_response(const gchar* code, const gchar* message) {
  return FL_METHOD_RESPONSE(fl_method_error_response_new(code, message, nullptr));
}

FlMethodResponse* error_from_gerror(const gchar* code, GError* error) {
  return error_response(code, error == nullptr ? "BlueZ DBus operation failed." : error->message);
}

GDBusConnection* ensure_bus(FlutterBluetoothPlugin* self, GError** error);
void send_adapter_state_event(FlutterBluetoothPlugin* self);
void send_scan_result_for_device(FlutterBluetoothPlugin* self, const gchar* path,
                                 GVariant* props);
void stop_scan_internal(FlutterBluetoothPlugin* self);

bool is_map(FlValue* value) {
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_MAP;
}

FlValue* lookup_arg(FlValue* args, const gchar* key) {
  return is_map(args) ? fl_value_lookup_string(args, key) : nullptr;
}

std::optional<std::string> get_string_arg(FlValue* args, const gchar* key) {
  FlValue* value = lookup_arg(args, key);
  if (value == nullptr || fl_value_get_type(value) == FL_VALUE_TYPE_NULL) {
    return std::nullopt;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
    return std::string(fl_value_get_string(value));
  }
  return std::nullopt;
}

std::string get_required_string_arg(FlValue* args, const gchar* key, GError** error) {
  auto value = get_string_arg(args, key);
  if (!value || value->empty()) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                "Missing required argument: %s", key);
    return {};
  }
  return *value;
}

bool get_bool_arg(FlValue* args, const gchar* key, bool default_value = false) {
  FlValue* value = lookup_arg(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return default_value;
  }
  return fl_value_get_bool(value);
}

std::optional<int64_t> get_int_arg(FlValue* args, const gchar* key) {
  FlValue* value = lookup_arg(args, key);
  if (value == nullptr || fl_value_get_type(value) == FL_VALUE_TYPE_NULL) {
    return std::nullopt;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return fl_value_get_int(value);
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return static_cast<int64_t>(fl_value_get_float(value));
  }
  return std::nullopt;
}

std::vector<std::string> get_string_list_arg(FlValue* args, const gchar* key) {
  std::vector<std::string> result;
  FlValue* value = lookup_arg(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_LIST) {
    return result;
  }
  const size_t length = fl_value_get_length(value);
  result.reserve(length);
  for (size_t i = 0; i < length; ++i) {
    FlValue* item = fl_value_get_list_value(value, i);
    if (fl_value_get_type(item) == FL_VALUE_TYPE_STRING) {
      result.emplace_back(fl_value_get_string(item));
    }
  }
  return result;
}

std::vector<uint8_t> get_byte_list_arg(FlValue* args, const gchar* key) {
  std::vector<uint8_t> result;
  FlValue* value = lookup_arg(args, key);
  if (value == nullptr || fl_value_get_type(value) == FL_VALUE_TYPE_NULL) {
    return result;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_UINT8_LIST) {
    const size_t length = fl_value_get_length(value);
    const uint8_t* bytes = fl_value_get_uint8_list(value);
    if (bytes != nullptr && length > 0) {
      result.assign(bytes, bytes + length);
    }
    return result;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT32_LIST) {
    const size_t length = fl_value_get_length(value);
    const int32_t* bytes = fl_value_get_int32_list(value);
    result.reserve(length);
    for (size_t i = 0; bytes != nullptr && i < length; ++i) {
      result.push_back(static_cast<uint8_t>(bytes[i]));
    }
    return result;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT64_LIST) {
    const size_t length = fl_value_get_length(value);
    const int64_t* bytes = fl_value_get_int64_list(value);
    result.reserve(length);
    for (size_t i = 0; bytes != nullptr && i < length; ++i) {
      result.push_back(static_cast<uint8_t>(bytes[i]));
    }
    return result;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_LIST) {
    const size_t length = fl_value_get_length(value);
    result.reserve(length);
    for (size_t i = 0; i < length; ++i) {
      FlValue* item = fl_value_get_list_value(value, i);
      if (fl_value_get_type(item) == FL_VALUE_TYPE_INT) {
        result.push_back(static_cast<uint8_t>(fl_value_get_int(item)));
      }
    }
  }
  return result;
}

FlValue* string_list_value(const std::vector<std::string>& values) {
  FlValue* list = fl_value_new_list();
  for (const auto& value : values) {
    fl_value_append_take(list, fl_value_new_string(value.c_str()));
  }
  return list;
}

FlValue* bytes_value(const std::vector<uint8_t>& bytes) {
  return fl_value_new_uint8_list(bytes.empty() ? nullptr : bytes.data(), bytes.size());
}

std::vector<uint8_t> bytes_from_variant(GVariant* value) {
  if (value == nullptr) {
    return {};
  }
  g_autoptr(GVariant) unboxed = nullptr;
  if (g_variant_is_of_type(value, G_VARIANT_TYPE_VARIANT)) {
    unboxed = g_variant_get_variant(value);
    value = unboxed;
  }
  if (!g_variant_is_of_type(value, G_VARIANT_TYPE_BYTESTRING) &&
      !g_variant_is_of_type(value, G_VARIANT_TYPE("ay"))) {
    return {};
  }
  gsize length = 0;
  const auto* data = static_cast<const uint8_t*>(
      g_variant_get_fixed_array(value, &length, sizeof(uint8_t)));
  if (data == nullptr || length == 0) {
    return {};
  }
  return std::vector<uint8_t>(data, data + length);
}

FlValue* bytes_value_from_variant(GVariant* value) {
  return bytes_value(bytes_from_variant(value));
}

GVariant* lookup_property_value(GVariant* props, const gchar* key) {
  if (props == nullptr) {
    return nullptr;
  }
  GVariant* value = g_variant_lookup_value(props, key, nullptr);
  if (value == nullptr) {
    return nullptr;
  }
  if (g_variant_is_of_type(value, G_VARIANT_TYPE_VARIANT)) {
    GVariant* unboxed = g_variant_get_variant(value);
    g_variant_unref(value);
    return unboxed;
  }
  return value;
}

std::string string_property(GVariant* props, const gchar* key) {
  if (props == nullptr) {
    return {};
  }
  g_autoptr(GVariant) value = lookup_property_value(props, key);
  if (value == nullptr || !g_variant_is_of_type(value, G_VARIANT_TYPE_STRING)) {
    return {};
  }
  return std::string(g_variant_get_string(value, nullptr));
}

std::string object_path_property(GVariant* props, const gchar* key) {
  if (props == nullptr) {
    return {};
  }
  g_autoptr(GVariant) value = lookup_property_value(props, key);
  if (value == nullptr || !g_variant_is_of_type(value, G_VARIANT_TYPE_OBJECT_PATH)) {
    return {};
  }
  return std::string(g_variant_get_string(value, nullptr));
}

bool bool_property(GVariant* props, const gchar* key, bool default_value = false) {
  if (props == nullptr) {
    return default_value;
  }
  g_autoptr(GVariant) value = lookup_property_value(props, key);
  if (value == nullptr || !g_variant_is_of_type(value, G_VARIANT_TYPE_BOOLEAN)) {
    return default_value;
  }
  return g_variant_get_boolean(value);
}


bool has_property(GVariant* props, const gchar* key) {
  if (props == nullptr) {
    return false;
  }
  g_autoptr(GVariant) value = lookup_property_value(props, key);
  return value != nullptr;
}

int64_t int_property(GVariant* props, const gchar* key, int64_t default_value = 0) {
  if (props == nullptr) {
    return default_value;
  }
  g_autoptr(GVariant) value = lookup_property_value(props, key);
  if (value == nullptr) {
    return default_value;
  }
  if (g_variant_is_of_type(value, G_VARIANT_TYPE_INT16)) {
    return g_variant_get_int16(value);
  }
  if (g_variant_is_of_type(value, G_VARIANT_TYPE_UINT16)) {
    return g_variant_get_uint16(value);
  }
  if (g_variant_is_of_type(value, G_VARIANT_TYPE_INT32)) {
    return g_variant_get_int32(value);
  }
  if (g_variant_is_of_type(value, G_VARIANT_TYPE_UINT32)) {
    return g_variant_get_uint32(value);
  }
  if (g_variant_is_of_type(value, G_VARIANT_TYPE_INT64)) {
    return g_variant_get_int64(value);
  }
  if (g_variant_is_of_type(value, G_VARIANT_TYPE_UINT64)) {
    return static_cast<int64_t>(g_variant_get_uint64(value));
  }
  return default_value;
}

std::vector<std::string> string_array_property(GVariant* props, const gchar* key) {
  std::vector<std::string> result;
  if (props == nullptr) {
    return result;
  }
  g_autoptr(GVariant) value = lookup_property_value(props, key);
  if (value == nullptr || !g_variant_is_of_type(value, G_VARIANT_TYPE("as"))) {
    return result;
  }
  GVariantIter iter;
  const gchar* item = nullptr;
  g_variant_iter_init(&iter, value);
  while (g_variant_iter_next(&iter, "&s", &item)) {
    result.emplace_back(item);
  }
  return result;
}

FlValue* manufacturer_data_value(GVariant* props) {
  FlValue* map = fl_value_new_map();
  if (props == nullptr) {
    return map;
  }
  g_autoptr(GVariant) data = lookup_property_value(props, "ManufacturerData");
  if (data == nullptr || !g_variant_is_of_type(data, G_VARIANT_TYPE("a{qv}"))) {
    return map;
  }
  GVariantIter iter;
  guint16 company_id = 0;
  GVariant* value = nullptr;
  g_variant_iter_init(&iter, data);
  while (g_variant_iter_next(&iter, "{q@v}", &company_id, &value)) {
    g_autoptr(GVariant) unboxed = g_variant_get_variant(value);
    gchar* key = g_strdup_printf("%u", company_id);
    map_set_take(map, key, bytes_value_from_variant(unboxed));
    g_free(key);
    g_variant_unref(value);
  }
  return map;
}

FlValue* service_data_value(GVariant* props) {
  FlValue* map = fl_value_new_map();
  if (props == nullptr) {
    return map;
  }
  g_autoptr(GVariant) data = lookup_property_value(props, "ServiceData");
  if (data == nullptr || !g_variant_is_of_type(data, G_VARIANT_TYPE("a{sv}"))) {
    return map;
  }
  GVariantIter iter;
  const gchar* uuid = nullptr;
  GVariant* value = nullptr;
  g_variant_iter_init(&iter, data);
  while (g_variant_iter_next(&iter, "{&s@v}", &uuid, &value)) {
    g_autoptr(GVariant) unboxed = g_variant_get_variant(value);
    map_set_take(map, uuid, bytes_value_from_variant(unboxed));
    g_variant_unref(value);
  }
  return map;
}

FlValue* raw_value(const gchar* path) {
  FlValue* raw = fl_value_new_map();
  map_set_take(raw, "platform", fl_value_new_string("linux"));
  if (path != nullptr) {
    map_set_take(raw, "dbusPath", fl_value_new_string(path));
  }
  return raw;
}

GVariant* get_managed_objects(FlutterBluetoothPlugin* self, GError** error) {
  GDBusConnection* bus = ensure_bus(self, error);
  if (bus == nullptr) {
    return nullptr;
  }
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      bus, kBluezName, kObjectManagerPath, kObjectManagerInterface,
      "GetManagedObjects", nullptr, G_VARIANT_TYPE("(a{oa{sa{sv}}})"),
      G_DBUS_CALL_FLAGS_NONE, -1, nullptr, error);
  if (result == nullptr) {
    return nullptr;
  }
  GVariant* objects = nullptr;
  g_variant_get(result, "(@a{oa{sa{sv}}})", &objects);
  return objects;
}

std::string find_adapter_path(FlutterBluetoothPlugin* self, GError** error) {
  g_autoptr(GVariant) objects = get_managed_objects(self, error);
  if (objects == nullptr) {
    return {};
  }

  GVariantIter iter;
  const gchar* path = nullptr;
  GVariant* interfaces = nullptr;
  g_variant_iter_init(&iter, objects);
  while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &interfaces)) {
    g_autoptr(GVariant) adapter_props =
        g_variant_lookup_value(interfaces, kAdapterInterface, G_VARIANT_TYPE("a{sv}"));
    g_variant_unref(interfaces);
    if (adapter_props != nullptr) {
      self->state->adapter_path = path;
      return path;
    }
  }
  self->state->adapter_path.clear();
  return {};
}

GVariant* get_interface_properties(FlutterBluetoothPlugin* self, const gchar* path,
                                   const gchar* interface, GError** error) {
  GDBusConnection* bus = ensure_bus(self, error);
  if (bus == nullptr) {
    return nullptr;
  }
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      bus, kBluezName, path, kPropertiesInterface, "GetAll",
      g_variant_new("(s)", interface), G_VARIANT_TYPE("(a{sv})"),
      G_DBUS_CALL_FLAGS_NONE, -1, nullptr, error);
  if (result == nullptr) {
    return nullptr;
  }
  GVariant* props = nullptr;
  g_variant_get(result, "(@a{sv})", &props);
  return props;
}

std::string adapter_state_from_props(GVariant* props) {
  if (props == nullptr) {
    return "unsupported";
  }
  return bool_property(props, "Powered") ? "poweredOn" : "poweredOff";
}

std::string current_adapter_state(FlutterBluetoothPlugin* self) {
  g_autoptr(GError) error = nullptr;
  std::string adapter = find_adapter_path(self, &error);
  if (adapter.empty()) {
    return "unsupported";
  }
  g_autoptr(GVariant) props = get_interface_properties(self, adapter.c_str(), kAdapterInterface, nullptr);
  if (props == nullptr) {
    return "unknown";
  }
  return adapter_state_from_props(props);
}

FlValue* device_value(const gchar* path, GVariant* props) {
  const std::string address = string_property(props, "Address");
  const std::string bluez_name = string_property(props, "Name");
  const std::string name =
      !bluez_name.empty() ? bluez_name : string_property(props, "Alias");

  FlValue* device = fl_value_new_map();
  map_set_take(device, "id", fl_value_new_string(address.empty() ? path : address.c_str()));
  map_set_take(device, "name", string_or_null(name.c_str()));
  map_set_take(device, "address", string_or_null(address.c_str()));
  map_set_take(device, "type", fl_value_new_string("ble"));
  map_set_take(device, "isConnected", fl_value_new_bool(bool_property(props, "Connected")));
  map_set_take(device, "isBonded", fl_value_new_bool(bool_property(props, "Paired")));

  FlValue* raw = raw_value(path);
  const std::string address_type = string_property(props, "AddressType");
  if (!address_type.empty()) {
    map_set_take(raw, "addressType", fl_value_new_string(address_type.c_str()));
  }
  map_set_take(raw, "servicesResolved", fl_value_new_bool(bool_property(props, "ServicesResolved")));
  map_set_take(device, "raw", raw);
  return device;
}

FlValue* scan_result_value(const gchar* path, GVariant* props) {
  const std::string bluez_name = string_property(props, "Name");
  const std::string name =
      !bluez_name.empty() ? bluez_name : string_property(props, "Alias");
  FlValue* result = fl_value_new_map();
  map_set_take(result, "type", fl_value_new_string("scanResult"));
  map_set_take(result, "device", device_value(path, props));
  map_set_take(result, "rssi", fl_value_new_int(int_property(props, "RSSI")));
  map_set_take(result, "localName", string_or_null(name.c_str()));
  map_set_take(result, "serviceUuids", string_list_value(string_array_property(props, "UUIDs")));
  map_set_take(result, "manufacturerData", manufacturer_data_value(props));
  map_set_take(result, "serviceData", service_data_value(props));

  g_autoptr(GVariant) tx_power = lookup_property_value(props, "TxPower");
  if (tx_power != nullptr) {
    map_set_take(result, "txPowerLevel", fl_value_new_int(int_property(props, "TxPower")));
  }
  map_set_take(result, "raw", raw_value(path));
  return result;
}

std::string device_id_from_path(FlutterBluetoothPlugin* self, const gchar* path) {
  g_autoptr(GVariant) props = get_interface_properties(self, path, kDeviceInterface, nullptr);
  if (props == nullptr) {
    return path == nullptr ? "" : path;
  }
  std::string address = string_property(props, "Address");
  return address.empty() ? std::string(path) : address;
}

std::string resolve_device_path(FlutterBluetoothPlugin* self, const std::string& device_id,
                                GError** error) {
  if (!device_id.empty() && device_id.front() == '/') {
    return device_id;
  }
  g_autoptr(GVariant) objects = get_managed_objects(self, error);
  if (objects == nullptr) {
    return {};
  }

  const std::string normalized_id = normalize_address(device_id);
  GVariantIter iter;
  const gchar* path = nullptr;
  GVariant* interfaces = nullptr;
  g_variant_iter_init(&iter, objects);
  while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &interfaces)) {
    g_autoptr(GVariant) props =
        g_variant_lookup_value(interfaces, kDeviceInterface, G_VARIANT_TYPE("a{sv}"));
    g_variant_unref(interfaces);
    if (props == nullptr) {
      continue;
    }
    std::string address = string_property(props, "Address");
    if (normalize_address(address) == normalized_id || device_id == path) {
      return path;
    }
  }
  return {};
}

bool device_has_any_service(GVariant* props, const std::vector<std::string>& service_uuids) {
  if (service_uuids.empty()) {
    return true;
  }
  std::vector<std::string> uuids = string_array_property(props, "UUIDs");
  for (const auto& candidate : uuids) {
    for (const auto& expected : service_uuids) {
      if (to_lower(candidate) == to_lower(expected)) {
        return true;
      }
    }
  }
  return false;
}

FlValue* devices_list(FlutterBluetoothPlugin* self, bool bonded_only, bool connected_only,
                      const std::vector<std::string>& service_uuids, GError** error) {
  FlValue* list = fl_value_new_list();
  g_autoptr(GVariant) objects = get_managed_objects(self, error);
  if (objects == nullptr) {
    return list;
  }

  GVariantIter iter;
  const gchar* path = nullptr;
  GVariant* interfaces = nullptr;
  g_variant_iter_init(&iter, objects);
  while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &interfaces)) {
    g_autoptr(GVariant) props =
        g_variant_lookup_value(interfaces, kDeviceInterface, G_VARIANT_TYPE("a{sv}"));
    g_variant_unref(interfaces);
    if (props == nullptr) {
      continue;
    }
    if (bonded_only && !bool_property(props, "Paired")) {
      continue;
    }
    if (connected_only && !bool_property(props, "Connected")) {
      continue;
    }
    if (!device_has_any_service(props, service_uuids)) {
      continue;
    }
    fl_value_append_take(list, device_value(path, props));
  }
  return list;
}

std::string find_service_path_for_device(GVariant* objects, const std::string& device_path,
                                         const std::string& service_uuid) {
  GVariantIter iter;
  const gchar* path = nullptr;
  GVariant* interfaces = nullptr;
  g_variant_iter_init(&iter, objects);
  while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &interfaces)) {
    g_autoptr(GVariant) props =
        g_variant_lookup_value(interfaces, kGattServiceInterface, G_VARIANT_TYPE("a{sv}"));
    g_variant_unref(interfaces);
    if (props == nullptr) {
      continue;
    }
    if (object_path_property(props, "Device") == device_path &&
        same_uuid(string_property(props, "UUID").c_str(), service_uuid)) {
      return path;
    }
  }
  return {};
}

std::string find_characteristic_path(GVariant* objects, const std::string& service_path,
                                     const std::string& characteristic_uuid) {
  GVariantIter iter;
  const gchar* path = nullptr;
  GVariant* interfaces = nullptr;
  g_variant_iter_init(&iter, objects);
  while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &interfaces)) {
    g_autoptr(GVariant) props =
        g_variant_lookup_value(interfaces, kGattCharacteristicInterface, G_VARIANT_TYPE("a{sv}"));
    g_variant_unref(interfaces);
    if (props == nullptr) {
      continue;
    }
    if (object_path_property(props, "Service") == service_path &&
        same_uuid(string_property(props, "UUID").c_str(), characteristic_uuid)) {
      return path;
    }
  }
  return {};
}

std::string find_descriptor_path(GVariant* objects, const std::string& characteristic_path,
                                 const std::string& descriptor_uuid) {
  GVariantIter iter;
  const gchar* path = nullptr;
  GVariant* interfaces = nullptr;
  g_variant_iter_init(&iter, objects);
  while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &interfaces)) {
    g_autoptr(GVariant) props =
        g_variant_lookup_value(interfaces, kGattDescriptorInterface, G_VARIANT_TYPE("a{sv}"));
    g_variant_unref(interfaces);
    if (props == nullptr) {
      continue;
    }
    if (object_path_property(props, "Characteristic") == characteristic_path &&
        same_uuid(string_property(props, "UUID").c_str(), descriptor_uuid)) {
      return path;
    }
  }
  return {};
}

std::string resolve_characteristic_path(FlutterBluetoothPlugin* self, FlValue* args,
                                        std::string* device_path_out,
                                        std::string* service_path_out,
                                        GError** error) {
  const std::string device_id = get_required_string_arg(args, "deviceId", error);
  if (device_id.empty() && error != nullptr && *error != nullptr) {
    return {};
  }
  const std::string service_uuid = get_required_string_arg(args, "serviceUuid", error);
  if (service_uuid.empty() && error != nullptr && *error != nullptr) {
    return {};
  }
  const std::string characteristic_uuid = get_required_string_arg(args, "characteristicUuid", error);
  if (characteristic_uuid.empty() && error != nullptr && *error != nullptr) {
    return {};
  }

  std::string device_path = resolve_device_path(self, device_id, error);
  if (device_path.empty()) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND, "Device not found: %s", device_id.c_str());
    return {};
  }
  g_autoptr(GVariant) objects = get_managed_objects(self, error);
  if (objects == nullptr) {
    return {};
  }
  std::string service_path = find_service_path_for_device(objects, device_path, service_uuid);
  if (service_path.empty()) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND, "GATT service not found: %s", service_uuid.c_str());
    return {};
  }
  std::string characteristic_path = find_characteristic_path(objects, service_path, characteristic_uuid);
  if (characteristic_path.empty()) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND, "GATT characteristic not found: %s", characteristic_uuid.c_str());
    return {};
  }
  if (device_path_out != nullptr) {
    *device_path_out = device_path;
  }
  if (service_path_out != nullptr) {
    *service_path_out = service_path;
  }
  return characteristic_path;
}

std::string resolve_descriptor_path(FlutterBluetoothPlugin* self, FlValue* args,
                                    std::string* characteristic_path_out,
                                    GError** error) {
  std::string device_path;
  std::string service_path;
  std::string characteristic_path =
      resolve_characteristic_path(self, args, &device_path, &service_path, error);
  if (characteristic_path.empty()) {
    return {};
  }
  const std::string descriptor_uuid = get_required_string_arg(args, "descriptorUuid", error);
  if (descriptor_uuid.empty() && error != nullptr && *error != nullptr) {
    return {};
  }

  g_autoptr(GVariant) objects = get_managed_objects(self, error);
  if (objects == nullptr) {
    return {};
  }
  std::string descriptor_path = find_descriptor_path(objects, characteristic_path, descriptor_uuid);
  if (descriptor_path.empty()) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND, "GATT descriptor not found: %s", descriptor_uuid.c_str());
    return {};
  }
  if (characteristic_path_out != nullptr) {
    *characteristic_path_out = characteristic_path;
  }
  return descriptor_path;
}

FlValue* descriptor_value(const gchar* path, GVariant* props) {
  FlValue* descriptor = fl_value_new_map();
  map_set_take(descriptor, "uuid", fl_value_new_string(string_property(props, "UUID").c_str()));
  map_set_take(descriptor, "characteristicUuid", fl_value_new_null());
  map_set_take(descriptor, "value", bytes_value({}));
  map_set_take(descriptor, "raw", raw_value(path));
  return descriptor;
}

FlValue* descriptors_for_characteristic(GVariant* objects, const std::string& characteristic_path) {
  FlValue* list = fl_value_new_list();
  GVariantIter iter;
  const gchar* path = nullptr;
  GVariant* interfaces = nullptr;
  g_variant_iter_init(&iter, objects);
  while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &interfaces)) {
    g_autoptr(GVariant) props =
        g_variant_lookup_value(interfaces, kGattDescriptorInterface, G_VARIANT_TYPE("a{sv}"));
    g_variant_unref(interfaces);
    if (props == nullptr) {
      continue;
    }
    if (object_path_property(props, "Characteristic") == characteristic_path) {
      fl_value_append_take(list, descriptor_value(path, props));
    }
  }
  return list;
}

FlValue* characteristic_value(GVariant* objects, const gchar* path, GVariant* props,
                              const std::string& service_uuid) {
  FlValue* characteristic = fl_value_new_map();
  map_set_take(characteristic, "uuid", fl_value_new_string(string_property(props, "UUID").c_str()));
  map_set_take(characteristic, "serviceUuid", fl_value_new_string(service_uuid.c_str()));
  map_set_take(characteristic, "properties", string_list_value(string_array_property(props, "Flags")));
  map_set_take(characteristic, "permissions", string_list_value({}));
  map_set_take(characteristic, "value", bytes_value({}));
  map_set_take(characteristic, "descriptors", descriptors_for_characteristic(objects, path));
  map_set_take(characteristic, "raw", raw_value(path));
  return characteristic;
}

FlValue* characteristics_for_service(GVariant* objects, const std::string& service_path,
                                     const std::string& service_uuid) {
  FlValue* list = fl_value_new_list();
  GVariantIter iter;
  const gchar* path = nullptr;
  GVariant* interfaces = nullptr;
  g_variant_iter_init(&iter, objects);
  while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &interfaces)) {
    g_autoptr(GVariant) props =
        g_variant_lookup_value(interfaces, kGattCharacteristicInterface, G_VARIANT_TYPE("a{sv}"));
    g_variant_unref(interfaces);
    if (props == nullptr) {
      continue;
    }
    if (object_path_property(props, "Service") == service_path) {
      fl_value_append_take(list, characteristic_value(objects, path, props, service_uuid));
    }
  }
  return list;
}

FlValue* service_value(GVariant* objects, const gchar* path, GVariant* props) {
  const std::string uuid = string_property(props, "UUID");
  FlValue* service = fl_value_new_map();
  map_set_take(service, "uuid", fl_value_new_string(uuid.c_str()));
  map_set_take(service, "isPrimary", fl_value_new_bool(bool_property(props, "Primary", true)));
  map_set_take(service, "includedServices", string_list_value({}));
  map_set_take(service, "characteristics", characteristics_for_service(objects, path, uuid));
  map_set_take(service, "raw", raw_value(path));
  return service;
}

FlValue* services_for_device(FlutterBluetoothPlugin* self, const std::string& device_path,
                             GError** error) {
  FlValue* list = fl_value_new_list();
  g_autoptr(GVariant) objects = get_managed_objects(self, error);
  if (objects == nullptr) {
    return list;
  }

  GVariantIter iter;
  const gchar* path = nullptr;
  GVariant* interfaces = nullptr;
  g_variant_iter_init(&iter, objects);
  while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &interfaces)) {
    g_autoptr(GVariant) props =
        g_variant_lookup_value(interfaces, kGattServiceInterface, G_VARIANT_TYPE("a{sv}"));
    g_variant_unref(interfaces);
    if (props == nullptr) {
      continue;
    }
    if (object_path_property(props, "Device") == device_path) {
      fl_value_append_take(list, service_value(objects, path, props));
    }
  }
  return list;
}

GVariant* empty_options() {
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE("a{sv}"));
  return g_variant_builder_end(&options);
}

GVariant* options_with_type(const gchar* type) {
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&options, "{sv}", "type", g_variant_new_string(type));
  return g_variant_builder_end(&options);
}

GVariant* bytes_variant(const std::vector<uint8_t>& bytes) {
  return g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE,
                                   bytes.empty() ? nullptr : bytes.data(),
                                   bytes.size(), sizeof(uint8_t));
}

void send_event(FlutterBluetoothPlugin* self, FlValue* event) {
  if (self->state == nullptr || !self->state->emit_events ||
      self->state->event_channel == nullptr) {
    return;
  }
  g_autoptr(GError) error = nullptr;
  if (!fl_event_channel_send(self->state->event_channel, event, nullptr, &error)) {
    g_warning("Failed to send Bluetooth event: %s",
              error == nullptr ? "unknown error" : error->message);
  }
}

void send_adapter_state_event(FlutterBluetoothPlugin* self) {
  g_autoptr(FlValue) event = fl_value_new_map();
  map_set_take(event, "type", fl_value_new_string("adapterState"));
  map_set_take(event, "state", fl_value_new_string(current_adapter_state(self).c_str()));
  send_event(self, event);
}

void send_connection_state_event(FlutterBluetoothPlugin* self, const gchar* path,
                                 const gchar* state) {
  g_autoptr(FlValue) event = fl_value_new_map();
  map_set_take(event, "type", fl_value_new_string("connectionState"));
  map_set_take(event, "deviceId", fl_value_new_string(device_id_from_path(self, path).c_str()));
  map_set_take(event, "state", fl_value_new_string(state));
  send_event(self, event);
}

void send_bond_state_event(FlutterBluetoothPlugin* self, const gchar* path, bool paired) {
  g_autoptr(FlValue) event = fl_value_new_map();
  map_set_take(event, "type", fl_value_new_string("bondState"));
  map_set_take(event, "deviceId", fl_value_new_string(device_id_from_path(self, path).c_str()));
  map_set_take(event, "state", fl_value_new_string(paired ? "bonded" : "none"));
  send_event(self, event);
}

void send_scan_result_for_device(FlutterBluetoothPlugin* self, const gchar* path,
                                 GVariant* props) {
  if (props == nullptr) {
    g_autoptr(GVariant) fetched = get_interface_properties(self, path, kDeviceInterface, nullptr);
    if (fetched == nullptr) {
      return;
    }
    g_autoptr(FlValue) event = scan_result_value(path, fetched);
    send_event(self, event);
    return;
  }
  g_autoptr(FlValue) event = scan_result_value(path, props);
  send_event(self, event);
}

void send_characteristic_value_event(FlutterBluetoothPlugin* self,
                                     const std::string& characteristic_path,
                                     const std::vector<uint8_t>& bytes) {
  g_autoptr(GVariant) char_props =
      get_interface_properties(self, characteristic_path.c_str(), kGattCharacteristicInterface, nullptr);
  if (char_props == nullptr) {
    return;
  }
  const std::string service_path = object_path_property(char_props, "Service");
  g_autoptr(GVariant) service_props =
      get_interface_properties(self, service_path.c_str(), kGattServiceInterface, nullptr);
  if (service_props == nullptr) {
    return;
  }
  const std::string device_path = object_path_property(service_props, "Device");

  g_autoptr(FlValue) event = fl_value_new_map();
  map_set_take(event, "type", fl_value_new_string("characteristicValue"));
  map_set_take(event, "deviceId", fl_value_new_string(device_id_from_path(self, device_path.c_str()).c_str()));
  map_set_take(event, "serviceUuid", fl_value_new_string(string_property(service_props, "UUID").c_str()));
  map_set_take(event, "characteristicUuid", fl_value_new_string(string_property(char_props, "UUID").c_str()));
  map_set_take(event, "value", bytes_value(bytes));
  send_event(self, event);
}

void send_descriptor_value_event(FlutterBluetoothPlugin* self,
                                 const std::string& descriptor_path,
                                 const std::vector<uint8_t>& bytes) {
  g_autoptr(GVariant) descriptor_props =
      get_interface_properties(self, descriptor_path.c_str(), kGattDescriptorInterface, nullptr);
  if (descriptor_props == nullptr) {
    return;
  }
  const std::string characteristic_path = object_path_property(descriptor_props, "Characteristic");
  g_autoptr(GVariant) char_props =
      get_interface_properties(self, characteristic_path.c_str(), kGattCharacteristicInterface, nullptr);
  if (char_props == nullptr) {
    return;
  }
  const std::string service_path = object_path_property(char_props, "Service");
  g_autoptr(GVariant) service_props =
      get_interface_properties(self, service_path.c_str(), kGattServiceInterface, nullptr);
  if (service_props == nullptr) {
    return;
  }
  const std::string device_path = object_path_property(service_props, "Device");

  g_autoptr(FlValue) event = fl_value_new_map();
  map_set_take(event, "type", fl_value_new_string("descriptorValue"));
  map_set_take(event, "deviceId", fl_value_new_string(device_id_from_path(self, device_path.c_str()).c_str()));
  map_set_take(event, "serviceUuid", fl_value_new_string(string_property(service_props, "UUID").c_str()));
  map_set_take(event, "characteristicUuid", fl_value_new_string(string_property(char_props, "UUID").c_str()));
  map_set_take(event, "descriptorUuid", fl_value_new_string(string_property(descriptor_props, "UUID").c_str()));
  map_set_take(event, "value", bytes_value(bytes));
  send_event(self, event);
}

void interfaces_added_cb(GDBusConnection*, const gchar*, const gchar* object_path,
                         const gchar*, const gchar*, GVariant* parameters,
                         gpointer user_data) {
  FlutterBluetoothPlugin* self = FLUTTER_BLUETOOTH_PLUGIN(user_data);
  const gchar* path = nullptr;
  GVariant* interfaces = nullptr;
  g_variant_get(parameters, "(&o@a{sa{sv}})", &path, &interfaces);
  g_autoptr(GVariant) interfaces_auto = interfaces;
  g_autoptr(GVariant) device_props =
      g_variant_lookup_value(interfaces, kDeviceInterface, G_VARIANT_TYPE("a{sv}"));
  if (device_props != nullptr) {
    send_scan_result_for_device(self, path != nullptr ? path : object_path, device_props);
  }
  g_autoptr(GVariant) adapter_props =
      g_variant_lookup_value(interfaces, kAdapterInterface, G_VARIANT_TYPE("a{sv}"));
  if (adapter_props != nullptr) {
    send_adapter_state_event(self);
  }
}

void properties_changed_cb(GDBusConnection*, const gchar*, const gchar* object_path,
                           const gchar*, const gchar*, GVariant* parameters,
                           gpointer user_data) {
  FlutterBluetoothPlugin* self = FLUTTER_BLUETOOTH_PLUGIN(user_data);
  const gchar* interface = nullptr;
  GVariant* changed = nullptr;
  GVariant* invalidated = nullptr;
  g_variant_get(parameters, "(&s@a{sv}@as)", &interface, &changed, &invalidated);
  g_autoptr(GVariant) changed_auto = changed;
  g_autoptr(GVariant) invalidated_auto = invalidated;

  if (g_strcmp0(interface, kAdapterInterface) == 0) {
    if (has_property(changed, "Powered") || has_property(changed, "Discovering")) {
      send_adapter_state_event(self);
    }
    return;
  }

  if (g_strcmp0(interface, kDeviceInterface) == 0) {
    g_autoptr(GVariant) connected = lookup_property_value(changed, "Connected");
    if (connected != nullptr && g_variant_is_of_type(connected, G_VARIANT_TYPE_BOOLEAN)) {
      send_connection_state_event(self, object_path, g_variant_get_boolean(connected) ? "connected" : "disconnected");
    }
    g_autoptr(GVariant) paired = lookup_property_value(changed, "Paired");
    if (paired != nullptr && g_variant_is_of_type(paired, G_VARIANT_TYPE_BOOLEAN)) {
      send_bond_state_event(self, object_path, g_variant_get_boolean(paired));
    }
    if (has_property(changed, "RSSI") || has_property(changed, "ManufacturerData") ||
        has_property(changed, "ServiceData") || has_property(changed, "UUIDs") ||
        has_property(changed, "Name")) {
      send_scan_result_for_device(self, object_path, nullptr);
    }
    return;
  }

  if (g_strcmp0(interface, kGattCharacteristicInterface) == 0) {
    if (self->state->notifying_characteristics.count(object_path) == 0) {
      return;
    }
    g_autoptr(GVariant) value = lookup_property_value(changed, "Value");
    if (value != nullptr) {
      send_characteristic_value_event(self, object_path, bytes_from_variant(value));
    }
  }
}

void ensure_signal_subscriptions(FlutterBluetoothPlugin* self) {
  if (self->state->interfaces_added_subscription != 0 &&
      self->state->properties_changed_subscription != 0) {
    return;
  }
  g_autoptr(GError) error = nullptr;
  GDBusConnection* bus = ensure_bus(self, &error);
  if (bus == nullptr) {
    g_warning("Unable to subscribe to BlueZ signals: %s",
              error == nullptr ? "unknown error" : error->message);
    return;
  }
  if (self->state->interfaces_added_subscription == 0) {
    self->state->interfaces_added_subscription = g_dbus_connection_signal_subscribe(
        bus, kBluezName, kObjectManagerInterface, "InterfacesAdded", nullptr,
        nullptr, G_DBUS_SIGNAL_FLAGS_NONE, interfaces_added_cb, self, nullptr);
  }
  if (self->state->properties_changed_subscription == 0) {
    self->state->properties_changed_subscription = g_dbus_connection_signal_subscribe(
        bus, kBluezName, kPropertiesInterface, "PropertiesChanged", nullptr,
        nullptr, G_DBUS_SIGNAL_FLAGS_NONE, properties_changed_cb, self, nullptr);
  }
}

GDBusConnection* ensure_bus(FlutterBluetoothPlugin* self, GError** error) {
  if (self->state->system_bus != nullptr) {
    return self->state->system_bus;
  }
  self->state->system_bus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, error);
  return self->state->system_bus;
}

bool call_no_result(FlutterBluetoothPlugin* self, const gchar* path, const gchar* interface,
                    const gchar* method, GVariant* parameters, GError** error) {
  GDBusConnection* bus = ensure_bus(self, error);
  if (bus == nullptr) {
    return false;
  }
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      bus, kBluezName, path, interface, method, parameters, nullptr,
      G_DBUS_CALL_FLAGS_NONE, -1, nullptr, error);
  return result != nullptr;
}

bool set_property(FlutterBluetoothPlugin* self, const gchar* path, const gchar* interface,
                  const gchar* name, GVariant* value, GError** error) {
  return call_no_result(self, path, kPropertiesInterface, "Set",
                        g_variant_new("(ssv)", interface, name, value), error);
}

FlMethodResponse* get_platform_version_response() {
  struct utsname uname_data = {};
  uname(&uname_data);
  g_autofree gchar* version = g_strdup_printf("Linux %s", uname_data.version);
  g_autoptr(FlValue) result = fl_value_new_string(version);
  return success_response(result);
}

FlMethodResponse* is_supported_response(FlutterBluetoothPlugin* self) {
  g_autoptr(GError) error = nullptr;
  std::string adapter = find_adapter_path(self, &error);
  g_autoptr(FlValue) result = fl_value_new_bool(!adapter.empty());
  return success_response(result);
}

FlMethodResponse* adapter_state_response(FlutterBluetoothPlugin* self) {
  g_autoptr(FlValue) result = fl_value_new_string(current_adapter_state(self).c_str());
  return success_response(result);
}

FlMethodResponse* adapter_info_response(FlutterBluetoothPlugin* self) {
  g_autoptr(GError) error = nullptr;
  std::string adapter = find_adapter_path(self, &error);
  g_autoptr(FlValue) result = fl_value_new_map();
  const bool supported = !adapter.empty();
  map_set_take(result, "isSupported", fl_value_new_bool(supported));
  map_set_take(result, "state", fl_value_new_string(current_adapter_state(self).c_str()));
  map_set_take(result, "isBleSupported", fl_value_new_bool(supported));
  map_set_take(result, "isMultipleAdvertisementSupported", fl_value_new_bool(false));
  map_set_take(result, "isOffloadedFilteringSupported", fl_value_new_bool(false));
  map_set_take(result, "isOffloadedScanBatchingSupported", fl_value_new_bool(false));
  map_set_take(result, "isLe2MPhySupported", fl_value_new_bool(false));
  map_set_take(result, "isLeCodedPhySupported", fl_value_new_bool(false));
  map_set_take(result, "isLeExtendedAdvertisingSupported", fl_value_new_bool(false));
  map_set_take(result, "isLePeriodicAdvertisingSupported", fl_value_new_bool(false));

  if (supported) {
    g_autoptr(GVariant) props = get_interface_properties(self, adapter.c_str(), kAdapterInterface, nullptr);
    map_set_take(result, "name", string_or_null(string_property(props, "Name").c_str()));
    map_set_take(result, "address", string_or_null(string_property(props, "Address").c_str()));
    map_set_take(result, "isDiscovering", fl_value_new_bool(bool_property(props, "Discovering")));
    FlValue* raw = raw_value(adapter.c_str());
    map_set_take(raw, "alias", string_or_null(string_property(props, "Alias").c_str()));
    map_set_take(result, "raw", raw);
  } else {
    map_set_take(result, "name", fl_value_new_null());
    map_set_take(result, "address", fl_value_new_null());
    map_set_take(result, "isDiscovering", fl_value_new_bool(false));
    map_set_take(result, "raw", raw_value(nullptr));
  }
  return success_response(result);
}

FlMethodResponse* is_scanning_response(FlutterBluetoothPlugin* self) {
  g_autoptr(GError) error = nullptr;
  std::string adapter = find_adapter_path(self, &error);
  bool discovering = false;
  if (!adapter.empty()) {
    g_autoptr(GVariant) props = get_interface_properties(self, adapter.c_str(), kAdapterInterface, nullptr);
    discovering = bool_property(props, "Discovering");
  }
  g_autoptr(FlValue) result = fl_value_new_bool(discovering);
  return success_response(result);
}

FlMethodResponse* set_adapter_name_response(FlutterBluetoothPlugin* self, FlValue* args) {
  g_autoptr(GError) error = nullptr;
  std::string name = get_required_string_arg(args, "name", &error);
  if (error != nullptr) {
    return error_from_gerror(kInvalidArgumentsCode, error);
  }
  std::string adapter = find_adapter_path(self, &error);
  if (adapter.empty()) {
    g_autoptr(FlValue) result = fl_value_new_bool(false);
    return success_response(result);
  }
  bool ok = set_property(self, adapter.c_str(), kAdapterInterface, "Alias",
                         g_variant_new_string(name.c_str()), &error);
  if (!ok && error != nullptr) {
    g_clear_error(&error);
  }
  g_autoptr(FlValue) result = fl_value_new_bool(ok);
  return success_response(result);
}

FlMethodResponse* permission_map_response(FlutterBluetoothPlugin* self) {
  g_autoptr(GError) error = nullptr;
  std::string adapter = find_adapter_path(self, &error);
  g_autoptr(FlValue) map = fl_value_new_map();
  map_set_take(map, "bluetooth", fl_value_new_string(adapter.empty() ? "notApplicable" : "granted"));
  return success_response(map);
}

FlMethodResponse* request_enable_response(FlutterBluetoothPlugin* self) {
  g_autoptr(GError) error = nullptr;
  std::string adapter = find_adapter_path(self, &error);
  bool ok = false;
  if (!adapter.empty()) {
    ok = set_property(self, adapter.c_str(), kAdapterInterface, "Powered",
                      g_variant_new_boolean(TRUE), &error);
    if (!ok && error != nullptr) {
      g_clear_error(&error);
    }
  }
  g_autoptr(FlValue) result = fl_value_new_bool(ok);
  return success_response(result);
}

FlMethodResponse* open_bluetooth_settings_response() {
  const gchar* commands[] = {
      "gnome-control-center bluetooth", "blueman-manager", "kcmshell6 bluetooth",
      "kcmshell5 bluetooth", nullptr};
  for (const gchar** command = commands; *command != nullptr; ++command) {
    g_autoptr(GError) error = nullptr;
    if (g_spawn_command_line_async(*command, &error)) {
      break;
    }
  }
  return success_response();
}

FlMethodResponse* start_scan_response(FlutterBluetoothPlugin* self, FlValue* args) {
  ensure_signal_subscriptions(self);
  g_autoptr(GError) error = nullptr;
  std::string adapter = find_adapter_path(self, &error);
  if (adapter.empty()) {
    return error_response(kBluetoothUnavailableCode, "No BlueZ Bluetooth adapter is available.");
  }

  std::string scan_mode = get_string_arg(args, "scanMode").value_or("ble");
  const bool allow_duplicates = get_bool_arg(args, "allowDuplicates", false);
  const std::vector<std::string> service_uuids = get_string_list_arg(args, "serviceUuids");

  GVariantBuilder filter;
  g_variant_builder_init(&filter, G_VARIANT_TYPE("a{sv}"));
  const gchar* transport = "le";
  if (scan_mode == "classic") {
    transport = "bredr";
  } else if (scan_mode == "dual") {
    transport = "auto";
  }
  g_variant_builder_add(&filter, "{sv}", "Transport", g_variant_new_string(transport));
  g_variant_builder_add(&filter, "{sv}", "DuplicateData", g_variant_new_boolean(allow_duplicates));
  if (!service_uuids.empty()) {
    GVariantBuilder uuids;
    g_variant_builder_init(&uuids, G_VARIANT_TYPE("as"));
    for (const auto& uuid : service_uuids) {
      g_variant_builder_add(&uuids, "s", uuid.c_str());
    }
    g_variant_builder_add(&filter, "{sv}", "UUIDs", g_variant_builder_end(&uuids));
  }

  if (!call_no_result(self, adapter.c_str(), kAdapterInterface, "SetDiscoveryFilter",
                      g_variant_new("(a{sv})", &filter), &error)) {
    return error_from_gerror(kOperationFailedCode, error);
  }
  if (!call_no_result(self, adapter.c_str(), kAdapterInterface, "StartDiscovery",
                      g_variant_new("()"), &error)) {
    return error_from_gerror(kOperationFailedCode, error);
  }

  if (self->state->scan_timeout_id != 0) {
    g_source_remove(self->state->scan_timeout_id);
    self->state->scan_timeout_id = 0;
  }
  auto timeout_ms = get_int_arg(args, "timeoutMs");
  if (timeout_ms && *timeout_ms > 0) {
    self->state->scan_timeout_id = g_timeout_add_full(
        G_PRIORITY_DEFAULT, static_cast<guint>(*timeout_ms),
        [](gpointer user_data) -> gboolean {
          FlutterBluetoothPlugin* plugin = FLUTTER_BLUETOOTH_PLUGIN(user_data);
          plugin->state->scan_timeout_id = 0;
          stop_scan_internal(plugin);
          return G_SOURCE_REMOVE;
        },
        g_object_ref(self), g_object_unref);
  }
  return success_response();
}

void stop_scan_internal(FlutterBluetoothPlugin* self) {
  if (self->state == nullptr) {
    return;
  }
  if (self->state->scan_timeout_id != 0) {
    g_source_remove(self->state->scan_timeout_id);
    self->state->scan_timeout_id = 0;
  }
  g_autoptr(GError) error = nullptr;
  std::string adapter = find_adapter_path(self, &error);
  if (!adapter.empty()) {
    call_no_result(self, adapter.c_str(), kAdapterInterface, "StopDiscovery",
                   g_variant_new("()"), nullptr);
  }
}

FlMethodResponse* get_device_response(FlutterBluetoothPlugin* self, FlValue* args) {
  g_autoptr(GError) error = nullptr;
  std::string device_id = get_required_string_arg(args, "deviceId", &error);
  if (error != nullptr) {
    return error_from_gerror(kInvalidArgumentsCode, error);
  }
  std::string path = resolve_device_path(self, device_id, &error);
  if (path.empty()) {
    g_autoptr(FlValue) empty = fl_value_new_map();
    return success_response(empty);
  }
  g_autoptr(GVariant) props = get_interface_properties(self, path.c_str(), kDeviceInterface, &error);
  if (props == nullptr) {
    return error_from_gerror(kOperationFailedCode, error);
  }
  g_autoptr(FlValue) device = device_value(path.c_str(), props);
  return success_response(device);
}

FlMethodResponse* get_devices_response(FlutterBluetoothPlugin* self, FlValue* args) {
  g_autoptr(FlValue) list = fl_value_new_list();
  FlValue* ids = lookup_arg(args, "deviceIds");
  if (ids == nullptr || fl_value_get_type(ids) != FL_VALUE_TYPE_LIST) {
    return success_response(list);
  }
  for (size_t i = 0; i < fl_value_get_length(ids); ++i) {
    FlValue* id = fl_value_get_list_value(ids, i);
    if (fl_value_get_type(id) != FL_VALUE_TYPE_STRING) {
      continue;
    }
    g_autoptr(GError) error = nullptr;
    std::string path = resolve_device_path(self, fl_value_get_string(id), &error);
    if (path.empty()) {
      continue;
    }
    g_autoptr(GVariant) props = get_interface_properties(self, path.c_str(), kDeviceInterface, nullptr);
    if (props != nullptr) {
      fl_value_append_take(list, device_value(path.c_str(), props));
    }
  }
  return success_response(list);
}

FlMethodResponse* connect_response(FlutterBluetoothPlugin* self, FlValue* args) {
  ensure_signal_subscriptions(self);
  g_autoptr(GError) error = nullptr;
  std::string device_id = get_required_string_arg(args, "deviceId", &error);
  if (error != nullptr) {
    return error_from_gerror(kInvalidArgumentsCode, error);
  }
  std::string path = resolve_device_path(self, device_id, &error);
  if (path.empty()) {
    return error_response(kOperationFailedCode, "Device not found. Scan or pair the device first.");
  }
  send_connection_state_event(self, path.c_str(), "connecting");
  if (!call_no_result(self, path.c_str(), kDeviceInterface, "Connect", g_variant_new("()"), &error)) {
    return error_from_gerror(kOperationFailedCode, error);
  }
  send_connection_state_event(self, path.c_str(), "connected");
  return success_response();
}

FlMethodResponse* disconnect_response(FlutterBluetoothPlugin* self, FlValue* args) {
  g_autoptr(GError) error = nullptr;
  std::string device_id = get_required_string_arg(args, "deviceId", &error);
  if (error != nullptr) {
    return error_from_gerror(kInvalidArgumentsCode, error);
  }
  std::string path = resolve_device_path(self, device_id, &error);
  if (!path.empty()) {
    call_no_result(self, path.c_str(), kDeviceInterface, "Disconnect", g_variant_new("()"), nullptr);
    send_connection_state_event(self, path.c_str(), "disconnected");
  }
  return success_response();
}

FlMethodResponse* connection_state_response(FlutterBluetoothPlugin* self, FlValue* args) {
  g_autoptr(GError) error = nullptr;
  std::string device_id = get_required_string_arg(args, "deviceId", &error);
  if (error != nullptr) {
    return error_from_gerror(kInvalidArgumentsCode, error);
  }
  std::string path = resolve_device_path(self, device_id, &error);
  bool connected = false;
  if (!path.empty()) {
    g_autoptr(GVariant) props = get_interface_properties(self, path.c_str(), kDeviceInterface, nullptr);
    connected = bool_property(props, "Connected");
  }
  g_autoptr(FlValue) result = fl_value_new_string(connected ? "connected" : "disconnected");
  return success_response(result);
}

FlMethodResponse* discover_services_response(FlutterBluetoothPlugin* self, FlValue* args) {
  g_autoptr(GError) error = nullptr;
  std::string device_id = get_required_string_arg(args, "deviceId", &error);
  if (error != nullptr) {
    return error_from_gerror(kInvalidArgumentsCode, error);
  }
  std::string path = resolve_device_path(self, device_id, &error);
  if (path.empty()) {
    return error_response(kOperationFailedCode, "Device not found. Scan or pair the device first.");
  }
  g_autoptr(FlValue) services = services_for_device(self, path, &error);
  if (error != nullptr) {
    return error_from_gerror(kOperationFailedCode, error);
  }
  return success_response(services);
}

FlMethodResponse* read_characteristic_response(FlutterBluetoothPlugin* self, FlValue* args) {
  g_autoptr(GError) error = nullptr;
  std::string path = resolve_characteristic_path(self, args, nullptr, nullptr, &error);
  if (path.empty()) {
    return error_from_gerror(error != nullptr && error->code == G_IO_ERROR_INVALID_ARGUMENT
                                 ? kInvalidArgumentsCode
                                 : kOperationFailedCode,
                             error);
  }
  GDBusConnection* bus = ensure_bus(self, &error);
  if (bus == nullptr) {
    return error_from_gerror(kBluetoothUnavailableCode, error);
  }
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      bus, kBluezName, path.c_str(), kGattCharacteristicInterface, "ReadValue",
      g_variant_new("(@a{sv})", empty_options()), G_VARIANT_TYPE("(ay)"),
      G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
  if (result == nullptr) {
    return error_from_gerror(kOperationFailedCode, error);
  }
  GVariant* value = nullptr;
  g_variant_get(result, "(@ay)", &value);
  g_autoptr(GVariant) value_auto = value;
  std::vector<uint8_t> bytes = bytes_from_variant(value);
  send_characteristic_value_event(self, path, bytes);
  g_autoptr(FlValue) response_value = bytes_value(bytes);
  return success_response(response_value);
}

FlMethodResponse* write_characteristic_response(FlutterBluetoothPlugin* self, FlValue* args) {
  g_autoptr(GError) error = nullptr;
  std::string path = resolve_characteristic_path(self, args, nullptr, nullptr, &error);
  if (path.empty()) {
    return error_from_gerror(error != nullptr && error->code == G_IO_ERROR_INVALID_ARGUMENT
                                 ? kInvalidArgumentsCode
                                 : kOperationFailedCode,
                             error);
  }
  std::vector<uint8_t> bytes = get_byte_list_arg(args, "value");
  const std::string write_type = get_string_arg(args, "writeType").value_or("withResponse");
  const gchar* bluez_type = write_type == "withoutResponse" ? "command" : "request";
  if (!call_no_result(self, path.c_str(), kGattCharacteristicInterface, "WriteValue",
                      g_variant_new("(@ay@a{sv})", bytes_variant(bytes), options_with_type(bluez_type)),
                      &error)) {
    return error_from_gerror(kOperationFailedCode, error);
  }
  return success_response();
}

FlMethodResponse* set_notification_response(FlutterBluetoothPlugin* self, FlValue* args) {
  ensure_signal_subscriptions(self);
  g_autoptr(GError) error = nullptr;
  std::string path = resolve_characteristic_path(self, args, nullptr, nullptr, &error);
  if (path.empty()) {
    return error_from_gerror(error != nullptr && error->code == G_IO_ERROR_INVALID_ARGUMENT
                                 ? kInvalidArgumentsCode
                                 : kOperationFailedCode,
                             error);
  }
  const bool enable = get_bool_arg(args, "enable", false);
  const gchar* method = enable ? "StartNotify" : "StopNotify";
  if (!call_no_result(self, path.c_str(), kGattCharacteristicInterface, method,
                      g_variant_new("()"), &error)) {
    return error_from_gerror(kOperationFailedCode, error);
  }
  if (enable) {
    self->state->notifying_characteristics.insert(path);
  } else {
    self->state->notifying_characteristics.erase(path);
  }
  return success_response();
}

FlMethodResponse* read_descriptor_response(FlutterBluetoothPlugin* self, FlValue* args) {
  g_autoptr(GError) error = nullptr;
  std::string path = resolve_descriptor_path(self, args, nullptr, &error);
  if (path.empty()) {
    return error_from_gerror(error != nullptr && error->code == G_IO_ERROR_INVALID_ARGUMENT
                                 ? kInvalidArgumentsCode
                                 : kOperationFailedCode,
                             error);
  }
  GDBusConnection* bus = ensure_bus(self, &error);
  if (bus == nullptr) {
    return error_from_gerror(kBluetoothUnavailableCode, error);
  }
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      bus, kBluezName, path.c_str(), kGattDescriptorInterface, "ReadValue",
      g_variant_new("(@a{sv})", empty_options()), G_VARIANT_TYPE("(ay)"),
      G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
  if (result == nullptr) {
    return error_from_gerror(kOperationFailedCode, error);
  }
  GVariant* value = nullptr;
  g_variant_get(result, "(@ay)", &value);
  g_autoptr(GVariant) value_auto = value;
  std::vector<uint8_t> bytes = bytes_from_variant(value);
  send_descriptor_value_event(self, path, bytes);
  g_autoptr(FlValue) response_value = bytes_value(bytes);
  return success_response(response_value);
}

FlMethodResponse* write_descriptor_response(FlutterBluetoothPlugin* self, FlValue* args) {
  g_autoptr(GError) error = nullptr;
  std::string path = resolve_descriptor_path(self, args, nullptr, &error);
  if (path.empty()) {
    return error_from_gerror(error != nullptr && error->code == G_IO_ERROR_INVALID_ARGUMENT
                                 ? kInvalidArgumentsCode
                                 : kOperationFailedCode,
                             error);
  }
  std::vector<uint8_t> bytes = get_byte_list_arg(args, "value");
  if (!call_no_result(self, path.c_str(), kGattDescriptorInterface, "WriteValue",
                      g_variant_new("(@ay@a{sv})", bytes_variant(bytes), empty_options()),
                      &error)) {
    return error_from_gerror(kOperationFailedCode, error);
  }
  send_descriptor_value_event(self, path, bytes);
  return success_response();
}

FlMethodResponse* read_rssi_response(FlutterBluetoothPlugin* self, FlValue* args) {
  g_autoptr(GError) error = nullptr;
  std::string device_id = get_required_string_arg(args, "deviceId", &error);
  if (error != nullptr) {
    return error_from_gerror(kInvalidArgumentsCode, error);
  }
  int64_t rssi = 0;
  std::string path = resolve_device_path(self, device_id, nullptr);
  if (!path.empty()) {
    g_autoptr(GVariant) props = get_interface_properties(self, path.c_str(), kDeviceInterface, nullptr);
    rssi = int_property(props, "RSSI", 0);
  }
  g_autoptr(FlValue) event = fl_value_new_map();
  map_set_take(event, "type", fl_value_new_string("rssi"));
  map_set_take(event, "deviceId", fl_value_new_string(device_id.c_str()));
  map_set_take(event, "rssi", fl_value_new_int(rssi));
  send_event(self, event);

  g_autoptr(FlValue) result = fl_value_new_int(rssi);
  return success_response(result);
}

FlMethodResponse* request_mtu_response(FlutterBluetoothPlugin* self, FlValue* args) {
  std::string device_id = get_string_arg(args, "deviceId").value_or("");
  g_autoptr(FlValue) event = fl_value_new_map();
  map_set_take(event, "type", fl_value_new_string("mtu"));
  map_set_take(event, "deviceId", fl_value_new_string(device_id.c_str()));
  map_set_take(event, "mtu", fl_value_new_int(0));
  send_event(self, event);
  g_autoptr(FlValue) result = fl_value_new_int(0);
  return success_response(result);
}

FlMethodResponse* read_phy_response(FlValue* args) {
  g_autoptr(FlValue) result = fl_value_new_map();
  map_set_take(result, "deviceId", fl_value_new_string(get_string_arg(args, "deviceId").value_or("").c_str()));
  map_set_take(result, "txPhy", fl_value_new_string("unknown"));
  map_set_take(result, "rxPhy", fl_value_new_string("unknown"));
  return success_response(result);
}

FlMethodResponse* create_bond_response(FlutterBluetoothPlugin* self, FlValue* args) {
  g_autoptr(GError) error = nullptr;
  std::string device_id = get_required_string_arg(args, "deviceId", &error);
  if (error != nullptr) {
    return error_from_gerror(kInvalidArgumentsCode, error);
  }
  std::string path = resolve_device_path(self, device_id, &error);
  bool ok = false;
  if (!path.empty()) {
    ok = call_no_result(self, path.c_str(), kDeviceInterface, "Pair", g_variant_new("()"), &error);
    if (!ok && error != nullptr) {
      g_clear_error(&error);
    }
  }
  g_autoptr(FlValue) result = fl_value_new_bool(ok);
  return success_response(result);
}

FlMethodResponse* remove_bond_response(FlutterBluetoothPlugin* self, FlValue* args) {
  g_autoptr(GError) error = nullptr;
  std::string device_id = get_required_string_arg(args, "deviceId", &error);
  if (error != nullptr) {
    return error_from_gerror(kInvalidArgumentsCode, error);
  }
  std::string adapter = find_adapter_path(self, &error);
  if (error != nullptr) {
    g_clear_error(&error);
  }
  std::string path;
  if (!adapter.empty()) {
    path = resolve_device_path(self, device_id, &error);
  }
  bool ok = false;
  if (!adapter.empty() && !path.empty()) {
    ok = call_no_result(self, adapter.c_str(), kAdapterInterface, "RemoveDevice",
                        g_variant_new("(o)", path.c_str()), &error);
    if (!ok && error != nullptr) {
      g_clear_error(&error);
    }
  }
  g_autoptr(FlValue) result = fl_value_new_bool(ok);
  return success_response(result);
}

FlMethodResponse* unsupported_error(const gchar* message) {
  return error_response(kUnsupportedCode, message);
}

}  // namespace

G_DEFINE_TYPE(FlutterBluetoothPlugin, flutter_bluetooth_plugin, g_object_get_type())

static void flutter_bluetooth_plugin_handle_method_call(
    FlutterBluetoothPlugin* self, FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "getPlatformVersion") == 0) {
    response = get_platform_version_response();
  } else if (strcmp(method, "isSupported") == 0) {
    response = is_supported_response(self);
  } else if (strcmp(method, "getAdapterState") == 0) {
    response = adapter_state_response(self);
  } else if (strcmp(method, "getAdapterInfo") == 0) {
    response = adapter_info_response(self);
  } else if (strcmp(method, "isScanning") == 0) {
    response = is_scanning_response(self);
  } else if (strcmp(method, "setAdapterName") == 0) {
    response = set_adapter_name_response(self, args);
  } else if (strcmp(method, "checkPermissions") == 0 ||
             strcmp(method, "requestPermissions") == 0) {
    response = permission_map_response(self);
  } else if (strcmp(method, "requestEnable") == 0) {
    response = request_enable_response(self);
  } else if (strcmp(method, "openBluetoothSettings") == 0) {
    response = open_bluetooth_settings_response();
  } else if (strcmp(method, "startScan") == 0) {
    response = start_scan_response(self, args);
  } else if (strcmp(method, "stopScan") == 0) {
    stop_scan_internal(self);
    response = success_response();
  } else if (strcmp(method, "getBondedDevices") == 0) {
    g_autoptr(GError) error = nullptr;
    g_autoptr(FlValue) list = devices_list(self, true, false, {}, &error);
    response = success_response(list);
  } else if (strcmp(method, "getConnectedDevices") == 0) {
    g_autoptr(GError) error = nullptr;
    g_autoptr(FlValue) list = devices_list(self, false, true, get_string_list_arg(args, "serviceUuids"), &error);
    response = success_response(list);
  } else if (strcmp(method, "getDevice") == 0) {
    response = get_device_response(self, args);
  } else if (strcmp(method, "getDevices") == 0) {
    response = get_devices_response(self, args);
  } else if (strcmp(method, "connect") == 0) {
    response = connect_response(self, args);
  } else if (strcmp(method, "disconnect") == 0) {
    response = disconnect_response(self, args);
  } else if (strcmp(method, "getConnectionState") == 0) {
    response = connection_state_response(self, args);
  } else if (strcmp(method, "discoverServices") == 0) {
    response = discover_services_response(self, args);
  } else if (strcmp(method, "readCharacteristic") == 0) {
    response = read_characteristic_response(self, args);
  } else if (strcmp(method, "writeCharacteristic") == 0) {
    response = write_characteristic_response(self, args);
  } else if (strcmp(method, "setCharacteristicNotification") == 0) {
    response = set_notification_response(self, args);
  } else if (strcmp(method, "readDescriptor") == 0) {
    response = read_descriptor_response(self, args);
  } else if (strcmp(method, "writeDescriptor") == 0) {
    response = write_descriptor_response(self, args);
  } else if (strcmp(method, "readRssi") == 0) {
    response = read_rssi_response(self, args);
  } else if (strcmp(method, "requestMtu") == 0) {
    response = request_mtu_response(self, args);
  } else if (strcmp(method, "getMaximumWriteLength") == 0) {
    g_autoptr(FlValue) result = fl_value_new_int(0);
    response = success_response(result);
  } else if (strcmp(method, "setPreferredPhy") == 0) {
    response = success_response();
  } else if (strcmp(method, "readPhy") == 0) {
    response = read_phy_response(args);
  } else if (strcmp(method, "requestConnectionPriority") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(false);
    response = success_response(result);
  } else if (strcmp(method, "createBond") == 0) {
    response = create_bond_response(self, args);
  } else if (strcmp(method, "removeBond") == 0) {
    response = remove_bond_response(self, args);
  } else if (strcmp(method, "isPeripheralSupported") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(false);
    response = success_response(result);
  } else if (strcmp(method, "startAdvertising") == 0) {
    response = unsupported_error("BLE advertising/peripheral mode is not implemented on Linux.");
  } else if (strcmp(method, "stopAdvertising") == 0 ||
             strcmp(method, "clearGattServerServices") == 0 ||
             strcmp(method, "stopClassicServer") == 0 ||
             strcmp(method, "disconnectClassic") == 0) {
    response = success_response();
  } else if (strcmp(method, "setGattServerServices") == 0 ||
             strcmp(method, "updateLocalCharacteristicValue") == 0) {
    response = unsupported_error("Local GATT server APIs are not implemented on Linux.");
  } else if (strcmp(method, "notifyGattServerCharacteristic") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(false);
    response = success_response(result);
  } else if (strcmp(method, "connectClassic") == 0 ||
             strcmp(method, "startClassicServer") == 0 ||
             strcmp(method, "writeClassic") == 0) {
    response = unsupported_error("Classic Bluetooth RFCOMM is not implemented on Linux.");
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) respond_error = nullptr;
  if (!fl_method_call_respond(method_call, response, &respond_error)) {
    g_warning("Failed to send method response: %s",
              respond_error == nullptr ? "unknown error" : respond_error->message);
  }
}

FlMethodResponse* get_platform_version() { return get_platform_version_response(); }

static FlMethodErrorResponse* event_listen_cb(FlEventChannel*, FlValue*, gpointer user_data) {
  FlutterBluetoothPlugin* self = FLUTTER_BLUETOOTH_PLUGIN(user_data);
  self->state->emit_events = true;
  ensure_signal_subscriptions(self);
  send_adapter_state_event(self);
  return nullptr;
}

static FlMethodErrorResponse* event_cancel_cb(FlEventChannel*, FlValue*, gpointer user_data) {
  FlutterBluetoothPlugin* self = FLUTTER_BLUETOOTH_PLUGIN(user_data);
  self->state->emit_events = false;
  return nullptr;
}

static void flutter_bluetooth_plugin_dispose(GObject* object) {
  FlutterBluetoothPlugin* self = FLUTTER_BLUETOOTH_PLUGIN(object);
  if (self->state != nullptr) {
    stop_scan_internal(self);
    if (self->state->system_bus != nullptr) {
      if (self->state->interfaces_added_subscription != 0) {
        g_dbus_connection_signal_unsubscribe(self->state->system_bus,
                                             self->state->interfaces_added_subscription);
      }
      if (self->state->properties_changed_subscription != 0) {
        g_dbus_connection_signal_unsubscribe(self->state->system_bus,
                                             self->state->properties_changed_subscription);
      }
      g_object_unref(self->state->system_bus);
      self->state->system_bus = nullptr;
    }
    if (self->state->event_channel != nullptr) {
      g_object_unref(self->state->event_channel);
      self->state->event_channel = nullptr;
    }
    delete self->state;
    self->state = nullptr;
  }
  G_OBJECT_CLASS(flutter_bluetooth_plugin_parent_class)->dispose(object);
}

static void flutter_bluetooth_plugin_class_init(FlutterBluetoothPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = flutter_bluetooth_plugin_dispose;
}

static void flutter_bluetooth_plugin_init(FlutterBluetoothPlugin* self) {
  self->state = new PluginState();
}

static void method_call_cb(FlMethodChannel*, FlMethodCall* method_call, gpointer user_data) {
  FlutterBluetoothPlugin* plugin = FLUTTER_BLUETOOTH_PLUGIN(user_data);
  flutter_bluetooth_plugin_handle_method_call(plugin, method_call);
}

void flutter_bluetooth_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  FlutterBluetoothPlugin* plugin = FLUTTER_BLUETOOTH_PLUGIN(
      g_object_new(flutter_bluetooth_plugin_get_type(), nullptr));

  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      messenger, "flutter_bluetooth_plugin", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin), g_object_unref);

  plugin->state->event_channel = fl_event_channel_new(
      messenger, "flutter_bluetooth_plugin/events", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(plugin->state->event_channel, event_listen_cb,
                                       event_cancel_cb, g_object_ref(plugin),
                                       g_object_unref);

  g_object_unref(plugin);
}
