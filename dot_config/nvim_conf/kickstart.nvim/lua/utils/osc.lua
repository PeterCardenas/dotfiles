local M = {}

--- Wrap an osc sequence with tmux-aware prefix and suffix
--- @param sequence string Sequence to wrap the tmux prefix and suffix around.
function M.osc(sequence)
  local osc_prefix ---@type string
  if vim.env.TMUX then
    -- Assume that tmux sessions in ssh sessions are nested.
    if vim.env.SSH_CONNECTION then
      osc_prefix = '\027Ptmux;\027\027Ptmux;\027\027\027\027'
    else
      osc_prefix = '\027Ptmux;\027\027'
    end
  else
    osc_prefix = '\027'
  end
  local osc_suffix ---@type string
  if vim.env.TMUX then
    if vim.env.SSH_CONNECTION then
      osc_suffix = '\a\027\027\\\\\027\\'
    else
      osc_suffix = '\a\027\\'
    end
  else
    osc_suffix = '\027\\'
  end
  return osc_prefix .. sequence .. osc_suffix
end

return M
