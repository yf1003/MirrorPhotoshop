#!/bin/zsh
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
task_app="$task_root/build/Mac/Build/Products/Debug/PSDMirrorMac.app"
if [[ ! -d "$task_app" ]]; then /bin/zsh "$task_root/Scripts/build.sh" mac; fi
open "$task_app"
