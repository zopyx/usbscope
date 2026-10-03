# bash completion for usbscope. Install:
#   mkdir -p ~/.local/share/bash-completion/completions
#   cp scripts/completions/usbscope.bash \
#       ~/.local/share/bash-completion/completions/usbscope
# (bash 4.4+ loads that directory automatically; otherwise `source` the file
# from ~/.bashrc.)

_usbscope() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD - 1]}"
    local views="overview ports devices cables thunderbolt json"
    local opts="-v --verbose --json --watch --no-color -h --help --version"

    case "${prev}" in
        --watch)
            # free-form number of seconds; no completion
            return 0
            ;;
    esac

    if [[ "${cur}" == -* ]]; then
        COMPREPLY=($(compgen -W "${opts}" -- "${cur}"))
        return 0
    fi

    # only one view is accepted; offer the views until one is on the line
    local word view_seen=0
    for word in "${COMP_WORDS[@]:1}"; do
        case " ${views} " in
            *" ${word} "*) view_seen=1 ;;
        esac
    done
    if [[ ${view_seen} -eq 0 ]]; then
        COMPREPLY=($(compgen -W "${views} ${opts}" -- "${cur}"))
    else
        COMPREPLY=($(compgen -W "${opts}" -- "${cur}"))
    fi
    return 0
}

complete -F _usbscope usbscope
