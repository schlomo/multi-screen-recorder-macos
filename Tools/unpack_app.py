"""Unpacks the app archive from scripts/build-app into an empty build folder,
for scripts/unpack-app, treating it as data and relying on no tar's defaults: every
member is checked before anything is written, then written by this script.

A member must lie inside the app bundle, which must be a folder, with no
absolute path and no `..` component, and not below a symbolic link. A
symbolic link must be relative and without `..`, so it stays inside the
bundle; a hard link must point to an earlier file of the bundle. Anything
else (devices, fifos) is refused. Nothing from the archive is executed.
"""

import os
import sys
import tarfile
from pathlib import Path, PurePosixPath

ME = "scripts/unpack-app"
BUNDLE = PurePosixPath("Multi Screen Recorder.app")


class Refused(Exception):
    pass


def member_path(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    if path.is_absolute():
        raise Refused(f"the member '{name}' has an absolute path")
    if ".." in path.parts:
        raise Refused(f"the member '{name}' has a .. component")
    if path.parts[:1] != BUNDLE.parts:
        raise Refused(f"the member '{name}' lies outside {BUNDLE}")
    return path


def check(members: list[tarfile.TarInfo]) -> None:
    seen: set[PurePosixPath] = set()
    files: set[PurePosixPath] = set()
    symbolic_links: set[PurePosixPath] = set()
    for member in members:
        path = member_path(member.name)
        if path in seen:
            raise Refused(f"the member '{member.name}' appears twice")
        for parent in path.parents:
            if parent in symbolic_links:
                raise Refused(f"the member '{member.name}' would be written through the symbolic link '{parent}'")
        if path == BUNDLE and not member.isdir():
            raise Refused(f"{BUNDLE} is not a folder in the archive")
        if member.issym():
            target = PurePosixPath(member.linkname)
            if target.is_absolute() or ".." in target.parts:
                raise Refused(f"the symbolic link '{member.name}' points outside {BUNDLE} ({member.linkname})")
            symbolic_links.add(path)
        elif member.islnk():
            target = PurePosixPath(member.linkname)
            if target.is_absolute() or ".." in target.parts or target not in files:
                raise Refused(f"the hard link '{member.name}' points outside {BUNDLE}'s files ({member.linkname})")
        elif member.isfile():
            files.add(path)
        elif not member.isdir():
            raise Refused(f"the member '{member.name}' is not a file, folder or link")
        seen.add(path)
    if BUNDLE not in seen:
        raise Refused(f"the archive holds no {BUNDLE} folder")


def write(archive: tarfile.TarFile, members: list[tarfile.TarInfo], build: Path) -> None:
    for member in members:
        destination = build / member.name
        if member.isdir():
            destination.mkdir(mode=0o755, parents=True, exist_ok=True)
            continue
        destination.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
        if member.issym():
            destination.symlink_to(member.linkname)
        elif member.islnk():
            os.link(build / member.linkname, destination)
        else:
            source = archive.extractfile(member)
            assert source is not None
            with source, open(destination, "xb") as target:
                target.write(source.read())
            destination.chmod(0o755 if member.mode & 0o111 else 0o644)


def unpack(archive_path: Path, build: Path) -> None:
    if build.is_symlink() or (build.exists() and any(build.iterdir())):
        raise Refused("build/ is not empty; unpack only into an empty build/")
    with tarfile.open(archive_path) as archive:
        members = archive.getmembers()
        check(members)
        build.mkdir(exist_ok=True)
        write(archive, members, build)
    bundle = build / BUNDLE
    if bundle.is_symlink() or not bundle.is_dir():
        raise Refused(f"build/{BUNDLE} is not a folder")


def main() -> int:
    if len(sys.argv) != 3:
        print(f"{ME}: usage: unpack_app.py <archive> <build folder>", file=sys.stderr)
        return 1
    archive_path, build = Path(sys.argv[1]), Path(sys.argv[2])
    try:
        unpack(archive_path, build)
    except Refused as refusal:
        print(f"{ME}: {refusal}", file=sys.stderr)
        return 1
    except (OSError, tarfile.TarError) as error:
        print(f"{ME}: cannot unpack {archive_path}: {error}", file=sys.stderr)
        return 1
    print(f"build/{BUNDLE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
