# Default appearance options. Override in config.fish if you want.
set -g urge_untracked_indicator "…"
set -g urge_unstaged_indicator "+"
set -g urge_staged_color green
set -g urge_unstaged_color red
set -g urge_clean_color 928374
set -g urge_git_color $urge_clean_color
set -g urge_prompt_symbol "❯"
set -g urge_clean_indicator ""
set -g urge_cwd_color normal
set -g urge_prompt_color_ok blue
set -g urge_prompt_color_error red

# State used for memoization and async calls.
set -g __urge_cmd_id 0
set -g __urge_git_state_cmd_id -1
set -g __urge_git_static ""
set -g __urge_dirty ""

# Increment a counter each time a prompt is about to be displayed.
# Enables us to distingish between redraw requests and new prompts.
function __urge_increment_cmd_id --on-event fish_prompt
    set __urge_cmd_id (math $__urge_cmd_id + 1)
end

# Abort an in-flight dirty check, if any.
function __urge_abort_check
    if set -q __urge_check_pid
        set -l pid $__urge_check_pid
        functions -e __urge_on_finish_$pid
        command kill $pid >/dev/null 2>&1
        set -e __urge_check_pid
    end
end

function __urge_git_status
    # Reset state if this call is *not* due to a redraw request
    set -l prev_dirty $__urge_dirty
    if test $__urge_cmd_id -ne $__urge_git_state_cmd_id
        __urge_abort_check

        set __urge_git_state_cmd_id $__urge_cmd_id
        set __urge_git_static ""
        set __urge_dirty ""
    end

    # Fetch git position & action synchronously.
    # Memoize results to avoid recomputation on subsequent redraws.
    if test -z $__urge_git_static
        # Determine git working directory
        set -l git_dir (command git --no-optional-locks rev-parse --absolute-git-dir 2>/dev/null)
        if test $status -ne 0
            return 1
        end

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
        if test -f "$git_dir/MERGE_HEAD"
            set action "merge"
        else if test -d "$git_dir/rebase-merge"
            set branch "rebase"
        else if test -d "$git_dir/rebase-apply"
            set branch "rebase"
        end

        set -l state $position
        if test -n $action
            set state "$state <$action>"
        end

        set -g __urge_git_static $state
    end

    # Fetch dirty status asynchronously.
    if test -z $__urge_dirty
        if ! set -q __urge_check_pid
            # Compose shell command to run in background
            set -l cmd '\
                set -l git_state (git --no-optional-locks status -unormal --ignore-submodules 2>&1)
                set -l result 0
                if string match -r "Changes to be committed" $git_state
                    set result (math $result + 5)
                end
                if string match -r "Changes not staged" $git_state
                    set result (math $result + 3)
                end
                if string match -r "Untracked files" $git_state
                    set result (math $result + 1)
                end
                exit $result\
                ' | string escape

            begin
                # Defer execution of event handlers by fish for the remainder of lexical scope.
                # This is to prevent a race between the child process exiting before we can get set up.
                block -l

                set -g __urge_check_pid 0
                command fish --private --command "$cmd" >/dev/null 2>&1 &
                set -l pid (jobs --last --pid)

                set -g __urge_check_pid $pid

                # Use exit code to convey dirty status to parent process.
                function __urge_on_finish_$pid --inherit-variable pid --on-process-exit $pid
                    functions -e __urge_on_finish_$pid

                    if set -q __urge_check_pid
                        if test $pid -eq $__urge_check_pid
                            set -g __urge_dirty_state $argv[3]
                            if status is-interactive
                                commandline -f repaint
                            end
                        end
                    end
                end
            end
        end

        if set -q __urge_dirty_state
            switch $__urge_dirty_state
                case 9
                    set -g __urge_dirty $urge_unstaged_indicator$urge_untracked_indicator
                    set -g urge_git_color $urge_staged_color
                case 8
                    set -g __urge_dirty $urge_unstaged_indicator
                    set -g urge_git_color $urge_staged_color
                case 6
                    set -g __urge_dirty $urge_untracked_indicator
                    set -g urge_git_color $urge_staged_color
                case 5
                    set -g __urge_dirty $urge_clean_indicator
                    set -g urge_git_color $urge_staged_color
                case 4
                    set -g __urge_dirty $urge_untracked_indicator
                    set -g urge_git_color $urge_unstaged_color
                case 3
                    set -g __urge_dirty $urge_clean_indicator
                    set -g urge_git_color $urge_unstaged_color
                case 1
                    set -g __urge_dirty $urge_untracked_indicator
                    set -g urge_git_color $urge_clean_color
                case 0
                    set -g __urge_dirty $urge_clean_indicator
                    set -g urge_git_color $urge_clean_color
            end

            set -e __urge_check_pid
            set -e __urge_dirty_state
        end
    end

    # Render git status. When in-progress, use previous state to reduce flicker.
    set_color $urge_git_color
    echo -n $__urge_git_static

    if ! test -z $__urge_dirty
        echo -n $__urge_dirty
    else if ! test -z $prev_dirty
        set_color --dim $urge_git_color
        echo -n $prev_dirty
        set_color normal
    end

    set_color normal
end

function urge_update_shortpwd --on-variable PWD
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
        urge_update_shortpwd
    end

    echo ''
    set_color $urge_cwd_color
    echo -sn $SHORTPWD
    set_color normal

    if ! string match -q $SHORTPWD '~'
        set -l git_state (__urge_git_status)
        if test $status -eq 0
            echo -sn " $git_state"
        end
    end

    if test $exit_code -eq 0
        set_color $urge_prompt_color_ok
    else
        set_color $urge_prompt_color_error
    end
    echo -n " $urge_prompt_symbol "
    set_color normal
end
