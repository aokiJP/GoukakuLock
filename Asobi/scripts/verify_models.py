import pathlib,json,hashlib,struct
root=pathlib.Path(__file__).resolve().parents[1]/'Models'
manifest=json.loads((root/'manifest.json').read_text())
assert {x['path'].split('/')[0] for x in manifest}=={'small','balanced'}
for x in manifest:
 p=root/x['path']; assert p.stat().st_size==x['bytes'],str(p)
 assert hashlib.file_digest(open(p,'rb'),'sha256').hexdigest()==x['sha256'],str(p)
 if p.suffix=='.safetensors':
  with open(p,'rb') as f:
   n=struct.unpack('<Q',f.read(8))[0]; h=json.loads(f.read(n))
   assert all(0<=v['data_offsets'][0]<=v['data_offsets'][1]<=p.stat().st_size-8-n for k,v in h.items() if k!='__metadata__')
print('Model hashes and safetensors bounds verified')
