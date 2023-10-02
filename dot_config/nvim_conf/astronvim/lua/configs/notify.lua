local notify = require "notify"
notify.setup(astronvim.user_plugin_opts("plugins.notify", { stages = "fade" }))
vim.notify = function(msg, ...)
    if msg:match("warning: multiple different client offset_encodings") then
        return
    end

    notify(msg, ...)
end
