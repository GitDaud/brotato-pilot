"""Run the next character at Danger 5 on its own branch, then stop for review/merge.

Only reads native saves. Progress and unlocks must be earned by the game.
Create run/campaign-stop to stop; restarting requires deleting that stop file.
"""
import ctypes
import json
import subprocess
import sys
import time
from ctypes import wintypes as W
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RUN = ROOT / 'run'
SAVE = Path.home() / 'AppData/Roaming/Brotato/76561198851811283/save_v3_1.json'
PLAN = ['old', 'lucky', 'mutant', 'generalist', 'loud', 'multitasker', 'wildling', 'pacifist', 'gladiator', 'saver', 'sick', 'farmer', 'ghost', 'speedy', 'entrepreneur', 'engineer', 'explorer', 'doctor', 'hunter']


def read_json(path):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return {}


def native_progress():
    save = read_json(SAVE)
    wins = []
    unlocked = False
    for entry in save.get('difficulties_unlocked', []):
        for zone in entry.get('zones_difficulty_info', []):
            unlocked |= zone.get('max_selectable_difficulty', 0) >= 6
            beaten = zone.get('max_difficulty_beaten', {})
            if beaten.get('difficulty_value', -1) >= 5:
                wins.append((entry['character_id'], zone['zone_id']))
    return save, sorted(set(wins)), unlocked


def write_status(status, **values):
    _, wins, unlocked = native_progress()
    data = dict(status=status, qualifying_wins=wins, count=len(wins),
                nightmare_unlocked=unlocked, updated_at=time.time(), **values)
    target = RUN / 'campaign-status.json'
    temporary = target.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    temporary.replace(target)


def close_game(pid):
    # WM_CLOSE only to windows owned by the exact launched game process.
    user = ctypes.WinDLL('user32')
    callback_type = ctypes.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
    user.GetWindowThreadProcessId.argtypes = [W.HWND, ctypes.POINTER(W.DWORD)]
    user.PostMessageW.argtypes = [W.HWND, W.UINT, W.WPARAM, W.LPARAM]
    @callback_type
    def visit(hwnd, _):
        owner = W.DWORD()
        user.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid:
            user.PostMessageW(hwnd, 0x10, 0, 0)
        return True
    user.EnumWindows(visit, 0)


def alive(pid):
    kernel = ctypes.WinDLL('kernel32')
    kernel.OpenProcess.restype = W.HANDLE
    kernel.WaitForSingleObject.argtypes = [W.HANDLE, W.DWORD]
    kernel.CloseHandle.argtypes = [W.HANDLE]
    handle = kernel.OpenProcess(0x100000, False, pid)
    if not handle:
        return False
    try:
        return kernel.WaitForSingleObject(handle, 0) == 258
    finally:
        kernel.CloseHandle(handle)


def main():
    RUN.mkdir(exist_ok=True)
    save, wins, unlocked = native_progress()
    if not save:
        raise RuntimeError('Native save unreadable; will not launch a campaign.')
    if unlocked:
        write_status('complete')
        return
    for short_name in PLAN:
        if (RUN / 'campaign-stop').exists():
            write_status('stopped')
            return
        character = 'character_' + short_name
        save, wins, unlocked = native_progress()
        if unlocked:
            write_status('complete')
            return
        if any(char == character for char, zone in wins):
            continue
        branch = subprocess.run(['git', 'branch', '--show-current'], cwd=ROOT,
                                capture_output=True, text=True, check=True).stdout.strip()
        expected_branch = 'feature/' + short_name + '-strategy'
        if branch != expected_branch:
            write_status('branch_required', character=character,
                         expected_branch=expected_branch, actual_branch=branch)
            return
        profile = 'brawler' if short_name == 'crazy' else 'ranged'
        weapon = {'lucky':'weapon_slingshot', 'old':'weapon_double_barrel_shotgun', 'chunky':'weapon_double_barrel_shotgun', 'mage':'weapon_taser', 'crazy':'weapon_knife'}.get(short_name, 'weapon_smg')
        (RUN / 'challenge.json').write_text(json.dumps(dict(
            enabled=True, difficulty=5, profile=profile, character=character,
            weapon=weapon)), encoding='utf-8')
        launched_at = time.time()
        result = subprocess.run([sys.executable, str(ROOT / 'launch_background.py'),
                                 '--profile', profile, '--speed', '1'], cwd=ROOT,
                                capture_output=True, text=True, check=True)
        launch = json.loads(result.stdout.strip())
        pid = launch['pid']
        entered_combat = False
        last_wave = -1
        while True:
            if (RUN / 'campaign-stop').exists():
                close_game(pid)
                write_status('stopped', character=character)
                return
            state = read_json(RUN / 'state.json')
            fresh = (RUN / 'state.json').exists() and (RUN / 'state.json').stat().st_mtime >= launched_at
            matched = fresh and state.get('character') == character
            if not alive(pid):
                write_status('review_required', character=character, reason='game_exited')
                return
            if matched:
                if not state.get('enabled', True):
                    write_status('review_required', character=character, reason=state.get('decision'))
                    return
                entered_combat |= state.get('scene') == 'res://main.tscn'
                write_status('running', character=character, pid=pid, wave=state.get('wave'),
                             run_id=state.get('run_id'), recording=False)
                if state.get('wave') != last_wave:
                    last_wave = state.get('wave')
                    print(json.dumps(dict(character=character, wave=last_wave)), flush=True)
                if entered_combat and state.get('finished'):
                    if not state.get('won'):
                        write_status('review_required', character=character,
                                     reason='defeat', run_id=state.get('run_id'))
                        print(json.dumps(dict(character=character, result='defeat')), flush=True)
                        return
                    # Native saved completion, not only the pilot's won flag.
                    _, wins, unlocked = native_progress()
                    if (character, 0) not in wins:
                        time.sleep(2)
                        continue
                    print(json.dumps(dict(character=character, result='victory', count=len(wins))), flush=True)
                    if unlocked:
                        write_status('complete', character=character, run_id=state.get('run_id'))
                        return
                    write_status('character_complete', character=character,
                                 run_id=state.get('run_id'), reason='merge_branch_before_next_character')
                    return
            if time.time()-launched_at > 3600:
                write_status('review_required', character=character, reason='run_timeout')
                return
            time.sleep(3)
    write_status('review_required', reason='plan_exhausted_before_native_unlock')


if __name__ == '__main__':
    import msvcrt
    RUN.mkdir(exist_ok=True)
    with (RUN / 'campaign.lock').open('a+b') as lock:
        if lock.tell() == 0:
            lock.write(b'0')
            lock.flush()
        lock.seek(0)
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        main()
