"""Flutter create sonrasında Android release için INTERNET iznini güvenle ekler."""
from pathlib import Path

manifest = Path("android/app/src/main/AndroidManifest.xml")
if not manifest.exists():
    raise SystemExit(f"AndroidManifest.xml bulunamadı: {manifest}")
text = manifest.read_text(encoding="utf-8")
permission = '<uses-permission android:name="android.permission.INTERNET" />'
if permission not in text:
    ix = text.find(">")
    if ix == -1 or not text.lstrip().startswith("<manifest"):
        raise SystemExit("AndroidManifest.xml beklenen biçimde değil.")
    text = text[: ix + 1] + "\n    " + permission + text[ix + 1 :]
    manifest.write_text(text, encoding="utf-8")
print("Android internet izni hazır")
