# Default appearance options. Override in config.fish if you want.
if ! set -q urge_untracked_indicator
    set -g urge_untracked_indicator "…"
end

if ! set -q urge_unstaged_indicator
    set -g urge_unstaged_indicator "+"
end

if ! set -q urge_staged_color
    set -g urge_staged_color green
end

if ! set -q urge_unstaged_color
    set -g urge_unstaged_color red
end

if ! set -q urge_clean_color
    set -g urge_clean_color 928374
end

set -g urge_git_color $urge_clean_color

if ! set -q urge_prompt_symbol
    set -g urge_prompt_symbol "❯"
end

# This should be set to be at least as long as urge_unstaged_indicator and urge_untracked_indicator combined, due to a fish bug
if ! set -q urge_clean_indicator
    set -g urge_clean_indicator ""
    # set -g urge_clean_indicator (string replace -r -a '.' ' ' $urge_untracked_indicator$urge_unstaged_indicator)
end

if ! set -q urge_cwd_color
    set -g urge_cwd_color normal
end

if ! set -q urge_prompt_color_ok
    set -g urge_prompt_color_ok blue
end

if ! set -q urge_prompt_color_error
    set -g urge_prompt_color_error red
end

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

function fish_prompt
    set -l exit_code $status
    set -l cwd (pwd | string replace "$HOME" '~')

    echo ''
    set_color $urge_cwd_color
    echo -sn $cwd
    set_color normal

    if test $cwd != '~'
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
