# appearance options
set -g urge_right_prompt_color 928374
set -g __urge_rp_cmd_id -1

function fish_right_prompt
    if test $__urge_cmd_id -ne $__urge_rp_cmd_id
        set -g __urge_rp_cmd_id $__urge_cmd_id
        set -e __urge_rp_state
    end

    if set -q __urge_rp_state
        echo -sn (set_color $urge_right_prompt_color) $__urge_rp_state (set_color normal)
    else
        set -l cmd "node -v | cut -dv -f2; npm -v"
        __urge_job "__urge_refresh_rp" __urge_rp_callback $cmd
    end

end

function __urge_rp_callback -a node_version npm_version
    set -g __urge_rp_state "node@$node_version npm@$npm_version"
    if status is-interactive
        commandline -f force-repaint
    end
end
