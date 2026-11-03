import pathlib,struct,hashlib
original=pathlib.Path(r'F:\SteamLibrary\steamapps\common\Brotato\Brotato.pck')
f=original.open('rb'); header=f.read(84); n=struct.unpack('<I',f.read(4))[0]; entries=[]
for i in range(n):
 l=struct.unpack('<I',f.read(4))[0]; name=f.read(l); off,size=struct.unpack('<QQ',f.read(16)); md=f.read(16); entries.append([name,off,size,md,None])
for p in pathlib.Path('mods-unpacked').rglob('*'):
 if p.is_file():
  data=p.read_bytes(); name=('res://'+p.as_posix()).encode(); name+=b'\0'*((-len(name))%4); entries.append([name,0,len(data),hashlib.md5(data).digest(),data])
start=88+sum(4+len(e[0])+32 for e in entries); start=(start+15)//16*16
out=pathlib.Path(r'F:\SteamLibrary\steamapps\common\Brotato\CodexPilot.pck')
with out.open('wb') as w:
 w.write(header); w.write(struct.pack('<I',len(entries))); offset=start
 for name,off,size,md,data in entries:
  w.write(struct.pack('<I',len(name))); w.write(name); w.write(struct.pack('<QQ',offset,size)); w.write(md); offset+=(size+15)//16*16
 w.write(b'\0'*(start-w.tell()))
 for name,off,size,md,data in entries:
  if data is None: f.seek(off); data=f.read(size)
  w.write(data); w.write(b'\0'*((-size)%16))
print(out)
