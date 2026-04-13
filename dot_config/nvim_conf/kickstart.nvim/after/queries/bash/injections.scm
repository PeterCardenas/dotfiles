; extends

; grep/egrep/rg/ag 'pattern' (pattern as first argument)
((command
  name: (command_name) @_command
  .
  argument: [
    (raw_string) @injection.content
    (string) @injection.content
  ])
  (#any-of? @_command "grep" "egrep" "rg" "ag")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  (#set! injection.language "regex"))

; grep/egrep/rg/ag [flags] 'pattern' (pattern after flags)
((command
  name: (command_name) @_command
  argument: (word) @_flag
  (#match? @_flag "^-")
  .
  argument: [
    (raw_string) @injection.content
    (string) @injection.content
  ])
  (#any-of? @_command "grep" "egrep" "rg" "ag")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  (#set! injection.language "regex"))

; find -regex/-iregex 'pattern'
((command
  name: (command_name) @_command
  argument: (word) @_flag
  (#any-of? @_flag "-regex" "-iregex")
  .
  argument: [
    (raw_string) @injection.content
    (string) @injection.content
  ])
  (#eq? @_command "find")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  (#set! injection.language "regex"))

; jq 'expression' (first argument)
((command
  name: (command_name) @_command
  .
  argument: [
    (raw_string) @injection.content
    (string) @injection.content
  ])
  (#eq? @_command "jq")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  (#set! injection.language "jq"))

; jq [flags/args] 'expression' (after any word argument)
((command
  name: (command_name) @_command
  argument: (word) @_word
  .
  argument: [
    (raw_string) @injection.content
    (string) @injection.content
  ])
  (#eq? @_command "jq")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  (#set! injection.language "jq"))

; gh --jq 'expression'
((command
  name: (command_name) @_command
  argument: (word) @_flag
  (#eq? @_flag "--jq")
  .
  argument: [
    (raw_string) @injection.content
    (string) @injection.content
  ])
  (#eq? @_command "gh")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  (#set! injection.language "jq"))

; tmux shell command — directly after subcommand (e.g., tmux run-shell 'cmd')
((command
  name: (command_name) @_command
  argument: (word) @_subcmd
  (#any-of? @_subcmd
    "new-session" "new-window" "split-window" "respawn-window" "respawn-pane" "display-popup"
    "run-shell" "if-shell" "pipe-pane" "neww" "splitw" "popup" "run")
  .
  argument: [
    (raw_string) @injection.content
    (string) @injection.content
  ])
  (#eq? @_command "tmux")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  (#set! injection.self))

; tmux shell command — after flags (e.g., tmux new-session -d -s name 'cmd')
((command
  name: (command_name) @_command
  argument: (word) @_subcmd
  (#any-of? @_subcmd
    "new-session" "new-window" "split-window" "respawn-window" "respawn-pane" "display-popup"
    "run-shell" "if-shell" "pipe-pane" "neww" "splitw" "popup" "run")
  argument: (_) @_arg
  .
  argument: [
    (raw_string) @injection.content
    (string) @injection.content
  ])
  (#eq? @_command "tmux")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  (#set! injection.self))

; nvim/vim -c 'command' (directly after -c flag)
((command
  name: (command_name) @_command
  argument: (word) @_flag
  (#eq? @_flag "-c")
  .
  argument: [
    (raw_string) @injection.content
    (string) @injection.content
  ])
  (#any-of? @_command "nvim" "vim")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  (#set! injection.language "vim"))

; nvim/vim [flags] -c 'command' (-c after other flags)
((command
  name: (command_name) @_command
  argument: (word) @_other
  (#match? @_other "^-")
  argument: (word) @_flag
  (#eq? @_flag "-c")
  .
  argument: [
    (raw_string) @injection.content
    (string) @injection.content
  ])
  (#any-of? @_command "nvim" "vim")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  (#set! injection.language "vim"))

; nvim/vim '+command' (first argument)
((command
  name: (command_name) @_command
  .
  argument: (raw_string) @injection.content)
  (#any-of? @_command "nvim" "vim")
  (#match? @injection.content "^'+")
  (#offset! @injection.content 0 2 0 -1)
  (#set! injection.language "vim"))

; nvim/vim [flags] '+command' (after flags)
((command
  name: (command_name) @_command
  argument: (word) @_flag
  (#match? @_flag "^-")
  .
  argument: (raw_string) @injection.content)
  (#any-of? @_command "nvim" "vim")
  (#match? @injection.content "^'+")
  (#offset! @injection.content 0 2 0 -1)
  (#set! injection.language "vim"))
