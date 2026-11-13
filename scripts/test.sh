#!/usr/bin/env bash
# 规则测试的唯一入口：README、CI 与本地都调用它，避免源文件列表漂移。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p neatquit/build/Tests

swiftc \
  neatquit/NeatQuit/RuleStore.swift \
  neatquit/NeatQuit/ScheduledAction.swift \
  neatquit/NeatQuit/ScheduledActionStore.swift \
  neatquit/NeatQuit/ScheduledActionScheduler.swift \
  neatquit/NeatQuit/ScheduledDisk.swift \
  neatquit/NeatQuit/DiskAccess.swift \
  neatquit/Tests/main.swift \
  -o neatquit/build/Tests/neatquit-rules-test

./neatquit/build/Tests/neatquit-rules-test
