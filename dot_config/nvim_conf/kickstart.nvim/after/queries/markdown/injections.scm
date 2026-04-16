; extends

(fenced_code_block
  (info_string
    (language) @_label
    (#agentic-fence-path-inject! @_label))
  (code_fence_content) @injection.content)

((inline) @injection.content
  (#lua-match? @injection.content "^%s*import")
  (#set! injection.language "typescript"))

((inline) @injection.content
  (#lua-match? @injection.content "^%s*export")
  (#set! injection.language "typescript"))

((inline) @injection.content
  (#agentic-bash-tool-call-inject! @injection.content))
