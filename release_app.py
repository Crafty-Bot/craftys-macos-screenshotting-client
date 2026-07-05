#!/usr/bin/env python3
"""Build, sign, notarize, install, and restart CraftyCannon.

Prerequisites for the default full release flow:
  1. Xcode Command Line Tools are installed.
  2. A "Developer ID Application" certificate is available in Keychain.
  3. Notary credentials are stored, for example:
       xcrun notarytool store-credentials craftycannon-notary \
         --apple-id "you@example.com" \
         --team-id "TEAMID" \
         --password "APP_SPECIFIC_PASSWORD"

Useful examples:
  ./release_app.py
  ./release_app.py --notary-profile my-profile
  ./release_app.py --install-dir "$HOME/Applications"
  ./release_app.py --skip-notarize
"""

from __future__ import annotations

import argparse
import os
import plistlib
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Iterable


APP_NAME = "CraftyCannon"
DEFAULT_NOTARY_PROFILE = "craftycannon-notary"
DEFAULT_DEPLOYMENT_TARGET = "13.0"


class ReleaseError(RuntimeError):
    """A release step failed."""


def log(message: str = "") -> None:
    print(message, flush=True)


def run(
    args: list[str],
    *,
    cwd: Path | None = None,
    check: bool = True,
    capture: bool = False,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    printable = " ".join(str(part) for part in args)
    log(f"$ {printable}")
    return subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        check=check,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        env=env,
    )


def capture(args: list[str], *, cwd: Path | None = None, check: bool = True) -> str:
    completed = run(args, cwd=cwd, check=check, capture=True)
    return completed.stdout or ""


def require_path(path: str) -> str:
    resolved = shutil.which(path)
    if resolved is None:
        raise ReleaseError(f"Required tool not found on PATH: {path}")
    return resolved


def xcrun_find(tool: str) -> str:
    try:
        found = capture(["/usr/bin/xcrun", "--find", tool]).strip()
    except subprocess.CalledProcessError as exc:
        output = exc.stdout or ""
        raise ReleaseError(f"Missing Xcode tool: {tool}\n{output}".rstrip()) from exc
    if not found:
        raise ReleaseError(f"Missing Xcode tool: {tool}")
    return found


