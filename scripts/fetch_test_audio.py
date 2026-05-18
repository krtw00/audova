#!/usr/bin/env python3
"""
Audova テストライブラリ用音源を Internet Archive の netlabels コレクションから DL する。

- 出力先: $AUDOVA_TEST_LIBRARY (default: ~/Music/audova-test-library) の _source/
- 取得対象: netlabels コレクション + format:"VBR MP3"、 ダウンロード数 desc で上位 N item
- 各 item から最大 --per-item 曲をサンプリング、 合計 --target 曲を狙う
- ライセンス情報は manifest.json として _source/ 直下に記録

依存: python3 (標準ライブラリのみ)
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path


SEARCH_URL = "https://archive.org/advancedsearch.php"
METADATA_URL = "https://archive.org/metadata"
DOWNLOAD_URL = "https://archive.org/download"


def http_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "audova-test-fetch/0.1"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def search_items(rows: int) -> list[dict]:
    params = {
        "q": 'collection:netlabels AND format:("VBR MP3") AND licenseurl:*creativecommons*',
        "fl[]": ["identifier", "title", "creator", "licenseurl", "downloads"],
        "sort[]": "downloads desc",
        "rows": str(rows),
        "output": "json",
    }
    url = f"{SEARCH_URL}?{urllib.parse.urlencode(params, doseq=True)}"
    data = http_json(url)
    return data["response"]["docs"]


def item_mp3_files(identifier: str) -> list[dict]:
    url = f"{METADATA_URL}/{identifier}"
    data = http_json(url)
    files = []
    for f in data.get("files", []):
        if f.get("format") != "VBR MP3":
            continue
        size = int(f.get("size", "0") or 0)
        if size < 500_000 or size > 30_000_000:
            # 30 秒未満 / 異常に巨大なものは弾く (= bumper / 長尺 mix 除外)
            continue
        files.append({"name": f["name"], "size": size, "length": f.get("length")})
    return files


def download(url: str, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() and dst.stat().st_size > 0:
        return
    req = urllib.request.Request(url, headers={"User-Agent": "audova-test-fetch/0.1"})
    with urllib.request.urlopen(req, timeout=120) as resp, open(dst, "wb") as out:
        while chunk := resp.read(64 * 1024):
            out.write(chunk)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--target", type=int, default=40, help="狙う合計曲数 (default: 40)")
    ap.add_argument("--per-item", type=int, default=3, help="1 item からの最大曲数 (default: 3)")
    ap.add_argument("--item-rows", type=int, default=40, help="item 検索取得数 (default: 40)")
    ap.add_argument("--seed", type=int, default=20260518, help="サンプリング seed")
    ap.add_argument("--out", type=Path, default=None, help="出力先 (default: $AUDOVA_TEST_LIBRARY or ~/Music/audova-test-library)")
    args = ap.parse_args()

    out_root = args.out or Path(os.environ.get("AUDOVA_TEST_LIBRARY", str(Path.home() / "Music" / "audova-test-library")))
    source_dir = out_root / "_source"
    source_dir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(args.seed)
    print(f"[search] netlabels items (rows={args.item_rows}) ...", file=sys.stderr)
    items = search_items(args.item_rows)
    print(f"[search] got {len(items)} items", file=sys.stderr)

    manifest: list[dict] = []
    total = 0
    for item in items:
        if total >= args.target:
            break
        identifier = item["identifier"]
        try:
            files = item_mp3_files(identifier)
        except Exception as e:
            print(f"[warn] {identifier}: metadata 取得失敗 ({e})", file=sys.stderr)
            continue
        if not files:
            continue
        rng.shuffle(files)
        picked = files[: args.per_item]
        item_record = {
            "identifier": identifier,
            "title": item.get("title"),
            "creator": item.get("creator"),
            "licenseurl": item.get("licenseurl"),
            "files": [],
        }
        for f in picked:
            if total >= args.target:
                break
            file_url = f"{DOWNLOAD_URL}/{identifier}/{urllib.parse.quote(f['name'])}"
            local_path = source_dir / identifier / f["name"]
            try:
                print(f"[dl] {identifier}/{f['name']} ({f['size']:,} B)", file=sys.stderr)
                download(file_url, local_path)
            except Exception as e:
                print(f"[warn] {identifier}/{f['name']}: DL 失敗 ({e})", file=sys.stderr)
                continue
            item_record["files"].append({"name": f["name"], "size": f["size"], "length": f.get("length")})
            total += 1
            time.sleep(0.2)  # archive.org に優しく
        if item_record["files"]:
            manifest.append(item_record)

    manifest_path = source_dir / "manifest.json"
    manifest_path.write_text(json.dumps({"items": manifest, "track_count": total}, indent=2, ensure_ascii=False))
    print(f"[done] {total} tracks → {source_dir}", file=sys.stderr)
    print(f"[done] manifest → {manifest_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
