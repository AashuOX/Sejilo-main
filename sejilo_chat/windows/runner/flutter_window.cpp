#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      result.data(), size);
  return result;
}

std::string MapString(const flutter::EncodableMap& map,
                      const std::string& key,
                      const std::string& fallback) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) return fallback;
  const auto* value = std::get_if<std::string>(&iterator->second);
  return value == nullptr ? fallback : *value;
}

}  // namespace

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
  notification_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "sejilo/notifications",
          &flutter::StandardMethodCodec::GetInstance());
  notification_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "showIncoming") {
          result->NotImplemented();
          return;
        }
        const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("invalid_arguments", "Notification arguments are missing.");
          return;
        }
        ShowIncomingNotification(MapString(*arguments, "title", "SejiloChat"),
                                 MapString(*arguments, "body", "New nearby message"));
        result->Success();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  if (notification_icon_added_) {
    NOTIFYICONDATAW data{};
    data.cbSize = sizeof(data);
    data.hWnd = GetHandle();
    data.uID = 1;
    Shell_NotifyIconW(NIM_DELETE, &data);
    notification_icon_added_ = false;
  }
  notification_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::ShowIncomingNotification(const std::string& title,
                                             const std::string& body) {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = 1;
  data.uFlags = NIF_ICON | NIF_TIP | NIF_INFO;
  data.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(data.szTip, L"SejiloChat");
  const std::wstring wide_title = Utf8ToWide(title);
  const std::wstring wide_body = Utf8ToWide(body);
  wcsncpy_s(data.szInfoTitle, wide_title.c_str(), _TRUNCATE);
  wcsncpy_s(data.szInfo, wide_body.c_str(), _TRUNCATE);
  data.dwInfoFlags = NIIF_INFO | NIIF_RESPECT_QUIET_TIME;
  if (!notification_icon_added_) {
    notification_icon_added_ = Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
    data.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &data);
  }
  Shell_NotifyIconW(NIM_MODIFY, &data);
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
