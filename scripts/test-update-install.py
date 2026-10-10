"""Exercise the actual macOS installer helper using disposable signed apps."""
from pathlib import Path
import plistlib
import shutil
import shlex
import subprocess
import sys
import tempfile
import time

helper_source, executable = map(Path, sys.argv[1:])

def app_at(destination, version):
    (destination / "Contents/MacOS").mkdir(parents=True)
    shutil.copy2(executable, destination / "Contents/MacOS/Mirror")
    info = {"CFBundleIdentifier": "com.local.mirror", "CFBundleExecutable": "Mirror",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version,
            "CFBundleVersion": version}
    (destination / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(destination)], check=True, capture_output=True)

def version(app):
    return plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleShortVersionString"]

with tempfile.TemporaryDirectory(prefix="Mirror update ' $() ") as temporary:
    root = Path(temporary)
    for mode in ["success", "unarmed", "verification-failure", "rollback", "newer-installed"]:
        directory = root / mode
        stage = directory / "stage"
        stage.mkdir(parents=True)
        target, staged = directory / "Mirror.app", stage / "Mirror.app"
        app_at(target, "1.0.1" if mode == "newer-installed" else "1.0.0")
        app_at(staged, "2.0.0")
        current = plistlib.loads((target / "Contents/Info.plist").read_bytes())
        current["CFBundleShortVersionString"] = "1.0.0"
        (stage / "current.plist").write_bytes(plistlib.dumps(current))
        armed, restart = stage / "armed", stage / "restart"
        if mode != "unarmed": armed.touch()
        script = helper_source.read_text()
        if mode == "verification-failure":
            with (staged / "Contents/MacOS/Mirror").open("ab") as file: file.write(b"bad signature")
        if mode == "rollback":
            # Inject a final verification failure after replacement to exercise rollback.
            wrapper = stage / "verify.sh"
            wrapper.write_text('#!/bin/sh\ncase "$4" in *.update-*.app) exec /usr/bin/codesign "$@";; *) exit 1;; esac\n')
            wrapper.chmod(0o755)
            script = script.replace("/usr/bin/codesign --verify", shlex.quote(str(wrapper)) + " --verify")
        helper = stage / "install.sh"
        helper.write_text(script)
        parent = subprocess.Popen(["/bin/sleep", "30"])
        process = subprocess.Popen(["/bin/sh", str(helper), str(parent.pid), str(staged), str(target), str(armed), str(restart), "2.0.0"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            time.sleep(0.15)
            assert version(target) == ("1.0.1" if mode == "newer-installed" else "1.0.0"), "Must wait until the parent exits"
        finally:
            parent.terminate(); parent.wait()
        out, error = process.communicate(timeout=15)
        expected = "2.0.0" if mode == "success" else "1.0.1" if mode == "newer-installed" else "1.0.0"
        assert version(target) == expected, (mode, error.decode())
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(target)], check=True, capture_output=True)
        if mode in ["success", "unarmed", "newer-installed"]: assert process.returncode == 0, error.decode()
        else: assert process.returncode != 0
        print("macOS installation helper passed:", mode)
