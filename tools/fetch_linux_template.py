#!/usr/bin/env python3
"""
Fast downloader for Godot Linux export templates using HTTP Range requests.
Instead of downloading the entire multiplatform TPZ archive (~1.1 GB),
this script inspects the remote zip central directory and extracts only
the Linux templates (linux_release.x86_64, linux_debug.x86_64, version.txt)
which are ~25 MB each.
"""

import os
import sys
import struct
import zlib
import urllib.request

def fetch_linux_templates(version: str, dest_dir: str):
    os.makedirs(dest_dir, exist_ok=True)
    release_path = os.path.join(dest_dir, "linux_release.x86_64")
    if os.path.isfile(release_path) and os.path.getsize(release_path) > 0:
        print(f"Linux export template already present at: {release_path}")
        return True

    tpz_url = f"https://github.com/godotengine/godot/releases/download/{version}-stable/Godot_v{version}-stable_export_templates.tpz"
    print(f"Connecting to {tpz_url} ...")

    # Follow redirect to get actual storage URL
    req = urllib.request.Request(tpz_url, headers={"User-Agent": "curl/7.81.0"})
    with urllib.request.urlopen(req) as resp:
        final_url = resp.geturl()

    # Get total file size
    head_req = urllib.request.Request(final_url, method="HEAD", headers={"User-Agent": "curl/7.81.0"})
    with urllib.request.urlopen(head_req) as resp:
        content_length = resp.headers.get("Content-Length")
        if not content_length:
            print("Server did not return Content-Length, cannot use range requests.")
            return False
        total_size = int(content_length)

    def fetch_range(start: int, length: int) -> bytes:
        r_req = urllib.request.Request(final_url, headers={
            "User-Agent": "curl/7.81.0",
            "Range": f"bytes={start}-{start+length-1}"
        })
        with urllib.request.urlopen(r_req) as r_resp:
            return r_resp.read()

    # Read last 64 KB to locate End of Central Directory (EOCD)
    tail_size = min(65536, total_size)
    tail = fetch_range(total_size - tail_size, tail_size)
    eocd_pos = tail.rfind(b"PK\x05\x06")
    if eocd_pos == -1:
        print("Could not find ZIP End of Central Directory record.")
        return False

    _, _, _, total_entries, cd_size, cd_offset = struct.unpack(
        "<HHHHII", tail[eocd_pos+4:eocd_pos+20]
    )

    print(f"Reading central directory ({cd_size} bytes, {total_entries} entries)...")
    cd_data = fetch_range(cd_offset, cd_size)

    # Targets to extract
    target_names = {
        "templates/linux_release.x86_64": "linux_release.x86_64",
        "templates/linux_debug.x86_64": "linux_debug.x86_64",
        "templates/version.txt": "version.txt",
    }

    entries = {}
    pos = 0
    while pos < len(cd_data):
        if cd_data[pos:pos+4] != b"PK\x01\x02":
            break
        (
            _, _, _, method, _, _, _,
            comp_size, uncomp_size,
            name_len, extra_len, comment_len,
            _, _, _, local_hdr_offset
        ) = struct.unpack("<HHHHHHIIIHHHHHII", cd_data[pos+4:pos+46])
        name = cd_data[pos+46:pos+46+name_len].decode("utf-8", "ignore")
        if name in target_names:
            entries[name] = {
                "dest_file": target_names[name],
                "method": method,
                "comp_size": comp_size,
                "uncomp_size": uncomp_size,
                "local_offset": local_hdr_offset,
            }
        pos += 46 + name_len + extra_len + comment_len

    if "templates/linux_release.x86_64" not in entries:
        print("linux_release.x86_64 not found in central directory.")
        return False

    for name, info in entries.items():
        out_filename = info["dest_file"]
        out_path = os.path.join(dest_dir, out_filename)
        if os.path.isfile(out_path) and os.path.getsize(out_path) == info["uncomp_size"]:
            print(f"Already have {out_filename}")
            continue

        comp_size = info["comp_size"]
        uncomp_size = info["uncomp_size"]
        offset = info["local_offset"]

        print(f"Fetching {out_filename} ({comp_size / 1024 / 1024:.1f} MB compressed)...")
        # Read local header to get dynamic name_len / extra_len
        local_hdr = fetch_range(offset, 30)
        loc_name_len, loc_extra_len = struct.unpack("<HH", local_hdr[26:30])
        data_start = offset + 30 + loc_name_len + loc_extra_len

        # Stream / download compressed payload
        raw_comp = fetch_range(data_start, comp_size)

        if info["method"] == 0:  # Stored
            payload = raw_comp
        elif info["method"] == 8:  # Deflate
            payload = zlib.decompress(raw_comp, -15)
        else:
            print(f"Unsupported compression method {info['method']} for {name}")
            return False

        with open(out_path, "wb") as f:
            f.write(payload)

        if out_filename.endswith(".x86_64"):
            os.chmod(out_path, 0o755)

        print(f"Successfully extracted {out_filename} ({len(payload)} bytes)")

    return True

if __name__ == "__main__":
    ver = sys.argv[1] if len(sys.argv) > 1 else "4.4.1"
    target_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser(f"~/.local/share/godot/export_templates/{ver}.stable")
    success = fetch_linux_templates(ver, target_dir)
    sys.exit(0 if success else 1)
