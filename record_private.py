"""Encode only engine viewport pixels from a private desktop, at wall-clock speed."""
import argparse
import json
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / 'recordings'
FRAME_BYTES = 1280 * 720 * 3


def record(run_id, game_pid):
    if not run_id or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_' for c in run_id):
        raise ValueError('Invalid run ID')
    OUTPUT.mkdir(exist_ok=True)
    video = OUTPUT / (run_id + '.mp4')
    status = OUTPUT / (run_id + '.json')
    port_file = OUTPUT / (run_id + '.port.json')
    stop = OUTPUT / (run_id + '.stop')
    if video.exists():
        raise FileExistsError(video)
    base = dict(video=str(video), game_pid=game_pid, capture_source='engine_viewport_rgb_tcp',
                width=1280, height=720, target_fps=30, audio=False, replay=True)

    def report(state, **extra):
        temp = status.with_suffix('.tmp')
        temp.write_text(json.dumps(dict(base, state=state, **extra), indent=2), encoding='utf-8')
        temp.replace(status)

    compatible = ROOT / 'tools/ffmpeg-compatible/ffmpeg-8.0-full_build/bin/ffmpeg.exe'
    ffmpeg = str(compatible) if compatible.is_file() else shutil.which('ffmpeg')
    cmd = [ffmpeg, '-hide_banner', '-loglevel', 'warning', '-n', '-f', 'rawvideo',
           '-pixel_format', 'rgb24', '-video_size', '1280x720', '-framerate', '30', '-i', 'pipe:0',
           '-an', '-c:v', 'h264_nvenc', '-preset', 'p2', '-cq', '21', '-b:v', '0',
           '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(video)]
    proc = None
    received = written = 0
    first_ms = last_ms = None
    previous = None
    started = time.monotonic()
    try:
        with socket.socket() as server, (OUTPUT / (run_id + '.ffmpeg.log')).open('w') as log:
            server.bind(('127.0.0.1', 0))
            server.listen(1)
            server.settimeout(30)
            port_file.write_text(json.dumps({'port': server.getsockname()[1]}))
            report('starting')
            conn, _ = server.accept()
            proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                    stderr=log, creationflags=subprocess.CREATE_NO_WINDOW)
            with conn:
                conn.settimeout(1)
                buffer = bytearray()
                expected = None
                timestamp = None
                while time.monotonic() - started < 240:
                    try:
                        chunk = conn.recv(1024 * 1024)
                        if not chunk:
                            break
                        buffer.extend(chunk)
                    except socket.timeout:
                        if stop.exists():
                            break
                        continue
                    while True:
                        if expected is None:
                            if len(buffer) < 8:
                                break
                            timestamp, expected = struct.unpack('<II', buffer[:8])
                            del buffer[:8]
                            if expected != FRAME_BYTES:
                                raise ValueError('Unexpected viewport frame size')
                        if len(buffer) < expected:
                            break
                        pixels = bytes(buffer[:expected])
                        del buffer[:expected]
                        expected = None
                        received += 1
                        if first_ms is None:
                            first_ms = timestamp
                        target = round((timestamp - first_ms) * 30 / 1000)
                        while written < target:
                            proc.stdin.write(previous if previous is not None else pixels)
                            written += 1
                        if written == target:
                            proc.stdin.write(pixels)
                            written += 1
                        previous = pixels
                        last_ms = timestamp
                        if received % 30 == 0:
                            report('recording', received_frames=received, encoded_frames=written)
                    if stop.exists():
                        break
            proc.stdin.close()
            proc.wait(timeout=30)
            if not received:
                raise RuntimeError('No viewport frames received')
            if proc.returncode:
                raise RuntimeError('Encoder failed; inspect FFmpeg log')
        probe = subprocess.run(['ffprobe', '-v', 'error', '-show_entries',
                                'format=duration,size:stream=width,height,avg_frame_rate,codec_name',
                                '-of', 'json', str(video)], capture_output=True, text=True,
                               creationflags=subprocess.CREATE_NO_WINDOW, check=True)
        report('saved', received_frames=received, encoded_frames=written,
               source_seconds=(last_ms-first_ms)/1000, probe=json.loads(probe.stdout))
    except Exception as exc:
        report('failed', error=str(exc), received_frames=received)
        raise
    finally:
        if proc and proc.poll() is None:
            proc.kill()
            proc.wait()
        port_file.unlink(missing_ok=True)
        stop.unlink(missing_ok=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('run_id')
    parser.add_argument('game_pid', type=int)
    args = parser.parse_args()
    record(args.run_id, args.game_pid)
