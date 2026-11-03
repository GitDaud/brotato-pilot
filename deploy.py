import pathlib,zipfile
root=pathlib.Path(__file__).resolve().parent/'mods-unpacked'
dest=pathlib.Path(r'F:\SteamLibrary\steamapps\common\Brotato\mods'); dest.mkdir(exist_ok=True)
with zipfile.ZipFile(dest/'Codex-Pilot.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in root.rglob('*'):
  if p.is_file(): z.write(p,'mods-unpacked/'+p.relative_to(root).as_posix())
print(dest/'Codex-Pilot.zip')
