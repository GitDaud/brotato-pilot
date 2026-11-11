"""Start only the game with activation blocked and its window off-screen."""
import ctypes
from ctypes import wintypes as W
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parent
GAME = Path(r'F:\SteamLibrary\steamapps\common\Brotato')


class StartupInfo(ctypes.Structure):
    _fields_ = [('cb', W.DWORD), ('lpReserved', W.LPWSTR), ('lpDesktop', W.LPWSTR),
                ('lpTitle', W.LPWSTR), ('dwX', W.DWORD), ('dwY', W.DWORD),
                ('dwXSize', W.DWORD), ('dwYSize', W.DWORD), ('dwXCountChars', W.DWORD),
                ('dwYCountChars', W.DWORD), ('dwFillAttribute', W.DWORD), ('dwFlags', W.DWORD),
                ('wShowWindow', W.WORD), ('cbReserved2', W.WORD),
                ('lpReserved2', ctypes.POINTER(ctypes.c_byte)), ('hStdInput', W.HANDLE),
                ('hStdOutput', W.HANDLE), ('hStdError', W.HANDLE)]


class ProcessInfo(ctypes.Structure):
    _fields_ = [('hProcess', W.HANDLE), ('hThread', W.HANDLE),
                ('dwProcessId', W.DWORD), ('dwThreadId', W.DWORD)]


class ModuleEntry(ctypes.Structure):
    _fields_ = [('dwSize', W.DWORD), ('th32ModuleID', W.DWORD), ('th32ProcessID', W.DWORD),
                ('GlblcntUsage', W.DWORD), ('ProccntUsage', W.DWORD),
                ('modBaseAddr', ctypes.c_void_p), ('modBaseSize', W.DWORD), ('hModule', W.HMODULE),
                ('szModule', W.WCHAR * 256), ('szExePath', W.WCHAR * 260)]


