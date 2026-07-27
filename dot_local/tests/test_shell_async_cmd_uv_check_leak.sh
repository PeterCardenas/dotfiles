#!/usr/bin/env bash
# Regression test for the nvim idle-memory leak: utils/shell.lua's
# `Shell.async_cmd` must not leak libuv handles.
#
# Root cause (see /tmp/nvim-leak-findings.md from the investigation that
# found this): the old plenary.job-based implementation allocated a
# uv_check_t handle per Job (job.lua:178), then Job:start() allocated a
# SECOND one via _reset() (job.lua:447), orphaning the first. On completion
# job.lua only called uv.check_stop() then set the field to nil -- it never
# called handle:close(). Every completed Job therefore permanently leaked two
# uv_check_t handles, and libuv keeps a handle's Lua closure (which pinned a
# full copy of the process environment) alive until it is closed. Amplified
# by a ~1 Hz poll loop in plugins/tmux.lua, this leaked multiple GB/day on an
# otherwise idle session.
#
# This test runs N Shell.async_cmd calls through a real headless nvim and
# asserts the uv_check_t handle count (via vim.uv.walk) does not grow beyond
# a small constant slack. It fails against the old plenary.job
# implementation (proven: 200 calls -> +400 check handles) and passes
# against the vim.system-based implementation (proven: +0).
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
nvim_src=$(cd "$script_dir/../../dot_config/nvim_conf/kickstart.nvim" && pwd)

if ! command -v nvim >/dev/null 2>&1; then
  echo "SKIP: nvim not found on PATH" >&2
  exit 1
fi

plenary_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/plenary.nvim"
if [ ! -d "$plenary_dir" ]; then
  echo "SKIP: plenary.nvim not found at $plenary_dir (Shell.async_cmd's Async.wrap depends on it)" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

census_script="$tmp/census.lua"
cat >"$census_script" <<'EOF'
local SRC = os.getenv('SHELL_TEST_SRC')
vim.opt.rtp:prepend(SRC)

local Async = require('utils.async')
local Shell = require('utils.shell')

local N = 200

---@return table<string, integer>
local function census()
  local counts = {}
  vim.uv.walk(function(h)
    local ok, t = pcall(h.get_type, h)
    local key = ok and t or 'unknown'
    counts[key] = (counts[key] or 0) + 1
  end)
  return counts
end

local before = census()

Async.run(function()
  for i = 1, N do
    local ok = Shell.async_cmd('echo', { 'leak-check-' .. i })
    if not ok then
      io.write('FAIL: command ' .. i .. ' failed unexpectedly\n')
      os.exit(1)
    end
  end

  -- Let the event loop run a couple of ticks for any pending close
  -- callbacks before taking the final census.
  Shell.sleep(50)

  local after = census()
  local before_check = before['check'] or 0
  local after_check = after['check'] or 0
  local growth = after_check - before_check

  -- A real fix shows ~0 growth; the old leak showed +2 per call (+400 for
  -- N=200). Allow a small constant slack for anything incidental to setup.
  local max_allowed_growth = 5

  io.write(string.format('uv_check_t before=%d after=%d growth=%d (N=%d calls)\n', before_check, after_check, growth, N))

  if growth > max_allowed_growth then
    io.write(string.format(
      'FAIL: uv_check_t handle count grew by %d after %d Shell.async_cmd calls (allowed <= %d) -- handle leak detected.\n',
      growth,
      N,
      max_allowed_growth
    ))
    os.exit(1)
  end

  io.write(string.format('PASS: uv_check_t handle growth (%d) within allowed slack (%d) after %d calls.\n', growth, max_allowed_growth, N))
  os.exit(0)
end, function() end)
EOF

SHELL_TEST_SRC="$nvim_src" timeout 30 nvim --headless -u NONE --noplugin -c "luafile $census_script" 2>&1
