# appearance options
set -g urge_untracked_indicator "…"
set -g urge_git_color 928374
set -g urge_git_color_staged green
set -g urge_git_color_unstaged red
set -g urge_git_color_modified yellow
set -g urge_prompt_symbol "❯"
set -g urge_cwd_color normal
set -g urge_prompt_color_ok blue
set -g urge_prompt_color_error red

# state used for memoization and async storage
set -g __urge_cmd_id 0
set -g __urge_git_state_cmd_id -1

function __urge_set_dict -a type dir value
    set -l dict_name __urge'_'$type'_'(string escape --style=var $dir)
    set -g $dict_name $value
end

function __urge_get_dict -a type dir
    set -l dict_name __urge'_'$type'_'(string escape --style=var $dir)
    echo $$dict_name
end

function __urge_del_dict -a type dir
    set -l dict_name __urge'_'$type'_'(string escape --style=var $dir)
    set -e $dict_name
end

# Increment a counter each time a prompt is about to be displayed.
# Enables us to distingish between redraw requests and new prompts.
function __urge_increment_cmd_id --on-event fish_prompt
    set __urge_cmd_id (math $__urge_cmd_id + 1)
end

function __urge_job -a job_name callback cmd
    if set -q $job_name
        return 0
    end

    set -l job_result _job_result_(random)
    set -g $job_name
    set -U $job_result "…"

    fish -c "set -U $job_result (eval $cmd | string escape)" &
    set -l pid (jobs --last --pid)
    disown $pid

    function _job_$pid -v $job_result -V pid -V job_result -V callback -V job_name
        set -e $job_name
        eval $callback $$job_result
        functions -e _job_$pid
        set -e $job_result
    end
end

function __urge_git_info -a git_dir
    set -l prev_state (__urge_get_dict states $git_dir)
    # not a repaint, clear the state
    if test $__urge_cmd_id -ne $__urge_git_state_cmd_id
        set __urge_git_state_cmd_id $__urge_cmd_id
        __urge_del_dict branches $git_dir
        __urge_del_dict colors $git_dir
        __urge_del_dict states $git_dir
    end

    set -l branch (__urge_get_dict branches $git_dir)
    set -l state (__urge_get_dict states $git_dir)
    set -l branch_color (__urge_get_dict colors $git_dir)
    if test -z (string trim $branch_color)
        set branch_color $urge_git_color
    end

    # Fetch git position & action synchronously.
    # Memoize results to avoid recomputation on subsequent redraws.
    if test -z $branch
        set -l position (command git --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
        if test $status -ne 0
            # Denote detached HEAD state with short commit hash
            set position (command git --no-optional-locks rev-parse --short HEAD 2>/dev/null)
            if test $status -eq 0
                set position "@$position"
            end
        end

        # TODO: add bisect
        set -l action ""
        if test -f "$git_dir/.git/MERGE_HEAD"
            set action "merge"
        else if test -d "$git_dir/.git/rebase-merge"
            set action "rebase"
        else if test -d "$git_dir/.git/rebase-apply"
            set action "rebase"
        end

        set -l state $position
        if test -n $action
            set state "$state <$action>"
        end

        set branch $state
        __urge_set_dict branches $git_dir $branch
    end

    if test -z $state
        if set -q prev_state
            echo -sn (set_color --dim $branch_color) $branch $prev_state (set_color normal)
        end
        set -l cmd "echo -n $git_dir'X'; git --no-optional-locks status -unormal --ignore-submodules 2>&1 | string join X"
        __urge_job "__urge_git_check" __urge_git_callback $cmd
    else
        echo -sn (set_color $branch_color) $branch $state (set_color normal)
    end
end

function __urge_git_callback -a git_state
    set -l lines (string split "X" "$git_state")
    set -l git_dir (string trim $lines[1])
    set -l result
    set -l color $urge_git_color

    if string match -r "Changes to be committed" $git_state &>/dev/null
        set color $urge_git_color_staged
    end
    if string match -r "Changes not staged" $git_state &>/dev/null
        if test $color = $urge_git_color
            set color $urge_git_color_unstaged
        else
            set color $urge_git_color_modified
        end
    end
    if string match -r "Untracked files" $git_state &>/dev/null
        set result $urge_untracked_indicator
    end
    if test -z $result
        set result " "
    end
    __urge_set_dict states $git_dir "$result"
    __urge_set_dict colors $git_dir "$color"
    if status is-interactive
        commandline -f force-repaint
    end
end

function __urge_shortpwd --on-variable PWD
    if string match -q $PWD '/'
        set -g SHORTPWD '/'
        return
    end

    if string match -q $PWD $HOME
        set -g SHORTPWD '~'
        return
    end

    set -l path
    set -l fullpath
    set -l trimmedpath (echo $PWD | string replace "$HOME" '')
    if string match -q $trimmedpath $PWD
        set path ""
        set fullpath "/"
    else
        set path "~"
        set fullpath "$HOME"
    end
    set -l parts (echo $trimmedpath | string trim -l -r --chars=/' ' | string split '/')
    set -l current 0
    set -l length (count $parts)

    for part in $parts
        set current (math $current + 1)
        if test $current -eq $length
            set path "$path/$part"
            break
        end

        set -l depth 1
        set -l partsegment (string sub --length $depth $part)
        set -l matches (command find $fullpath -type d -maxdepth 1 -name "$partsegment*")
        while test (count $matches) -gt 1; and test $depth -lt (string length $part)
            set depth (math $depth + 1)
            set partsegment (string sub --length $depth $part)
            set matches (command find $fullpath -type d -maxdepth 1 -name "$partsegment*")
        end

        set path $path/$partsegment
        set fullpath $fullpath/$part
    end

    set -g SHORTPWD $path
end


function fish_prompt
    set -l exit_code $status
    if ! set -q SHORTPWD
        __urge_shortpwd
    end

    echo ""
    echo -s (set_color --dim $urge_git_color) (string repeat -n $COLUMNS "─")
    set_color $urge_cwd_color
    echo -n $SHORTPWD ""

    set -l git_dir (command git rev-parse --show-toplevel 2>/dev/null)
    if test -n "$git_dir"
        # we are in a git dir, so gather that info and refresh async state
        echo -sn (__urge_git_info $git_dir)
    end

    if test $exit_code -eq 0
        set_color $urge_prompt_color_ok
    else
        set_color $urge_prompt_color_error
    end
    echo -n $urge_prompt_symbol ""
    set_color normal
end
