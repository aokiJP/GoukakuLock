#!/usr/bin/env python3
import json, pathlib, urllib.request, hashlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
repos=[('small','mlx-community/Qwen3-0.6B-4bit','73e3e38d981303bc594367cd910ea6eb48349da8'),('balanced','mlx-community/Qwen3-1.7B-4bit','3b1b1768f8f8cf8351c712464f906e86c2b8269e')]
manifest=[]
for name,repo,rev in repos:
    d=json.load(urllib.request.urlopen(f'https://huggingface.co/api/models/{repo}/revision/{rev}?blobs=true'))
    folder=ROOT/'Models'/name; folder.mkdir(parents=True,exist_ok=True)
    for f in d['siblings']:
        fn=f['rfilename']
        if not (fn.endswith(('.json','.safetensors','.txt','.jinja')) or fn=='README.md'): continue
        dest=folder/fn
        expected=f.get('lfs',{}).get('sha256')
        if not dest.exists() or dest.stat().st_size!=f.get('size',-1):
            print('Downloading',fn,flush=True)
            urllib.request.urlretrieve(f'https://huggingface.co/{repo}/resolve/{rev}/{fn}',str(dest)+'.partial')
            pathlib.Path(str(dest)+'.partial').replace(dest)
        sha=hashlib.file_digest(open(dest,'rb'),'sha256').hexdigest()
        if expected and expected!=sha: raise RuntimeError('Hash mismatch: '+fn)
        manifest.append(dict(path=f'{name}/{fn}',sha256=sha,bytes=dest.stat().st_size,repo=repo,revision=rev))
    urllib.request.urlretrieve('https://huggingface.co/Qwen/Qwen3-0.6B/raw/main/LICENSE',folder/'LICENSE')
(ROOT/'Models'/'manifest.json').write_text(json.dumps(manifest,indent=2))
print('Models verified',flush=True)
