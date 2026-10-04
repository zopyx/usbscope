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
    local views="overview ports devices cables thunderbolt usb4 security json"
    local commands="check watch baseline report"
    local opts="-v --verbose --json --watch --no-color --expect --events --interval --format --out -h --help --version"

    case "${prev}" in
        --watch | --interval)
            # free-form number of seconds; no completion
            return 0
            ;;
        --format)
            COMPREPLY=($(compgen -W "md html" -- "${cur}"))
            return 0
            ;;
        --out | save | check)
            COMPREPLY=($(compgen -f -- "${cur}"))
            return 0
            ;;
    esac

    if [[ "${cur}" == -* ]]; then
        COMPREPLY=($(compgen -W "${opts}" -- "${cur}"))
        return 0
    fi

    # only one view or command is accepted; offer them until one is on the line
    local word seen=0
    for word in "${COMP_WORDS[@]:1}"; do
        case " ${views} ${commands} " in
            *" ${word} "*) seen=1 ;;
        esac
    done
    if [[ ${seen} -eq 0 ]]; then
        COMPREPLY=($(compgen -W "${views} ${commands} ${opts}" -- "${cur}"))
    else
        COMPREPLY=($(compgen -W "${opts}" -- "${cur}"))
    fi
    return 0
}

complete -F _usbscope usbscope
