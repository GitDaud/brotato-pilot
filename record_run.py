"""Per-run recording of the exact game's HWND using Windows Graphics Capture."""
import argparse,ctypes,json,os,shutil,subprocess,time
from ctypes import wintypes as W
from pathlib import Path
ROOT=Path(__file__).resolve().parent
OUTPUT=ROOT/'recordings'
def write_status(path,**values):path.write_text(json.dumps(values,ensure_ascii=False,indent=2),encoding='utf-8')
def game_window(pid):
 u=ctypes.WinDLL('user32');u.GetWindowThreadProcessId.argtypes=[W.HWND,ctypes.POINTER(W.DWORD)];u.IsWindowVisible.argtypes=[W.HWND];u.GetClientRect.argtypes=[W.HWND,ctypes.POINTER(W.RECT)]
 found=[]
 callback=ctypes.WINFUNCTYPE(W.BOOL,W.HWND,W.LPARAM)
 def visit(hwnd,_):
  owner=W.DWORD();u.GetWindowThreadProcessId(hwnd,ctypes.byref(owner))
  if owner.value==pid and u.IsWindowVisible(hwnd):
   rect=W.RECT();u.GetClientRect(hwnd,ctypes.byref(rect))
   if rect.right>100 and rect.bottom>100:found.append((rect.right*rect.bottom,int(hwnd)))
  return True
 u.EnumWindows(callback(visit),0)
 return max(found)[1] if found else None

def record(run_id,game_pid,duration=None):
 OUTPUT.mkdir(exist_ok=True)
 if not run_id or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_' for c in run_id):raise ValueError('Invalid run ID')
 video=OUTPUT/(run_id+'.mp4');status=OUTPUT/(run_id+'.json');stop=OUTPUT/(run_id+'.stop');logpath=OUTPUT/(run_id+'.ffmpeg.log')
 if video.exists():raise FileExistsError(video)
 k=ctypes.WinDLL('kernel32');k.OpenProcess.restype=W.HANDLE;k.WaitForSingleObject.argtypes=[W.HANDLE,W.DWORD];k.CloseHandle.argtypes=[W.HANDLE]
 handle=k.OpenProcess(0x100000,False,game_pid)
 if not handle:raise RuntimeError('Game process unavailable')
 started=time.monotonic();hwnd=None
 while time.monotonic()-started<30 and k.WaitForSingleObject(handle,0)!=0:
  hwnd=game_window(game_pid)
  if hwnd:break
  time.sleep(.1)
 if not hwnd:raise RuntimeError('No visible window belonging to game PID')
 source=f'gfxcapture=hwnd={hwnd}:capture_cursor=0:capture_border=0:display_border=0:max_framerate=60'
 cmd=[shutil.which('ffmpeg') or 'ffmpeg','-hide_banner','-loglevel','warning','-y','-f','lavfi','-i',source,'-an','-vf','hwdownload,format=bgra,format=yuv420p','-c:v','h264_nvenc','-preset','p2','-cq','22','-b:v','0','-pix_fmt','yuv420p','-r','60','-fps_mode','cfr','-g','120','-movflags','+frag_keyframe+empty_moov+default_base_moof',str(video)]
 # A modern capture build may require a newer NVENC driver. Keep its HWND
 # capture, and optionally pipe frames to a compatible NVENC executable.
 compatible=Path(os.environ.get('BROTATO_NVENC_FFMPEG',str(ROOT/'tools/ffmpeg-compatible/ffmpeg-8.0-full_build/bin/ffmpeg.exe')))
 capture_cmd=None
 if compatible.is_file():
  capture_cmd=cmd[:cmd.index('-an')]+['-vf','hwdownload,format=bgra,scale=1920:1080','-r','60','-f','rawvideo','pipe:1']
  cmd=[str(compatible),'-hide_banner','-loglevel','warning','-y','-f','rawvideo','-pixel_format','bgra','-video_size','1920x1080','-framerate','60','-i','pipe:0','-an','-vf','format=yuv420p']+cmd[cmd.index('-c:v'):]
 reason='encoder_exit'
 base=dict(video=str(video),game_pid=game_pid,hwnd=hwnd,capture_source='windows_graphics_capture_hwnd',audio=False,target_fps=60,encoder_executable=cmd[0],piped_capture=capture_cmd is not None)
 capture_proc=None
 proc=None
 try:
  with logpath.open('w',encoding='utf-8') as log:
   if capture_cmd:
    capture_proc=subprocess.Popen(capture_cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log,creationflags=subprocess.CREATE_NO_WINDOW)
   proc=subprocess.Popen(cmd,stdin=capture_proc.stdout if capture_proc else subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=log,creationflags=subprocess.CREATE_NO_WINDOW)
   if capture_proc:capture_proc.stdout.close()
   write_status(status,state='starting',pid=proc.pid,**base)
   started=time.monotonic()
   while proc.poll() is None:
    if capture_proc and capture_proc.poll() is not None:reason='capture_exit';break
    if stop.exists():reason='run_end';break
    if k.WaitForSingleObject(handle,0)==0:reason='game_closed';break
    if duration and time.monotonic()-started>=duration:reason='test_duration';break
    if video.exists() and video.stat().st_size>0:write_status(status,state='recording',pid=proc.pid,**base)
    time.sleep(.5)
   control=capture_proc or proc
   if control.poll() is None:
    try:control.stdin.write(b'q\n');control.stdin.flush()
    except OSError:pass
    try:control.wait(timeout=15)
    except subprocess.TimeoutExpired:control.kill();control.wait();reason+='_forced'
   try:proc.wait(timeout=15)
   except subprocess.TimeoutExpired:proc.kill();proc.wait();reason+='_encoder_forced'
   control.stdin.close()
  result=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration,size:stream=width,height,avg_frame_rate,codec_name','-of','json',str(video)],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
  info=json.loads(result.stdout) if result.returncode==0 else {}
  write_status(status,state='saved' if proc.returncode==0 and info else 'failed',returncode=proc.returncode,reason=reason,probe=info,elapsed_seconds=time.monotonic()-started,**base)
 finally:
  for worker in [capture_proc,proc]:
   if worker and worker.poll() is None:worker.kill();worker.wait()
  k.CloseHandle(handle);stop.unlink(missing_ok=True)
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('run_id');parser.add_argument('game_pid',type=int);parser.add_argument('--duration',type=float);a=parser.parse_args()
 try:record(a.run_id,a.game_pid,a.duration)
 except Exception as exc:
  OUTPUT.mkdir(exist_ok=True);write_status(OUTPUT/(a.run_id+'.json'),state='failed',error=str(exc));raise
