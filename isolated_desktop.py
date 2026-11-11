"""Keep a private desktop alive for the complete lifetime of the native game."""
import ctypes
from ctypes import wintypes as W
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parent
GAME = Path(r'F:\SteamLibrary\steamapps\common\Brotato')


def start(profile, speed, record=False):
    token = uuid.uuid4().hex
    with (ROOT/'run/isolated-launch.log').open('wb') as log:
        worker = subprocess.Popen([sys.executable, str(Path(__file__)), '--worker', profile,
                                   str(speed), token, str(int(record))], cwd=ROOT, stdout=log, stderr=log,
                                  creationflags=subprocess.CREATE_NO_WINDOW)
    deadline = time.monotonic()+15
    while time.monotonic() < deadline:
        try:
            result = json.loads((ROOT/'run/background-launch.json').read_text())
            if result.get('launch_token') == token:
                print(json.dumps(result))
                return
        except (OSError, ValueError):
            pass
        if worker.poll() is not None:
            raise RuntimeError('Isolated launcher exited; inspect run/isolated-launch.log.')
        time.sleep(.1)
    raise TimeoutError('Isolated launch receipt not received.')


def worker(profile, speed, token, record=False):
    user = ctypes.WinDLL('user32', use_last_error=True)
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    user.GetForegroundWindow.restype = W.HWND
    user.CreateDesktopW.argtypes = [W.LPCWSTR,W.LPCWSTR,ctypes.c_void_p,W.DWORD,W.DWORD,ctypes.c_void_p]
    user.CreateDesktopW.restype = W.HANDLE
    user.CloseDesktop.argtypes = [W.HANDLE]
    kernel.CloseHandle.argtypes = [W.HANDLE]
    kernel.WaitForSingleObject.argtypes = [W.HANDLE,W.DWORD]

    class StartupInfo(ctypes.Structure):
        _fields_ = [('cb',W.DWORD),('lpReserved',W.LPWSTR),('lpDesktop',W.LPWSTR),
                    ('lpTitle',W.LPWSTR),('dwX',W.DWORD),('dwY',W.DWORD),
                    ('dwXSize',W.DWORD),('dwYSize',W.DWORD),('dwXCountChars',W.DWORD),
                    ('dwYCountChars',W.DWORD),('dwFillAttribute',W.DWORD),('dwFlags',W.DWORD),
                    ('wShowWindow',W.WORD),('cbReserved2',W.WORD),
                    ('lpReserved2',ctypes.POINTER(ctypes.c_byte)),('hStdInput',W.HANDLE),
                    ('hStdOutput',W.HANDLE),('hStdError',W.HANDLE)]

    class ProcessInfo(ctypes.Structure):
        _fields_ = [('hProcess',W.HANDLE),('hThread',W.HANDLE),
                    ('dwProcessId',W.DWORD),('dwThreadId',W.DWORD)]

    kernel.CreateProcessW.argtypes = [W.LPCWSTR,W.LPWSTR,ctypes.c_void_p,ctypes.c_void_p,
                                     W.BOOL,W.DWORD,ctypes.c_void_p,W.LPCWSTR,
                                     ctypes.POINTER(StartupInfo),ctypes.POINTER(ProcessInfo)]
    foreground = user.GetForegroundWindow()
    desktop = user.CreateDesktopW('BrotatoPilot',None,None,0,0x01ff,None)
    if not desktop:
        raise ctypes.WinError(ctypes.get_last_error())
    process = ProcessInfo()
    try:
        os.environ.update(SteamAppId='1942280',SteamGameId='1942280')
        startup = StartupInfo()
        startup.cb = ctypes.sizeof(startup)
        startup.lpDesktop = 'WinSta0\\BrotatoPilot'
        startup.dwFlags = 1
        startup.wShowWindow = 4
        command = ctypes.create_unicode_buffer(subprocess.list2cmdline([
            str(GAME/'Brotato.exe'),'--main-pack',str(GAME/'CodexPilot.pck'),
            '--windowed','--resolution','1920x1080','--audio-driver','Dummy',
            '--pilot-profile='+profile,'--pilot-speed='+str(speed),
            '--pilot-record='+str(int(record)), '--pilot-private-record='+str(int(record))]))
        if not kernel.CreateProcessW(None,command,None,None,False,0x08000000,None,
                                     str(GAME),ctypes.byref(startup),ctypes.byref(process)):
            raise ctypes.WinError(ctypes.get_last_error())
        kernel.CloseHandle(process.hThread)
        result = dict(pid=process.dwProcessId, profile=profile, speed=int(speed),
                      desktop='WinSta0\\BrotatoPilot',input_isolated=True,
                      recording=record,focus_unchanged=user.GetForegroundWindow()==foreground,
                      launch_token=token)
        target = ROOT/'run/background-launch.json'
        temporary = target.with_suffix('.tmp')
        temporary.write_text(json.dumps(result,indent=2))
        temporary.replace(target)
        kernel.WaitForSingleObject(process.hProcess,0xFFFFFFFF)
    finally:
        if process.hProcess:
            kernel.CloseHandle(process.hProcess)
        user.CloseDesktop(desktop)


if __name__ == '__main__':
    if len(sys.argv) == 6 and sys.argv[1] == '--worker':
        worker(sys.argv[2],int(sys.argv[3]),sys.argv[4],sys.argv[5]=='1')
    else:
        raise SystemExit('Use launch_background.py --isolated.')
