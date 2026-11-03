#!/bin/zsh
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
cd "$task_root"
task_node="$task_root/build/node-v22.22.0-darwin-x64/bin/node"
task_cli="$task_root/build/uxp-tools/node_modules/@adobe/uxp-devtools-cli/src/uxp.js"
if [[ ! -x "$task_node" || ! -f "$task_cli" ]]; then
  print -u2 '请用 Adobe UXP Developer Tool 加载 PhotoshopPlugin/manifest.json；本机 CLI 工具尚未安装。'
  exit 1
fi
if ! /usr/sbin/lsof -n -P -iTCP:14001 -sTCP:LISTEN >/dev/null 2>&1; then
  nohup "$task_node" "$task_cli" service start > "$task_root/build/uxp-service.log" 2>&1 &
  for task_attempt in {1..30}; do
    if /usr/sbin/lsof -n -P -iTCP:14001 -sTCP:LISTEN >/dev/null 2>&1; then break; fi
    sleep 1
  done
fi
"$task_node" "$task_cli" plugin load --manifest "$task_root/PhotoshopPlugin/manifest.json" --apps PS
print '插件已加载。请在 Photoshop 的“增效工具 → PSD Mirror”打开面板。'
