function stol_project_dir --description 'Print the stol project directory for a project dir or one of its checkouts' -a target
    set -l project
    if test -d "$target/.repo/.git"
        set project (path resolve -- "$target")
    else
        set -l common_dir (git -C "$target" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); or return 1
        string match --quiet -- '*/.repo/.git' "$common_dir"; or return 1
        set project (path dirname (path dirname "$common_dir"))
    end
    # stol lays projects out as <STOL_ROOT>/projects/<project>/.repo; a stray .repo elsewhere is not stol.
    test (path basename (path dirname "$project")) = projects; or return 1
    printf '%s\n' "$project"
end
