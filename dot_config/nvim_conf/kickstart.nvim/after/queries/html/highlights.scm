; extends

; conceal comments for octo.nvim
((comment) @conceal
  (#maybe-conceal-whole-line! @conceal))

; conceal cursor.com anchor tags
((element
  (start_tag
    (tag_name) @_tag
    (#eq? @_tag "a")
    (attribute
      (attribute_name) @_attr
      (#eq? @_attr "href")
      (quoted_attribute_value
        (attribute_value) @_val
        (#match? @_val "^https://cursor\\.com"))))) @conceal
  (#set! conceal_lines ""))

(element
  (start_tag
    (tag_name) @_tag
    (#eq? @_tag "img")
    (attribute
      (attribute_name) @_attr_name
      (#eq? @_attr_name "src")
      (quoted_attribute_value
        (attribute_value))))
  (#set! image.ignore ""))
