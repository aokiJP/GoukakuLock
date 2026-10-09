"""xcresulttool export attachments の出力(manifest.json)から、スクリーンショットを付けた名前で並べ直す。
   使い方: python3 scripts/rename-attachments.py <export-dir> <out-dir>"""
import json, os, shutil, sys

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
manifest = json.load(open(os.path.join(src, "manifest.json")))

def walk(node):
    if isinstance(node, dict):
        if "exportedFileName" in node:
            yield node
        for v in node.values():
            yield from walk(v)
    elif isinstance(node, list):
        for v in node:
            yield from walk(v)

count = 0
for item in walk(manifest):
    name = item.get("suggestedHumanReadableName") or item["exportedFileName"]
    # 例: "01-はじめに_0_6F3C....png" → "01-はじめに.png"
    base, ext = os.path.splitext(name)
    base = base.split("_0_")[0]
    shutil.copyfile(os.path.join(src, item["exportedFileName"]), os.path.join(dst, base + (ext or ".png")))
    count += 1
print(f"{count} attachments")
