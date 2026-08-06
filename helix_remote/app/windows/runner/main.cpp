#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

void SetRegistryString(HKEY key, const wchar_t* name, const std::wstring& value) {
  RegSetValueExW(
      key,
      name,
      0,
      REG_SZ,
      reinterpret_cast<const BYTE*>(value.c_str()),
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
}

// Register per-user so the app does not need elevation. A `helix://` URI is
// passed back to this executable as its first argument, which Dart receives
// through set_dart_entrypoint_arguments below.
void RegisterHelixUriScheme() {
  wchar_t executable_path[MAX_PATH];
  const DWORD length = GetModuleFileNameW(nullptr, executable_path, MAX_PATH);
  if (length == 0 || length == MAX_PATH) {
    return;
  }

  HKEY protocol_key;
  if (RegCreateKeyExW(
          HKEY_CURRENT_USER,
          L"Software\\Classes\\helix",
          0,
          nullptr,
          0,
          KEY_SET_VALUE,
          nullptr,
          &protocol_key,
          nullptr) != ERROR_SUCCESS) {
    return;
  }
  SetRegistryString(protocol_key, L"", L"URL:Helix Remote Protocol");
  SetRegistryString(protocol_key, L"URL Protocol", L"");
  RegCloseKey(protocol_key);

  HKEY command_key;
  if (RegCreateKeyExW(
          HKEY_CURRENT_USER,
          L"Software\\Classes\\helix\\shell\\open\\command",
          0,
          nullptr,
          0,
          KEY_SET_VALUE,
          nullptr,
          &command_key,
          nullptr) == ERROR_SUCCESS) {
    SetRegistryString(
        command_key,
        L"",
        L"\"" + std::wstring(executable_path) + L"\" \"%1\"");
    RegCloseKey(command_key);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  RegisterHelixUriScheme();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Helix Remote", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
