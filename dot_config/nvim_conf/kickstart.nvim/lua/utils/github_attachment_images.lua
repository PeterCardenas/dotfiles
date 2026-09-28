local Async = require('utils.async')

local M = {}

local parse_async = Async.wrap(function(parser, done)
  parser:parse(false, function(err)
    done(err)
  end)
end, 2)

local yield_to_main_loop = Async.wrap(function(done)
  vim.defer_fn(done, 1)
end, 1)

---@param bodies { md: string?, html: string? }[]
---@param on_complete fun(mappings: table<string, string>)
function M.extract(bodies, on_complete)
  Async.void(function() ---@async
    yield_to_main_loop()
    local mappings = {} ---@type table<string, string>
    local languages = { 'markdown', 'markdown_inline', 'html' }

    for _, body in ipairs(bodies) do
      if type(body.md) == 'string' and type(body.html) == 'string' then
        local urls_with_range = {} ---@type [string, number, number][]
        for _, language in ipairs(languages) do
          local parser = vim.treesitter.get_string_parser(body.md, language)
          local err = parse_async(parser)
          if not err then
            parser:for_each_tree(function(tstree, tree)
              local query = vim.treesitter.query.get(tree:lang(), 'images')
              if not query then
                return
              end
              for _, match in query:iter_matches(tstree:root(), body.md, 0, -1) do
                for capture_id, nodes in pairs(match) do
                  if query.captures[capture_id] == 'image.src' then
                    nodes = type(nodes) == 'userdata' and { nodes } or nodes
                    local node = nodes[1]
                    local row, col = node:range()
                    urls_with_range[#urls_with_range + 1] = { vim.treesitter.get_node_text(node, body.md), row, col }
                  end
                end
              end
            end)
          end
          yield_to_main_loop()
        end

        table.sort(urls_with_range, function(a, b)
          return a[2] == b[2] and a[3] < b[3] or a[2] < b[2]
        end)
        local rendered_urls = {} ---@type string[]
        for url in body.html:gmatch(' src="([^"]+)"') do
          rendered_urls[#rendered_urls + 1] = url
        end
        for index, markdown_url in ipairs(urls_with_range) do
          local rendered_url = rendered_urls[index]
          if rendered_url then
            mappings[markdown_url[1]] = rendered_url
          end
        end
      end
    end

    on_complete(mappings)
  end)
end

return M
