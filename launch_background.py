"""Launch the actual native game window on the normal desktop, as requested."""
import ctypes,json,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent
GAME=Path(r'F:\SteamLibrary\steamapps\common\Brotato')
def main():
 # Refuse duplicate workers: simultaneous games overwrite the shared evidence files.
 previous=ROOT/'run/background-launch.json'
 if previous.exists():
  try:
   prior=json.loads(previous.read_text())
   k=ctypes.WinDLL('kernel32',use_last_error=True)
   k.OpenProcess.argtypes=[ctypes.c_uint32,ctypes.c_int,ctypes.c_uint32];k.OpenProcess.restype=ctypes.c_void_p
   k.CloseHandle.argtypes=[ctypes.c_void_p]
   k.QueryFullProcessImageNameW.argtypes=[ctypes.c_void_p,ctypes.c_uint32,ctypes.c_wchar_p,ctypes.POINTER(ctypes.c_uint32)]
   handle=k.OpenProcess(0x1000,False,int(prior['pid']))
   if handle:
    try:
     size=ctypes.c_uint32(32768);name=ctypes.create_unicode_buffer(size.value)
     if k.QueryFullProcessImageNameW(handle,0,name,ctypes.byref(size)) and Path(name.value).resolve()==(GAME/'Brotato.exe').resolve():
      raise RuntimeError('Existing Brotato game is still running; review settlement and stop it before deployment.')
    finally:k.CloseHandle(handle)
  except (ValueError,KeyError,json.JSONDecodeError):pass
 os.environ.update(SteamAppId='1942280',SteamGameId='1942280')
 with (ROOT/'run/capture-engine.log').open('wb') as log:
  process=subprocess.Popen([str(GAME/'Brotato.exe'),'--main-pack',str(GAME/'CodexPilot.pck'),'--windowed','--resolution','1920x1080','--audio-driver','Dummy','--log-file',str(ROOT/'run/startup.log')],cwd=GAME,stdout=log,stderr=log)
 result={'pid':process.pid,'desktop':'WinSta0\\Default','display':'native_game_window','capture':'windows_graphics_capture_hwnd','requested_resolution':[1920,1080],'input_isolated':False}
 (ROOT/'run/background-launch.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
if __name__=='__main__':main()
