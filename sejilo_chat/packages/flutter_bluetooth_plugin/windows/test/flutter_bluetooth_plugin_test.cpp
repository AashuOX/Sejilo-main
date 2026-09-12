#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <chrono>
#include <memory>
#include <future>
#include <string>
#include <variant>

#include "flutter_bluetooth_plugin.h"

namespace flutter_bluetooth_plugin {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

}  // namespace

TEST(FlutterBluetoothPlugin, GetPlatformVersion) {
  FlutterBluetoothPlugin plugin;
  // Native method dispatch is asynchronous so slow GATT operations never
  // block Flutter's Windows platform thread.
  auto response = std::make_shared<std::promise<std::string>>();
  auto response_future = response->get_future();
  plugin.HandleMethodCall(
      MethodCall("getPlatformVersion", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          [response](const EncodableValue* result) {
            response->set_value(std::get<std::string>(*result));
          },
          [response](const std::string&, const std::string&,
                     const EncodableValue*) { response->set_value(""); },
          [response]() { response->set_value(""); }));

  ASSERT_EQ(response_future.wait_for(std::chrono::seconds(5)),
            std::future_status::ready);
  const std::string result_string = response_future.get();

  // Since the exact string varies by host, just ensure that it's a string
  // with the expected format.
  EXPECT_TRUE(result_string.rfind("Windows ", 0) == 0);
}

}  // namespace test
}  // namespace flutter_bluetooth_plugin
