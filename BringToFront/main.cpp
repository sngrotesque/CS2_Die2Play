#include <windows.h>
#include <tlhelp32.h>
#include <string>
#include <string_view>
#include <cctype>

static std::wstring Utf8ToWide(std::string str)
{
    DWORD len = MultiByteToWideChar(CP_UTF8, 0, str.data(), -1, nullptr, 0);
    std::wstring wstr(len, '\0');

    MultiByteToWideChar(CP_UTF8, 0, str.data(), -1, wstr.data(), len);

    return wstr;
}

// 只返回第一个匹配到的进程 ID，未找到返回 0
static DWORD GetFirstProcessIdByName(std::wstring processName)
{
    DWORD pid = 0;

    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if(snapshot == INVALID_HANDLE_VALUE)
        return pid;

    PROCESSENTRY32W pe{};
    pe.dwSize = sizeof(pe);

    if(Process32FirstW(snapshot, &pe)) {
        do {
            if(lstrcmpW(pe.szExeFile, processName.c_str()) == 0) {
                pid = pe.th32ProcessID;
                break;  // 只要第一个匹配的进程
            }
        } while(Process32NextW(snapshot, &pe));
    }

    CloseHandle(snapshot);
    return pid;
}

struct EnumArgs {
    DWORD pid;  // 目标进程 ID
    int count;  // 已处理的窗口数
};

static BOOL CALLBACK EnumWindowsProc(HWND hwnd, LPARAM lParam)
{
    auto &args = *reinterpret_cast<EnumArgs *>(lParam);

    DWORD processId = 0;
    GetWindowThreadProcessId(hwnd, &processId);

    if(processId == args.pid) {
        // 恢复窗口
        if(IsIconic(hwnd))
            ShowWindow(hwnd, SW_RESTORE);

        // 允许抢前台
        AllowSetForegroundWindow(args.pid);

        // 抢前台
        SetForegroundWindow(hwnd);

        // 强制置顶一次
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);

        // 取消置顶
        SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);

        ++args.count;
    }

    return TRUE;
}

// 导出给 Dart 使用的 C 函数
extern "C" __declspec(dllexport) bool BringWindowToFront(const char *processName)
{
    if(!processName || *processName == '\0')
        return false;

    DWORD pid = GetFirstProcessIdByName(Utf8ToWide(processName));
    if(pid == 0) {
        return false;
    }

    // 枚举所有顶层窗口，对匹配进程的窗口执行置顶
    EnumArgs args{pid, 0};
    EnumWindows(EnumWindowsProc, reinterpret_cast<LPARAM>(&args));

    return args.count > 0;  // 至少处理了一个窗口即为成功
}