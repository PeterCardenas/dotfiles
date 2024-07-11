# Remove files as completions.
complete -f -c cherry

complete -c cherry -l no_merge -f -d 'Do not merge main release branch'
