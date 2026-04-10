#!/usr/bin/env -S uv run --script
#
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "pyelftools",
#     "PyYAML",
#     "pykwalify",
#     "jsonschema",
#     "canopen",
#     "packaging",
#     "patool",
#     "psutil",
#     "pylink-square",
#     "pyserial",
#     "requests",
#     "semver",
#     "tqdm",
#     "reuse",
#     "anytree",
#     "intelhex",
#     "west",
# ]
# ///

import subprocess  # noqa: S404
import sys
from pathlib import Path

from west.configuration import Configuration
from west.util import WestNotFound, west_topdir


def run_west_cmd(
    west_cmd: list[str],
    zephyr_base: Path | None = None,
) -> None:
    if zephyr_base and zephyr_base.is_dir():
        requirements_txt_path = zephyr_base / "scripts" / "requirements-base.txt"

        cmd = [
            "uvx",
            "--with-requirements",
            str(requirements_txt_path),
            "west",
            *west_cmd,
        ]
    else:
        cmd = ["uvx", "west", *west_cmd]

    try:
        res = subprocess.run(
            cmd,
            check=True,
        )
        if res.stdout:
            print(
                f"""
        {res.stdout.decode().rstrip()}
                            """,
            )

    except subprocess.CalledProcessError as exc:
        print(f"""
                    process failed!
                        cmd: {exc.cmd}
                        retcode: {exc.returncode}
                        stderr: {exc.stderr.rstrip().decode()}
                        build_output:
                        stdout: {exc.stdout.rstrip().decode()}
                        """)

        sys.exit(1)


def main():
    west_args = sys.argv[1:]
    zephyr_base = None
    try:
        if topdir := west_topdir(None, fall_back=True):
            westconfig = Configuration(topdir)
            if zephyr_base_val := westconfig.get("zephyr.base", f"{topdir}/zephyr"):
                zephyr_base = Path(zephyr_base_val)
    except WestNotFound:
        print("No west workspace found, are you inside a workspace?")

    run_west_cmd(west_args, zephyr_base)


if __name__ == "__main__":
    main()
