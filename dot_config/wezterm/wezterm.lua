local wezterm = require('wezterm')

local config = wezterm.config_builder()

config.color_scheme = 'Tokyo Night Storm'
config.font = wezterm.font({ family = 'MonaspiceKr Nerd Font' })
config.font_rules = {
  { italic = true, intensity = 'Bold', font = wezterm.font({ family = 'MonaspiceRn Nerd Font', weight = 'Bold' }) },
  { italic = true, font = wezterm.font({ family = 'MonaspiceRn Nerd Font' }) },
}
config.font_size = 13
config.harfbuzz_features = {
  'calt',
  'ss01',
  'ss02',
  'ss03',
  'ss04',
  'ss05',
  'ss08',
  'ss09',
  'liga',
}
config.window_decorations = 'NONE'
config.window_padding = {
  top = 0,
  bottom = 0,
  left = 0,
  right = 0,
}
config.enable_tab_bar = false
config.automatically_reload_config = true
config.strikethrough_position = '0.45cell'

wezterm.on('gui-startup', function(cmd)
  local _, _, window = wezterm.mux.spawn_window(cmd or {})
  window:gui_window():maximize()
end)

return config
