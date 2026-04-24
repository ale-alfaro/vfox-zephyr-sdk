# West Shim 

West is the command runner for Zephyr and is essential for most jobs done in a west workspace.  To be able to install and package as a proper tool (not only the west package) we need to do some work but it is worth the pain as having to manage python venv is a pain in the ass.

Main idea is too:
1. Create a shim or 

Folllowing code snippet is used to run the west shim script:

```python title:west
import subprocess
import sys


def main():
    cmd = ["west", *sys.argv[1:]]
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
        if exc.stderr:
            print(
                f"""
        {res.stderr.decode().rstrip()}
                            """,
            )
        raise SystemExit(exc.returncode) from exc


if __name__ == "__main__":
    main()
```

To manage package dependencies we need to run this as a [uv script with dependencies](https://docs.astral.sh/uv/guides/scripts/#running-a-script-with-dependencies) as inline metadata as defined by the [Python's inline script metadata spec](https://packaging.python.org/en/latest/specifications/inline-script-metadata/#inline-script-metadata) which look something like this at the top of the file

```python
# /// script
# requires-python = ">=3.11"
# dependencies = ["west", "pyelftools", ...]
# ///
```

That takes care of all the required packages being installed by the time west is called. As this package dependencies are managed in requirements.txt files inside the Zephyr repo and are not properly versioned or distributed we must resort to couple hacks to get the dependencies right for most cases. But we need to consider two scenarios:

## West ran inside a west workspace with ZEPHYR_BASE set properly through  an environment variable or west configuration


They were downloaded from Zephyr's source tree:

> https://raw.githubusercontent.com/zephyrproject-rtos/zephyr/v4.3.0/scripts/requirements-actions.txt
> https://raw.githubusercontent.com/zephyrproject-rtos/zephyr/v4.3.0/scripts/requirements-actions.in

