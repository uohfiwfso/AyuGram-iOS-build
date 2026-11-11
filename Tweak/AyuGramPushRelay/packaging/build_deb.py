#!/usr/bin/env python3
"""Собрать rootless-.deb без dpkg-deb.

macOS-раннеры в GitHub Actions не имеют dpkg, а ставить его ради одной
упаковки смысла нет: .deb - это обычный `ar`-архив с тремя членами:

    debian-binary   ("2.0\\n")
    control.tar.gz  (DEBIAN/control, postinst, postrm, triggers)
    data.tar.gz     (файлы пакета)

Собираем ровно то, что делает dpkg-deb -b, но на чистом Python, чтобы
сборка работала на любом раннере без системных пакетов.

Пути внутри data.tar - ./var/jb/... (rootless-раскладка): так же устроены
настоящие rootless-пакеты, например basebin-link.deb из bootstrap Dopamine.
"""

import gzip
import io
import os
import pathlib
import sys
import tarfile
import time

AR_MAGIC = b"!<arch>\n"

# Порядок членов фиксирован dpkg: сначала debian-binary, потом control.tar,
# потом data.tar. Имена дополняются пробелами до чётной длины.
MEMBER_NAMES = ["debian-binary", "control.tar.gz", "data.tar.gz"]


def ar_member(name, payload, mtime=0, mode=0o100644):
    """Один член ar-архива в GNU-формате (его и ждёт dpkg).

    Заголовок - ровно 60 байт:
        name(16) mtime(12) uid(6) gid(6) mode(8) size(10) "`\\n"
    Размеры полей нестандартные (не все по 16) - именно такие и пишет
    dpkg-deb, и именно их ждёт парсер на устройстве.
    """
    out = name.encode().ljust(16)
    out += str(mtime).encode().ljust(12)
    out += b"0".ljust(6)           # uid
    out += b"0".ljust(6)           # gid
    out += oct(mode).encode().ljust(8)
    out += str(len(payload)).encode().ljust(10)
    out += b"`\n"
    out += payload
    if len(payload) % 2 != 0:
        out += b"\n"
    return out


def tar_gz(members, mtime=0):
    """Собрать .tar.gz из списка (arcname, bytes, mode).

    Каталоги отмечаются типом DIRTYPE - dpkg по ним создаёт настоящие
    каталоги. Обычный файл с типом REGTYPE, даже если его имя оканчивается на
    "/", dpkg считает файлом - установка падает с "unable to create
    '<path>.dpkg-new'".
    """
    raw = io.BytesIO()
    # mtime фиксируем, чтобы сборка была воспроизводимой.
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as tf:
        for arcname, payload, mode in members:
            info = tarfile.TarInfo(name=arcname)
            info.size = len(payload)
            info.mode = mode
            info.mtime = mtime
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "root"
            if payload == b"" and mode & 0o111 and arcname.endswith("/"):
                # Каталог: тип важен для dpkg.
                info.type = tarfile.DIRTYPE
                info.size = 0
            else:
                info.type = tarfile.REGTYPE
            tf.addfile(info, io.BytesIO(payload))
    return gzip.compress(raw.getvalue(), mtime=0)


def build_deb(stage_dir, out_path, version, arch):
    stage = pathlib.Path(stage_dir)
    debian = stage / "DEBIAN"
    if not debian.is_dir():
        raise SystemExit(f"no DEBIAN directory in {stage}")

    control_members = []
    for name in ("control", "postinst", "postrm", "preinst", "triggers", "conffiles"):
        p = debian / name
        if not p.exists():
            continue
        mode = 0o755 if name in ("postinst", "postrm", "preinst") else 0o644
        control_members.append((f"./{name}", p.read_bytes(), mode))

    # Файлы пакета: всё внутри stage, кроме DEBIAN.
    data_members = []
    for root, dirs, files in os.walk(stage):
        dirs.sort()
        files.sort()
        rootp = pathlib.Path(root)
        rel_root = rootp.relative_to(stage)
        # Каталоги нужны, чтобы tar сохранил структуру (dpkg их тоже пишет).
        # Имя каталога в tar заканчивается на "/", тип - DIRTYPE.
        for d in dirs:
            rel = (rel_root / d).as_posix()
            # DEBIAN - метаданные пакета, в data.tar их не быть.
            if rel == "DEBIAN" or rel.startswith("DEBIAN/"):
                continue
            data_members.append((f"./{rel}/", b"", 0o755))
        for f in files:
            p = rootp / f
            rel = (rel_root / f).as_posix()
            # DEBIAN в data.tar не попадает - это метаданные пакета.
            if rel == "DEBIAN" or rel.startswith("DEBIAN/"):
                continue
            mode = 0o755 if os.access(p, os.X_OK) else 0o644
            data_members.append((f"./{rel}", p.read_bytes(), mode))

    control_tar = tar_gz(control_members)
    data_tar = tar_gz(data_members)

    with open(out_path, "wb") as f:
        f.write(AR_MAGIC)
        f.write(ar_member("debian-binary", b"2.0\n"))
        f.write(ar_member("control.tar.gz", control_tar))
        f.write(ar_member("data.tar.gz", data_tar))

    return out_path


def main():
    if len(sys.argv) < 4:
        raise SystemExit(
            "usage: build_deb.py <stage-dir> <out.deb> <version> <arch>"
        )
    stage, out, version, arch = sys.argv[1:5]
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    path = build_deb(stage, out, version, arch)
    print(f"built {path} ({os.path.getsize(path)} bytes)")


if __name__ == "__main__":
    main()
