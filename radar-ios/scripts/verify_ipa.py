"""Validate packaged metadata before publishing a re-signable Radar IPA."""
import plistlib
import sys
import zipfile
from pathlib import PurePosixPath

def verify(path):
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        infos = [n for n in names if n.endswith("/Info.plist") and
                 (n.count("/") == 2 or ("/PlugIns/" in n and n.count("/") == 4))]
        if len(infos) != 2:
            raise ValueError("Expected one app and one embedded extension")
        bundles = {}
        for name in sorted(infos):
            info = plistlib.loads(archive.read(name))
            for key in ("CFBundleIdentifier", "CFBundleExecutable", "CFBundleDisplayName",
                        "CFBundleName", "CFBundleVersion", "CFBundleShortVersionString"):
                value = info.get(key)
                if not isinstance(value, str) or not value.strip() or "$(" in value:
                    raise ValueError(f"{name}: invalid or absent {key}")
            executable = str(PurePosixPath(name).parent / info["CFBundleExecutable"])
            if executable not in names:
                raise ValueError(f"{name}: executable missing")
            bundles["extension" if "/PlugIns/" in name else "app"] = info
            print(f"Validated {info['CFBundleDisplayName']} build {info['CFBundleVersion']}")
        app, extension = bundles["app"], bundles["extension"]
        if extension["CFBundleVersion"] != app["CFBundleVersion"]:
            raise ValueError("App and extension build versions differ")
        if not extension["CFBundleIdentifier"].startswith(app["CFBundleIdentifier"] + "."):
            raise ValueError("Extension bundle ID must be nested under app ID")
        config = extension.get("NSExtension", {})
        if config.get("NSExtensionPointIdentifier") != "com.apple.broadcast-services-upload":
            raise ValueError("Broadcast extension point is invalid")
        if config.get("RPBroadcastProcessMode") != "RPBroadcastProcessModeSampleBuffer":
            raise ValueError("ReplayKit sample-buffer mode missing")
        principal = config.get("NSExtensionPrincipalClass", "")
        if not principal or "$(" in principal:
            raise ValueError("Broadcast principal class invalid")

if __name__ == "__main__":
    verify(sys.argv[1])
