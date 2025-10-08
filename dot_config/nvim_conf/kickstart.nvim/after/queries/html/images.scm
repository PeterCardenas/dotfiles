; extends

(element
  (start_tag
    (tag_name) @_grandparent_tag
    (#eq? @_grandparent_tag "a"))
  (element
    (start_tag
      (tag_name) @_parent_tag
      (#eq? @_parent_tag "picture"))
    (element
      (start_tag
        (tag_name) @_tag
        (#eq? @_tag "img")
        (attribute
          (attribute_name) @_attr_name
          (#eq? @_attr_name "src")
          (quoted_attribute_value
            (attribute_value) @image.src)))))) @image
