local Async = require('utils.async')
local Log = require('utils.log')
local String = require('utils.string')
M = {}

---Run a shell command synchronously and return the output.
---@param cmd string
---@return boolean, string[]
function M.sync_cmd(cmd)
  local result = vim.fn.system(cmd)
  local output = String.split_lines(result)
  return vim.v.shell_error == 0, output
end

---@class ShellAsyncOpts
---@field cwd? string
---@field stdin? string
---@field detach? boolean

---@class ShellCmdOutput: string[]
---@field stdout string[]
---@field stderr string[]

---Build a `vim.system` stream handler that incrementally splits raw chunks
---into complete lines, appending each line to the combined `output` list and
---its per-channel sub-list in true arrival order.
---
---`vim.system`'s streaming `stdout`/`stderr` callbacks deliver raw chunks that
---can split in the middle of a line, so lines must be buffered per-channel
---and only emitted once a newline (or stream close) completes them. This
---mirrors `plenary.job`'s internal line buffering, which is what the previous
---implementation relied on to receive already-line-buffered data.
---@param output ShellCmdOutput
---@param channel 'stdout' | 'stderr'
---@return fun(err: string?, data: string?)
local function make_stream_handler(output, channel)
  ---@type string?
  local pending = nil
  return function(_, data)
    if data == nil then
      -- Stream closed: flush a trailing line that never got a newline. An
      -- empty `pending` means the stream ended cleanly on a newline (or had
      -- no output at all), so there is nothing left to flush -- otherwise
      -- every command would gain a spurious trailing blank line.
      if pending and pending ~= '' then
        table.insert(output, pending)
        table.insert(output[channel], pending)
      end
      pending = nil
      return
    end
    -- Match plenary's normalization: strip carriage returns up front.
    data = (pending or '') .. data:gsub('\r', '')
    pending = nil
    local index = 1
    while true do
      local newline_index = data:find('\n', index, true)
      if not newline_index then
        pending = data:sub(index)
        break
      end
      table.insert(output, data:sub(index, newline_index - 1))
      table.insert(output[channel], data:sub(index, newline_index - 1))
      index = newline_index + 1
    end
  end
end

---@type async fun(cmd: string, args: string[], opts: ShellAsyncOpts | nil): (boolean, ShellCmdOutput)
M.async_cmd = Async.wrap(
  ---@param cmd string
  ---@param args string[]
  ---@param opts ShellAsyncOpts | nil
  ---@param done fun(success: boolean, output: ShellCmdOutput)
  ---@return nil
  function(cmd, args, opts, done)
    opts = opts or {}

    ---@type ShellCmdOutput
    local output = {
      stdout = {},
      stderr = {},
    }

    vim.system(vim.list_extend({ cmd }, args), {
      cwd = opts.cwd,
      stdin = opts.stdin,
      detach = opts.detach,
      stdout = make_stream_handler(output, 'stdout'),
      stderr = make_stream_handler(output, 'stderr'),
      -- vim.system merges this into the inherited environment (unless
      -- clear_env is set), so there is no need to copy vim.fn.environ()
      -- ourselves as the old plenary.job path did.
      --
      -- Behavior change worth knowing about: vim.system's base_env() also sets
      -- NVIM=v:servername in the child, which the old plenary.job path did not.
      -- That is deliberate and matches what nvim's own jobstart/:terminal do --
      -- `nvim-git` unconditionally runs `nvim --server "$NVIM"` and so requires
      -- it, and `lazygit_nvim.fish` branches on it to remote into the running
      -- instance instead of nesting a new one. Set clear_env if a future caller
      -- ever needs a child that must NOT see it.
      env = { GH_TOKEN = GH_TOKEN },
    }, function(result)
      -- vim.system's on_exit runs in a fast-event context (libuv callback,
      -- not scheduled onto the main loop), where most nvim_* API calls raise
      -- E5560. Reschedule before resuming the caller's coroutine so `done`
      -- and everything after it can safely call vim.api.
      vim.schedule(function()
        ---@type boolean, string
        local ok, err = pcall(done, result.code == 0, output)
        if not ok then
          Log.notify_error(
            'Error calling done callback:' .. err .. '\ncmd: ' .. cmd .. '\nargs: ' .. vim.inspect(args) .. '\nOutput: ' .. table.concat(output, '\n')
          )
        end
      end)
    end)
  end,
  4
)

---Sleep asynchrnously for a given number of milliseconds.
---@type async fun(ms: number)
M.sleep = Async.wrap(
  ---@param ms number
  ---@param done fun(): nil
  function(ms, done)
    vim.defer_fn(function()
      done()
    end, ms)
  end,
  2
)
return M
