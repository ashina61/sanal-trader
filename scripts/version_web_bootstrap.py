"""Give Flutter's JS entrypoint and loader content-specific public filenames.

GitHub Pages can cache the fixed main.dart.js URL after a deployment. Keep the
original files for compatibility and make the generated index load new URLs.
This only packages an already-built web app; it never runs Flutter or changes
wallet data, browser storage, or server permissions.
"""
import hashlib
from pathlib import Path
import re
import sys


def version_bootstrap(directory):
    root = Path(directory)
    entry = (root / "main.dart.js").read_bytes()
    bootstrap = (root / "flutter_bootstrap.js").read_text(encoding="utf-8")
    index = (root / "index.html").read_text(encoding="utf-8")
    if "main.dart.js" not in bootstrap:
        raise ValueError("Expected Flutter JS entrypoint missing from bootstrap")
    entry_name = "main." + hashlib.sha256(entry).hexdigest()[:16] + ".dart.js"
    bootstrap = bootstrap.replace("main.dart.js", entry_name)
    bootstrap_name = "flutter_bootstrap." + hashlib.sha256(
        bootstrap.encode("utf-8")).hexdigest()[:16] + ".js"
    pattern = r'''(src\s*=\s*["'])flutter_bootstrap\.js(["'])'''
    index, replacements = re.subn(pattern,
        lambda match: match[1] + bootstrap_name + match[2], index)
    if replacements != 1:
        raise ValueError("Expected one Flutter bootstrap script in index.html")
    # Validate every input before writing any build output.
    (root / entry_name).write_bytes(entry)
    (root / bootstrap_name).write_text(bootstrap, encoding="utf-8")
    (root / "index.html").write_text(index, encoding="utf-8")
    return entry_name, bootstrap_name


if __name__ == "__main__":
    for filename in version_bootstrap(sys.argv[1] if len(sys.argv) > 1 else "build/web"):
        print(filename)
