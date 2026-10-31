#!/usr/bin/env python3
"""List package paths from an UE5 IoStore .utoc directory index (unencrypted index only)."""
import struct, sys

def read_fstring(b, o):
    n = struct.unpack_from("<i", b, o)[0]; o += 4
    if n == 0: return "", o
    if n > 0:
        s = b[o:o + n - 1].decode("utf-8", "replace"); return s, o + n
    n = -n
    s = b[o:o + 2 * (n - 1)].decode("utf-16-le", "replace"); return s, o + 2 * n

def parse(path):
    b = open(path, "rb").read()
    assert b[:16] == b"-==--==--==--==-", "not a utoc"
    (ver,) = struct.unpack_from("<B", b, 16)
    hdr_size, entry_count, cblock_count, cblock_size, cm_count, cm_len, cblock_sz, dir_size, part_count = struct.unpack_from("<9I", b, 20)
    container_id, = struct.unpack_from("<Q", b, 56)
    flags = b[80]
    seeds_count, = struct.unpack_from("<I", b, 84)
    part_size, = struct.unpack_from("<Q", b, 88)
    nophash_count, = struct.unpack_from("<I", b, 96)
    o = hdr_size
    o += entry_count * 12          # chunk ids
    o += entry_count * 10          # offsets/lengths
    o += seeds_count * 4
    o += nophash_count * 4
    o += cblock_count * cblock_size
    o += cm_count * cm_len
    if flags & 0x4:                # signed
        hs, = struct.unpack_from("<i", b, o); o += 4
        o += hs * 2
        o += cblock_count * 20
    if flags & 0x8 == 0 and dir_size:  # Indexed flag
        pass
    d = b[o:o + dir_size]
    if flags & 0x2 and not d[:4].strip(b'\0'):
        raise SystemExit(f"{path}: directory index is encrypted")
    p = 0
    mount, p = read_fstring(d, p)
    (nd,) = struct.unpack_from("<i", d, p); p += 4
    dirs = [struct.unpack_from("<4I", d, p + i * 16) for i in range(nd)]; p += nd * 16
    (nf,) = struct.unpack_from("<i", d, p); p += 4
    files = [struct.unpack_from("<3I", d, p + i * 12) for i in range(nf)]; p += nf * 12
    (ns,) = struct.unpack_from("<i", d, p); p += 4
    strings = []
    for _ in range(ns):
        s, p = read_fstring(d, p); strings.append(s)
    NONE = 0xFFFFFFFF
    out = []
    def walk(di, prefix):
        name, first_child, next_sib, first_file = dirs[di]
        here = prefix + (strings[name] + "/" if name != NONE else "")
        f = first_file
        while f != NONE:
            fn, nxt, _ = files[f]
            out.append(here + strings[fn]); f = nxt
        c = first_child
        while c != NONE:
            walk(c, here); c = dirs[c][2]
    walk(0, mount)
    return out

if __name__ == "__main__":
    for path in sys.argv[1:]:
        try:
            for f in parse(path): print(f)
        except Exception as e:
            print(f"# {path}: {e}", file=sys.stderr)
