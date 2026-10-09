"""xcresulttool export attachments の出力(manifest.json)から、スクリーンショットだけを付けた名前で並べ直す。
   使い方: python3 scripts/rename-attachments.py <export-dir> <out-dir>
   UI テストが自動で付ける添付(画面の階層・動画・Synthesized Event など)は除き、
   「01-はじめに」のように番号で始まる画像だけを残す。"""
import json, os, re, shutil, sys

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

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".heic"}
count = skipped = 0
for item in walk(manifest):
    name = item.get("suggestedHumanReadableName") or item["exportedFileName"]
    # 例: "01-はじめに_0_6F3C....png" → "01-はじめに.png"
    base, ext = os.path.splitext(name)
    base = base.split("_0_")[0]
    ext = (ext or os.path.splitext(item["exportedFileName"])[1] or ".png").lower()
    if ext not in IMAGE_EXTS or not re.match(r"^\d{2}-", base):
        skipped += 1
        continue
    shutil.copyfile(os.path.join(src, item["exportedFileName"]), os.path.join(dst, base + ext))
    count += 1
print(f"{count} screenshots ({skipped} other attachments skipped)")
