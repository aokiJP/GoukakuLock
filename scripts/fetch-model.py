#!/usr/bin/env python3
"""AI/models.json のモデルを Hugging Face から取ってきて、アプリに入れられる形に整える。

    python3 scripts/fetch-model.py <モデルid> <出力フォルダ> [--catalog AI/models.json] [--source bundled]

- 目録の files を、固定したリビジョンで取る(何度でも同じ中身になる)
- stripPrefixes に当たるテンソル(画像・音声の部分)を safetensors から取り除く
  (アプリの GoukakuAI/Safetensors.swift と同じやり方。8 バイト境界にそろえる)
- goukaku-model.json(アプリが「入っているモデル」と認める印)を書く
標準ライブラリだけで動く(CI の macOS・Linux どちらでも)。
"""
import argparse
import datetime
import json
import os
import struct
import sys
import time
import urllib.request

CHUNK = 8 * 1024 * 1024


def download(url, dest):
    tmp = dest + ".part"
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "goukakulock-ci"})
            with urllib.request.urlopen(req, timeout=120) as resp, open(tmp, "wb") as out:
                expected = resp.headers.get("Content-Length")
                got = 0
                while True:
                    chunk = resp.read(CHUNK)
                    if not chunk:
                        break
                    out.write(chunk)
                    got += len(chunk)
            if expected is not None and int(expected) != got:
                raise IOError(f"size mismatch {got} != {expected}")
            os.replace(tmp, dest)
            return got
        except Exception as e:  # noqa: BLE001
            print(f"  retry {attempt + 1}: {e}", file=sys.stderr)
            time.sleep(3 * (attempt + 1))
    raise SystemExit(f"download failed: {url}")


def read_header(f):
    (length,) = struct.unpack("<Q", f.read(8))
    header = json.loads(f.read(length))
    return header, 8 + length


def slim(path, keep):
    """keep(name) が False のテンソルを取り除く。返り値: (残した数, 捨てた数)"""
    with open(path, "rb") as f:
        header, data_start = read_header(f)
        meta = header.pop("__metadata__", None)
        entries = sorted(header.items(), key=lambda kv: kv[1]["data_offsets"][0])
        kept = [(n, info) for n, info in entries if keep(n)]
        dropped = len(entries) - len(kept)
        if dropped == 0:
            return len(kept), 0
        new_header = {}
        if meta is not None:
            new_header["__metadata__"] = meta
        offset = 0
        for name, info in kept:
            size = info["data_offsets"][1] - info["data_offsets"][0]
            info = dict(info)
            info["data_offsets"] = [offset, offset + size]
            new_header[name] = info
            offset += size
        blob = json.dumps(new_header, sort_keys=True, separators=(",", ":")).encode()
        blob += b" " * ((8 - len(blob) % 8) % 8)
        out_path = path + ".slim"
        with open(out_path, "wb") as out:
            out.write(struct.pack("<Q", len(blob)))
            out.write(blob)
            for name, info in kept:
                begin, end = header[name]["data_offsets"]
                f.seek(data_start + begin)
                remaining = end - begin
                while remaining > 0:
                    chunk = f.read(min(CHUNK, remaining))
                    if not chunk:
                        raise SystemExit(f"truncated tensor {name}")
                    out.write(chunk)
                    remaining -= len(chunk)
    if kept:
        os.replace(out_path, path)
    else:
        os.remove(out_path)
        os.remove(path)
    return len(kept), dropped


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model_id")
    ap.add_argument("out_dir")
    ap.add_argument("--catalog", default=os.path.join(os.path.dirname(__file__), "..", "AI", "models.json"))
    ap.add_argument("--source", default="bundled")
    args = ap.parse_args()

    catalog = json.load(open(args.catalog, encoding="utf-8"))
    spec = next((m for m in catalog["models"] if m["id"] == args.model_id), None)
    if spec is None:
        raise SystemExit(f"unknown model id: {args.model_id}")
    os.makedirs(args.out_dir, exist_ok=True)

    total = 0
    for name in spec["files"]:
        url = f"https://huggingface.co/{spec['repo']}/resolve/{spec['revision']}/{name}"
        dest = os.path.join(args.out_dir, name)
        t = time.time()
        size = download(url, dest)
        total += size
        print(f"{name}: {size:,} bytes ({time.time() - t:.1f}s)")
    print(f"downloaded {total:,} bytes (catalog says {spec['downloadBytes']:,})")
    if total != spec["downloadBytes"]:
        raise SystemExit("download size does not match the catalog (revision changed?)")

    prefixes = tuple(spec.get("stripPrefixes") or [])
    if prefixes:
        for name in os.listdir(args.out_dir):
            if name.endswith(".safetensors"):
                kept, dropped = slim(os.path.join(args.out_dir, name), lambda n: not n.startswith(prefixes))
                print(f"slim {name}: kept {kept}, dropped {dropped}")

    installed = sum(os.path.getsize(os.path.join(args.out_dir, n)) for n in os.listdir(args.out_dir))
    manifest = {
        "id": spec["id"],
        "name": spec["name"],
        "family": spec["family"],
        "source": args.source,
        "repo": spec["repo"],
        "revision": spec["revision"],
        "installedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "bytes": installed,
    }
    with open(os.path.join(args.out_dir, "goukaku-model.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print(f"installed {installed:,} bytes (catalog says {spec['installedBytes']:,})")
    # 取り除いたあとの大きさが目録とずれすぎていたら止める(テンソル名の変化に気づくため)
    if abs(installed - spec["installedBytes"]) > max(8 * 1024 * 1024, spec["installedBytes"] * 0.02):
        raise SystemExit("installed size differs from the catalog by more than 2%")


if __name__ == "__main__":
    main()
