---@generic TState
---@generic TArg
---@generic TResult
---@alias yazi.Sync fun(inner: fun(state: TState, arg: TArg): TResult): fun(arg: TArg): TResult

---@class yazi.Notification
---@field title string
---@field content string
---@field level 'info' | 'warn' | 'error'
---@field timeout number
---@class yazi.Ya
---@field err fun(...)
---@field dbg fun(...)
---@field notify fun(notification: yazi.Notification)
---@field sync yazi.Sync
ya = {}

---@class yazi.Rect
---@field x integer
---@field y integer
---@field width integer
---@field height integer

---@class yazi.Url
---@field frag string
---@field is_regular boolean
---@field is_search boolean
---@field is_archive boolean
---@field is_absolute boolean
---@field has_root boolean
---@field name fun(): string
---@field stem fun(): string
---@field join fun(url: yazi.Url | string): yazi.Url
---@field parent fun(): string
---@field starts_with fun(url: yazi.Url | string): boolean
---@field ends_with fun(url: yazi.Url | string): boolean
---@field strip_prefix fun(url: yazi.Url | string): yazi.Url
---@field __eq fun(another_url: yazi.Url | string): boolean
---@field __tostring fun(): string
---@field __concat fun(string): string
---@param url string
---@return yazi.Url
function Url(url) end

---@class yazi.Cha
---@field is_dir boolean Whether this file is a directory
---@field is_hidden boolean Whether this file is hidden (starts with a dot)
---@field is_link boolean Whether this file is a symlink
---@field is_orphan boolean Whether this file is a bad symlink, which points to a non-existent file
---@field is_dummy boolean Whether the file is dummy, which fails to load complete metadata, possibly the filesystem doesn't support it, such as FUSE.
---@field is_block boolean Whether this file is a block device
---@field is_char boolean Whether this file is a character device
---@field is_fifo boolean Whether this file is a fifo
---@field is_sock boolean Whether this file is a socket
---@field is_exec boolean Whether this file is executable
---@field is_sticky boolean Whether this file has the sticky bit set
---@field length integer The length of this file, returns an integer representing the size in bytes. Note that it can't reflect the size of a directory, use size() instead
---@field created number The created time of this file in Unix timestamp, or nil if it doesn't have a valid time
---@field modified number The modified time of this file in Unix timestamp, or nil if it doesn't have a valid time
---@field accessed number The accessed time of this file in Unix timestamp, or nil if it doesn't have a valid time
---@field permissions string Unix permissions of this file in string, e.g. drwxr-xr-x. For Windows, it's always nil
---@field uid number The user id of this file
---@field gid number The group id of this file
---@field nlink number The number of hard links to this file

---@class yazi.File
---@field url yazi.Url
---@field cha yazi.Cha
---@field link_to yazi.Url The Url of this file pointing to, if it's a symlink; otherwise, nil
---@field name string

---@class yazi.SeekState
---@field file yazi.File
---@field area yazi.Rect

---@class yazi.PeekState : yazi.SeekState
---@field skip number
---@field window yazi.Rect

---@generic TState
---@generic TOpts
---@alias yazi.Setup fun(state: TState, opts: TOpts)

---@class yazi.Plugin
---@field entry? fun()
---@field peek? fun(self: yazi.PeekState)
---@field seek? fun(self: yazi.SeekState)
---@field preload? fun(self: yazi.PeekState): 0 | 1 | 2 | 3
---@field setup? yazi.Setup

---@class yazi.Tasks
---@field progress { total: integer, succ: integer, fail: integer, found: integer, processed: integer }

---@class yazi.TabMode
---@field is_select boolean Whether the mode is select
---@field is_unset boolean Whether the mode is unset
---@field is_visual boolean Whether the mode is select or unset
---@class yazi.TabConfig
---@field sort_by 'name' | 'size' | 'time' | 'ext'
---@field sort_sensitive boolean
---@field sort_reverse boolean
---@field sort_dir_first boolean
---@field sort_translit boolean
---@field linemode 'normal' | 'relative' | 'absolute'
---@field show_hidden boolean
---@class yazi.TabSelected
---@class yazi.TabPreview
---@field skip number
---@field folder yazi.Folder
---@class yazi.Folder
---@field cwd yazi.Url The current working directory of this folder, which is a Url
---@field offset integer The offset of this folder, which is an integer
---@field cursor integer The cursor position of this folder, which is an integer
---@field window yazi.File[] A table of File in the visible area of this folder
---@field files yazi.File[] The folder::Files of this folder
---@field hovered yazi.File The hovered File of this folder, or nil if there is no hovered file
---@class yazi.FolderFile : yazi.File
---@field size fun(): integer | nil The size of this file, returns an integer representing the size in bytes, or nil if its a directory and it has not been evaluated
---@field mime fun(): string | nil The mime-type of this file, which is a string, or nil if it's a directory or hasn't been lazily calculated at all
---@field prefix fun(): string The prefix of this file relative to CWD, which used in the flat view during search. For instance, if CWD is /foo, and the file is /foo/bar/baz, then the prefix is bar/
---@field icon fun(): yazi.Icon | nil The Icon of this file, [icon] rules are applied; if no rule matches, returns nil
---@field style fun(): yazi.Style | nil The Style of this file, [filetype] rules are applied; if no rule matches, returns nil
---@field is_hovered fun(): boolean Whether this file is hovered
---@field is_yanked fun(): boolean Whether this file is yanked
---@field is_selected fun(): boolean Whether this file is selected
---@field found fun(): { idx: integer, all: integer } When users find a file using the find command, the status of the file - returns nil if it doesn't match the user's find keyword; otherwise, returns {idx, all}, where idx is the position of matched file, and all represents the number of all matched files.
---@field highlights fun(): any
---@class yazi.Icon
---@field text string
---@field style yazi.Style
---@alias yazi.Color string | 'reset' | 'black' | 'white' | 'red' | 'lightred' | 'green' | 'lightgreen' | 'yellow' | 'lightyellow' | 'blue' | 'lightblue' | 'magenta' | 'lightmagenta' | 'cyan' | 'lightcyan' | 'gray' | 'darkgray'
---@class yazi.Style
---@field fg fun(color: yazi.Color): yazi.Style Set the foreground color of the style, which accepts a Color
---@field bg fun(color: yazi.Color): yazi.Style Set the background color of the style, which accepts a Color
---@field bold fun(): yazi.Style Set the style to bold
---@field dim fun(): yazi.Style Set the style to dim
---@field italic fun(): yazi.Style Set the style to italic
---@field underline fun(): yazi.Style Set the style to underline
---@field blink fun(): yazi.Style Set the style to blink
---@field blink_rapid fun(): yazi.Style Set the style to blink rapidly
---@field reverse fun(): yazi.Style Set the style to reverse
---@field hidden fun(): yazi.Style Set the style to hidden
---@field crossed fun(): yazi.Style Set the style to crossed
---@field reset fun(): yazi.Style Reset the style
---@field patch fun(style: yazi.Style): yazi.Style Patch the style with another Style

---@class yazi.Tab
---@field mode yazi.TabMode
---@field conf yazi.TabConfig
---@field current yazi.Folder
---@field parent yazi.Folder
---@field selected yazi.TabSelected
---@field preview yazi.TabPreview
---@field name fun(): string

---@class yazi.SyncContext
---@field active yazi.Tab
---@field tabs { idx: integer }
---@field tasks yazi.Tasks
---@field yanked yazi.Url[]
cx = {}

---@type yazi.Plugin
local s = {
  setup = function(state, opts) end,
}
