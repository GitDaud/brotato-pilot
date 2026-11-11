#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>

/* Local game-window hooks only: reject activation before it can occur and
   keep top-level game windows outside the interactive desktop's bounds. */
static HMODULE module;
static HHOOK cbt_hook, message_hook;

static LRESULT CALLBACK cbt(int code, WPARAM w, LPARAM l) {
    if (code == HCBT_ACTIVATE || code == HCBT_SETFOCUS) return 1;
    if (code == HCBT_CREATEWND) {
        CBT_CREATEWNDW *event = (CBT_CREATEWNDW *)l;
        CREATESTRUCTW *window = event->lpcs;
        if (!(window->style & WS_CHILD)) {
            window->dwExStyle |= WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW;
            window->x = -24000;
            window->y = -24000;
        }
    }
    return CallNextHookEx(cbt_hook, code, w, l);
}

static LRESULT CALLBACK message(int code, WPARAM w, LPARAM l) {
    if (code >= 0) {
        CWPSTRUCT *event = (CWPSTRUCT *)l;
        if (event->message == WM_STYLECHANGING && (int)event->wParam == GWL_EXSTYLE) {
            STYLESTRUCT *style = (STYLESTRUCT *)event->lParam;
            style->styleNew = (style->styleNew | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
        }
        if (event->message == WM_WINDOWPOSCHANGING &&
            !(GetWindowLongPtrW(event->hwnd, GWL_STYLE) & WS_CHILD)) {
            WINDOWPOS *position = (WINDOWPOS *)event->lParam;
            position->x = -24000;
            position->y = -24000;
            position->flags = (position->flags & ~SWP_NOMOVE) | SWP_NOACTIVATE;
        }
    }
    return CallNextHookEx(message_hook, code, w, l);
}

__declspec(dllexport) void CALLBACK InitializeGuard(ULONG_PTR ignored) {
    (void)ignored;
    SetProcessDPIAware();
    MSG queued;
    PeekMessageW(&queued, NULL, WM_USER, WM_USER, PM_NOREMOVE);
    DWORD primary = GetCurrentThreadId();
    cbt_hook = SetWindowsHookExW(WH_CBT, cbt, module, primary);
    message_hook = SetWindowsHookExW(WH_CALLWNDPROC, message, module, primary);
    if (!cbt_hook || !message_hook) ExitProcess(3);
    wchar_t name[96];
    wsprintfW(name, L"Local\\BrotatoCaptureGuard-%lu", GetCurrentProcessId());
    CreateEventW(NULL, TRUE, TRUE, name);
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        module = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}
