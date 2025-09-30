; extends

(source
  (tag
    (name) @comment.warning @nospell
    ":" @punctuation.delimiter)
  (#any-of? @comment.warning "ASSERT" "SETUP" "TEST" "PRECONDITION" "POSTCONDITION"))
