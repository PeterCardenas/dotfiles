function stol --wraps stol --description 'Run stol after linking the shared hooks into projects that have none'
    set -l shared_hooks $HOME/.config/stol/hooks
    if test -d $shared_hooks
        set -l root /mnt/work
        set -q STOL_ROOT; and set root $STOL_ROOT
        # stol only reads <project>/.stol/hooks, so newly imported projects would otherwise skip cleanup hooks.
        for project in $root/projects/*/
            if not test -e $project.stol/hooks; and not test -L $project.stol/hooks
                mkdir -p $project.stol; and ln -s $shared_hooks $project.stol/hooks
            end
        end
    end
    command stol $argv
end