def start(profile, speed):
    guard = ROOT / 'tools/compiled/capture_window_guard.dll'
    if not guard.is_file():
        raise FileNotFoundError(guard)
    k = ctypes.WinDLL('kernel32', use_last_error=True)
    u = ctypes.WinDLL('user32', use_last_error=True)
    u.GetForegroundWindow.restype = W.HWND
    k.CreateProcessW.argtypes = [W.LPCWSTR, W.LPWSTR, ctypes.c_void_p, ctypes.c_void_p,
                                W.BOOL, W.DWORD, ctypes.c_void_p, W.LPCWSTR,
                                ctypes.POINTER(StartupInfo), ctypes.POINTER(ProcessInfo)]
    k.VirtualAllocEx.argtypes = [W.HANDLE, ctypes.c_void_p, ctypes.c_size_t, W.DWORD, W.DWORD]
    k.VirtualAllocEx.restype = ctypes.c_void_p
    k.WriteProcessMemory.argtypes = [W.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                    ctypes.c_size_t, ctypes.c_void_p]
    k.GetModuleHandleW.argtypes = [W.LPCWSTR]
    k.GetModuleHandleW.restype = W.HMODULE
    k.GetProcAddress.argtypes = [W.HMODULE, ctypes.c_char_p]
    k.GetProcAddress.restype = ctypes.c_void_p
    k.CreateRemoteThread.argtypes = [W.HANDLE, ctypes.c_void_p, ctypes.c_size_t,
                                    ctypes.c_void_p, ctypes.c_void_p, W.DWORD, ctypes.c_void_p]
    k.CreateRemoteThread.restype = W.HANDLE
    k.OpenEventW.argtypes = [W.DWORD, W.BOOL, W.LPCWSTR]
    k.OpenEventW.restype = W.HANDLE
    k.WaitForSingleObject.argtypes = [W.HANDLE, W.DWORD]
    k.ResumeThread.argtypes = [W.HANDLE]
    k.CloseHandle.argtypes = [W.HANDLE]
    k.GetExitCodeThread.argtypes = [W.HANDLE, ctypes.POINTER(W.DWORD)]
    k.CreateToolhelp32Snapshot.argtypes = [W.DWORD, W.DWORD]
    k.CreateToolhelp32Snapshot.restype = W.HANDLE
    k.Module32FirstW.argtypes = [W.HANDLE, ctypes.POINTER(ModuleEntry)]
    k.Module32NextW.argtypes = [W.HANDLE, ctypes.POINTER(ModuleEntry)]
    k.QueueUserAPC.argtypes = [ctypes.c_void_p, W.HANDLE, ctypes.c_size_t]
    k.TerminateProcess.argtypes = [W.HANDLE, W.UINT]
    k.VirtualFreeEx.argtypes = [W.HANDLE, ctypes.c_void_p, ctypes.c_size_t, W.DWORD]
    os.environ.update(SteamAppId='1942280', SteamGameId='1942280', BROTATO_CAPTURE_SOFTWARE='1')
    startup = StartupInfo()
    startup.cb = ctypes.sizeof(startup)
    startup.lpDesktop = 'WinSta0\\Default'
    startup.dwFlags = 1
    startup.wShowWindow = 4
    process = ProcessInfo()
    before = u.GetForegroundWindow()
    command = ctypes.create_unicode_buffer(subprocess.list2cmdline([
        str(GAME/'Brotato.exe'), '--main-pack', str(GAME/'CodexPilot.pck'), '--windowed', '--borderless',
        '--resolution', '1920x1080', '--audio-driver', 'Dummy', '--pilot-profile='+profile,
        '--pilot-speed='+str(speed), '--pilot-record=1']))
    if not k.CreateProcessW(None, command, None, None, False, 0x08000004, None,
                            str(GAME), ctypes.byref(startup), ctypes.byref(process)):
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        path = ctypes.create_unicode_buffer(str(guard))
        remote = k.VirtualAllocEx(process.hProcess, None, ctypes.sizeof(path), 0x3000, 4)
        if not remote or not k.WriteProcessMemory(process.hProcess, remote, path, ctypes.sizeof(path), None):
            raise ctypes.WinError(ctypes.get_last_error())
        loader = k.GetProcAddress(k.GetModuleHandleW('kernel32.dll'), b'LoadLibraryW')
        thread = k.CreateRemoteThread(process.hProcess, None, 0, loader, remote, 0, None)
        if not thread or k.WaitForSingleObject(thread, 10000) != 0:
            raise RuntimeError('Window guard load timed out')
        loaded = W.DWORD()
        k.GetExitCodeThread(thread, ctypes.byref(loaded))
        k.CloseHandle(thread)
        if not loaded.value:
            raise RuntimeError('Window guard DLL failed to load')
        k.VirtualFreeEx(process.hProcess, remote, 0, 0x8000)
        snapshot = k.CreateToolhelp32Snapshot(0x18, process.dwProcessId)
        entry = ModuleEntry()
        entry.dwSize = ctypes.sizeof(entry)
        remote_base = None
        found = k.Module32FirstW(snapshot, ctypes.byref(entry))
        while found:
            if entry.szModule.lower() == guard.name.lower():
                remote_base = entry.modBaseAddr
                break
            found = k.Module32NextW(snapshot, ctypes.byref(entry))
        k.CloseHandle(snapshot)
        if not remote_base:
            raise RuntimeError('Loaded window guard module not found')
        local_guard = ctypes.WinDLL(str(guard))
        offset = k.GetProcAddress(local_guard._handle, b'InitializeGuard') - local_guard._handle
        if not k.QueueUserAPC(remote_base + offset, process.hThread, 0):
            raise ctypes.WinError(ctypes.get_last_error())
        # A queued APC runs before this newly-created primary thread's entry point.
        k.ResumeThread(process.hThread)
        ready = None
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            ready = k.OpenEventW(0x100000, False, 'Local\\BrotatoCaptureGuard-'+str(process.dwProcessId))
            if ready:
                break
            time.sleep(.05)
        if not ready:
            raise RuntimeError('Window activation guard did not initialize for PID '+str(process.dwProcessId))
        k.CloseHandle(ready)
        receipt = dict(pid=process.dwProcessId, profile=profile, speed=speed,
                       desktop='WinSta0\\Default', recording=True,
                       capture='windows_graphics_capture_hwnd', offscreen=True,
                       activation_guard=True, mouse_transparent=True,
                       focus_unchanged=u.GetForegroundWindow()==before)
        (ROOT/'run/background-launch.json').write_text(json.dumps(receipt, indent=2))
        print(json.dumps(receipt))
    except Exception:
        k.TerminateProcess(process.hProcess, 1)
        raise
    finally:
        k.CloseHandle(process.hThread)
        k.CloseHandle(process.hProcess)
