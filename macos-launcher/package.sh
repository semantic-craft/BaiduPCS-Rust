#!/bin/bash
# Assemble from source; signing and notarization are explicit, separate operations.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
  echo 'Commit the reviewed source changes before assembling a distribution.' >&2
  exit 1
fi
bash macos-launcher/build.sh
CARGO_PROFILE_RELEASE_DEBUG=0 cargo build --locked --release --bin baidu-netdisk-rust --example desktop-config-check --manifest-path backend/Cargo.toml
(cd frontend && npm ci --ignore-scripts && npm run build)
APP="$PWD/macos-launcher/.build/BaiduPCS.app"
mkdir -p "$APP/Contents/Resources/backend"
cp backend/target/release/baidu-netdisk-rust "$APP/Contents/Resources/backend/"
cp backend/target/release/examples/desktop-config-check "$APP/Contents/Resources/"
cp -R frontend/dist/. "$APP/Contents/Resources/backend/frontend/"
cp LICENSE "$APP/Contents/Resources/UPSTREAM-LICENSE"
python3 - "$APP" <<'PY'
from pathlib import Path
import hashlib,json,subprocess,sys
root=Path.cwd();app=Path(sys.argv[1])
manifest={'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
'upstream':'https://github.com/komorebiCarry/BaiduPCS-Rust','fork':'https://github.com/semantic-craft/BaiduPCS-Rust',
'rustc':subprocess.check_output(['rustc','--version'],text=True).strip(),
'swift':subprocess.check_output(['xcrun','swift','--version'],text=True).splitlines()[0],
'node':subprocess.check_output(['node','--version'],text=True).strip(),
'lock_sha256':{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in ['backend/Cargo.lock','frontend/package-lock.json']}}
(app/'Contents/Resources/source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY
printf 'Assembled %s\nSign nested executables, then the App; notarize and staple before running.\n' "$APP"