def security_identities() -> list[str]:
    completed = subprocess.run(
        ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    identities: list[str] = []
    for line in completed.stdout.splitlines():
        if '"' not in line:
            continue
        try:
            identities.append(line.split('"', 2)[1])
        except IndexError:
            continue
    return identities


def choose_identity(requested: str | None, *, notarize: bool) -> str:
    if requested:
        return requested

    identities = security_identities()
    preferences = ["Developer ID Application:"]
    if not notarize:
        preferences.extend(["Apple Development:", "Sign to Run Locally", "Mac Development:"])

    for prefix in preferences:
        for identity in identities:
            if prefix in identity:
                return identity

    if notarize:
        raise ReleaseError(
            "No 'Developer ID Application' signing identity found in Keychain.\n"
            "Install your Developer ID certificate, or pass --skip-notarize for a local build."
        )

    return "-"


def read_info_plist(info_plist: Path) -> dict:
    with info_plist.open("rb") as handle:
        return plistlib.load(handle)


def sanitize_metadata(target: Path) -> None:
    commands = [
        ["/usr/bin/xattr", "-c", str(target)],
        ["/usr/bin/xattr", "-r", "-d", "com.apple.provenance", str(target)],
        ["/usr/bin/xattr", "-r", "-d", "com.apple.quarantine", str(target)],
        ["/usr/bin/xattr", "-r", "-d", "com.apple.macl", str(target)],
        ["/usr/bin/xattr", "-r", "-d", "com.apple.FinderInfo", str(target)],
        ["/usr/bin/xattr", "-r", "-d", "com.apple.fileprovider.fpfs#P", str(target)],
    ]
    for command in commands:
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def strip_codesign_detritus(target: Path) -> None:
    subprocess.run(["/usr/bin/xattr", "-cr", str(target)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    sanitize_metadata(target)
    for child in target.rglob("*"):
        if child.name == ".DS_Store" or child.name.startswith("._"):
            try:
                child.unlink()
            except FileNotFoundError:
                pass


def copy_with_ditto(source: Path, destination: Path) -> None:
    if destination.exists() or destination.is_symlink():
        remove_path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    run(["/usr/bin/ditto", str(source), str(destination)])


def remove_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def swift_sources(root_dir: Path) -> list[str]:
    sources = sorted((root_dir / "Sources").glob("*.swift"))
    if not sources:
        raise ReleaseError("No Swift source files found in Sources/.")
    return [str(source) for source in sources]


def build_app(
    *,
    root_dir: Path,
    app_name: str,
    app_dir: Path,
    deployment_target: str,
    identity: str,
    bundle_id: str,
    clean: bool,
) -> None:
    log("Building app bundle...")

    if clean:
        remove_path(root_dir / "dist" / f"{app_name}.app")

    macos_dir = app_dir / "Contents" / "MacOS"
    resources_dir = app_dir / "Contents" / "Resources"
    module_cache = root_dir / ".build" / "module-cache"
    info_src = root_dir / "Resources" / "Info.plist"
    info_dst = app_dir / "Contents" / "Info.plist"

    if not info_src.exists():
        raise ReleaseError(f"Missing Info.plist: {info_src}")

    macos_dir.mkdir(parents=True, exist_ok=True)
    resources_dir.mkdir(parents=True, exist_ok=True)
    module_cache.mkdir(parents=True, exist_ok=True)

    arch = platform.machine()
    target = f"{arch}-apple-macos{deployment_target}"
    swiftc = xcrun_find("swiftc")
    sdkroot = capture(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"]).strip()

    swift_args = [
        swiftc,
        "-sdk",
        sdkroot,
        "-O",
        "-target",
        target,
        "-framework",
        "Cocoa",
        "-framework",
        "SwiftUI",
        "-framework",
        "Combine",
        "-framework",
        "Carbon",
        "-framework",
        "CoreGraphics",
        "-framework",
        "CoreText",
        "-framework",
        "CoreImage",
        "-framework",
        "ImageIO",
        "-framework",
        "Security",
        "-framework",
        "UserNotifications",
        "-framework",
        "Vision",
        "-o",
        str(macos_dir / app_name),
    ]
    swift_args.extend(swift_sources(root_dir))

    env = os.environ.copy()
    env["CLANG_MODULE_CACHE_PATH"] = str(module_cache)
    env["SWIFT_MODULE_CACHE_PATH"] = str(module_cache)
    run(swift_args, cwd=root_dir, env=env)

    log("Copying resources...")
    for item in (root_dir / "Resources").iterdir():
        destination = resources_dir / item.name
        if item.is_dir():
            copy_with_ditto(item, destination)
        else:
            shutil.copy2(item, destination)

    sanitize_metadata(resources_dir)
    shutil.copy2(info_src, info_dst)
    resource_info = resources_dir / "Info.plist"
    if resource_info.exists():
        resource_info.unlink()

    (app_dir / "Contents" / "PkgInfo").write_text("APPL????", encoding="ascii")
    strip_codesign_detritus(app_dir)

    log(f"Codesigning with identity: {identity if identity != '-' else 'ad-hoc'}")
    sign_command = ["/usr/bin/codesign", "--force", "--deep"]
    if identity == "-":
        sign_command.extend(["--sign", "-", "--timestamp=none", "--identifier", bundle_id])
    else:
        sign_command.extend(["--options", "runtime", "--sign", identity, "--timestamp"])
    sign_command.append(str(app_dir))
    run(sign_command)

    strip_codesign_detritus(app_dir)
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose", str(app_dir)], capture=True)


def ensure_developer_id_signature(app_dir: Path) -> None:
    details = capture(["/usr/bin/codesign", "-dv", "--verbose=4", str(app_dir)], check=False)
    if "Authority=Developer ID Application" not in details:
        relevant = [
            line
            for line in details.splitlines()
            if line.startswith(("Authority=", "TeamIdentifier=", "Identifier=", "Timestamp="))
        ]
        raise ReleaseError(
            "App is not signed with 'Developer ID Application'. Notarization will fail.\n"
            + "\n".join(relevant)
        )


def notarize_app(
    *,
    app_dir: Path,
    app_name: str,
    work_dir: Path,
    out_zip: Path,
    profile: str,
) -> Path:
    xcrun_find("notarytool")
    xcrun_find("stapler")

    notary_app = work_dir / f"{app_name}.app"
    notary_zip = work_dir / f"{app_name}.zip"

    log("Preparing clean notarization copy...")
    copy_with_ditto(app_dir, notary_app)
    strip_codesign_detritus(notary_app)

    log("Checking Developer ID signature...")
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose", str(notary_app)], capture=True)
    ensure_developer_id_signature(notary_app)

    log("Creating notarization zip...")
    remove_path(notary_zip) if notary_zip.exists() else None
    run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(notary_app), str(notary_zip)])

    log(f"Submitting to Apple notary service (profile: {profile})...")
    run(["/usr/bin/xcrun", "notarytool", "submit", str(notary_zip), "--keychain-profile", profile, "--wait"])

    log("Stapling notarization ticket...")
    run(["/usr/bin/xcrun", "stapler", "staple", "-v", str(notary_app)])

    log("Assessing with Gatekeeper...")
    spctl = subprocess.run(
        ["/usr/sbin/spctl", "-a", "-vv", "--type", "execute", str(notary_app)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if spctl.stdout:
        print(spctl.stdout, end="")
    if spctl.returncode != 0:
        log("Warning: Gatekeeper assessment returned a non-zero status. The app was still notarized and stapled.")

    out_zip.parent.mkdir(parents=True, exist_ok=True)
    copy_with_ditto(notary_zip, out_zip)
    log(f"Notarized zip: {out_zip}")
    return notary_app


def default_install_dir() -> Path:
    system_applications = Path("/Applications")
    if system_applications.exists() and os.access(system_applications, os.W_OK):
        return system_applications
    user_applications = Path.home() / "Applications"
    user_applications.mkdir(parents=True, exist_ok=True)
    return user_applications


def app_is_running(process_name: str) -> bool:
    return subprocess.run(
        ["/usr/bin/pgrep", "-x", process_name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0


def quit_app(*, app_name: str, bundle_id: str, timeout: float) -> None:
    if not app_is_running(app_name):
        return

    log(f"Quitting running {app_name}...")
    subprocess.run(
        ["/usr/bin/osascript", "-e", f'tell application id "{bundle_id}" to quit'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not app_is_running(app_name):
            return
        time.sleep(0.5)

    log(f"{app_name} did not quit in time; sending SIGTERM.")
    subprocess.run(["/usr/bin/pkill", "-TERM", "-x", app_name], check=False)
    time.sleep(1)

    if app_is_running(app_name):
        log(f"{app_name} is still running; sending SIGKILL.")
        subprocess.run(["/usr/bin/pkill", "-KILL", "-x", app_name], check=False)


def install_app(*, source_app: Path, install_dir: Path, app_name: str) -> Path:
    install_dir.mkdir(parents=True, exist_ok=True)
    target_app = install_dir / f"{app_name}.app"
    log(f"Installing app: {target_app}")
    copy_with_ditto(source_app, target_app)
    sanitize_metadata(target_app)
    return target_app


def relaunch_app(app_path: Path) -> None:
    log(f"Launching app: {app_path}")
    run(["/usr/bin/open", str(app_path)])


def existing_files(paths: Iterable[Path]) -> list[Path]:
    return [path for path in paths if path.exists() or path.is_symlink()]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build, sign, notarize, install, and restart CraftyCannon.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--app-name", default=APP_NAME)
    parser.add_argument("--deployment-target", default=DEFAULT_DEPLOYMENT_TARGET)
    parser.add_argument(
        "--codesign-identity",
        default=os.environ.get("CRAFTYCANNON_CODESIGN_IDENTITY"),
        help="Signing identity. Defaults to the first Developer ID Application identity.",
    )
    parser.add_argument(
        "--notary-profile",
        default=os.environ.get("CRAFTYCANNON_NOTARY_PROFILE", DEFAULT_NOTARY_PROFILE),
        help="notarytool keychain profile.",
    )
    parser.add_argument(
        "--install-dir",
        type=Path,
        default=Path(os.environ["CRAFTYCANNON_INSTALL_DIR"]) if os.environ.get("CRAFTYCANNON_INSTALL_DIR") else None,
        help="Where the finished .app is installed. Defaults to /Applications when writable, otherwise ~/Applications.",
    )
    parser.add_argument(
        "--out-zip",
        type=Path,
        default=Path(os.environ["CRAFTYCANNON_NOTARIZED_ZIP"])
        if os.environ.get("CRAFTYCANNON_NOTARIZED_ZIP")
        else None,
        help="Path for the exported notarized zip.",
    )
    parser.add_argument("--skip-notarize", action="store_true", help="Build, sign, install, and restart without notarization.")
    parser.add_argument("--skip-restart", action="store_true", help="Install without relaunching the app.")
    parser.add_argument("--skip-install", action="store_true", help="Build and notarize without replacing the installed app.")
    parser.add_argument("--keep-work", action="store_true", help="Keep the temporary working directory for inspection.")
    parser.add_argument("--no-clean", action="store_true", help="Do not remove dist/CraftyCannon.app before building.")
    parser.add_argument("--quit-timeout", type=float, default=10.0, help="Seconds to wait for the running app to quit.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root_dir = Path(__file__).resolve().parent
    dist_dir = root_dir / "dist"
    dist_app = dist_dir / f"{args.app_name}.app"
    info_plist = root_dir / "Resources" / "Info.plist"
    info = read_info_plist(info_plist)
    bundle_id = info.get("CFBundleIdentifier", "com.crafty599.craftycannon")
    out_zip = args.out_zip or (dist_dir / "releases" / f"{args.app_name}-notarized.zip")
    install_dir = args.install_dir or default_install_dir()

    require_path("python3")
    for absolute_tool in ["/usr/bin/xcrun", "/usr/bin/codesign", "/usr/bin/security", "/usr/bin/ditto", "/usr/bin/xattr"]:
        if not Path(absolute_tool).exists():
            raise ReleaseError(f"Required tool not found: {absolute_tool}")

    identity = choose_identity(args.codesign_identity, notarize=not args.skip_notarize)

    work_root = Path(tempfile.mkdtemp(prefix="craftycannon-release."))
    try:
        build_app_dir = work_root / "build" / f"{args.app_name}.app"

        log(f"Workspace: {root_dir}")
        log(f"Working directory: {work_root}")
        log(f"Install directory: {install_dir}")
        log()

        build_app(
            root_dir=root_dir,
            app_name=args.app_name,
            app_dir=build_app_dir,
            deployment_target=args.deployment_target,
            identity=identity,
            bundle_id=bundle_id,
            clean=not args.no_clean,
        )

        dist_dir.mkdir(parents=True, exist_ok=True)
        copy_with_ditto(build_app_dir, dist_app)
        sanitize_metadata(dist_app)
        log(f"Built app: {dist_app}")

        finished_app = dist_app
        if not args.skip_notarize:
            finished_app = notarize_app(
                app_dir=dist_app,
                app_name=args.app_name,
                work_dir=work_root / "notary",
                out_zip=out_zip,
                profile=args.notary_profile,
            )
        else:
            log("Skipping notarization by request.")

        if not args.skip_install:
            quit_app(app_name=args.app_name, bundle_id=bundle_id, timeout=args.quit_timeout)
            installed_app = install_app(source_app=finished_app, install_dir=install_dir, app_name=args.app_name)
            if not args.skip_restart:
                relaunch_app(installed_app)
        else:
            log("Skipping install by request.")

        log()
        log("Release complete.")
        log(f"Built app: {dist_app}")
        if not args.skip_notarize:
            log(f"Notarized zip: {out_zip}")
        if not args.skip_install:
            log(f"Installed app: {install_dir / (args.app_name + '.app')}")
        return 0
    finally:
        if args.keep_work:
            log(f"Keeping work directory: {work_root}")
        else:
            shutil.rmtree(work_root, ignore_errors=True)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as exc:
        if exc.stdout:
            print(exc.stdout, end="")
        print(f"\nCommand failed with exit code {exc.returncode}: {' '.join(exc.cmd)}", file=sys.stderr)
        raise SystemExit(exc.returncode)
    except ReleaseError as exc:
        print(f"\nRelease failed: {exc}", file=sys.stderr)
        raise SystemExit(2)
