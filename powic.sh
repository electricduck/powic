#!/usr/bin/env bash

USAGE="                     _
 _ __   _____      _(_) ___
| '_ \ / _ \ \ /\ / / |/ __|
| |_) | (_) \ V  V /| | (__
| .__/ \___/ \_/\_/ |_|\___|
|_|=========================

Usage:
    powic [pwsh-command]
    powic [verb] [parameters]

Available Verbs:
    help | ?            Prints this, dingus
    invoke | i          Executes the [parameters] as a command in PowerShell.
                        Running powic without a [verb] does this regardless
                        invokes the command, however, explicitly calling \`invoke\`
                        does multiple things:
                        * More explictness in scripts!
                        * Bypasses PowerShell's own parameters
                        * Bypasses the check to see if you're already inside
                          a container, as this may be a false error to you
                        See examples below for more help
    print-vars          Prints exported variables used for configuring powic
    update-pwsh | u     Pulls an updated PowerShell image from the repository

Variables
    Configuring powic is done via environment variables. See your shell/OS
    docs on how to set these. Unsetting them will reset the options to default.

    POWIC_CONFIG_DIR        (todo)
    POWIC_DEBUG             (todo)
    POWIC_HOSTNAME_CMD      (todo)
    POWIC_IMAGE_SOURCE      (todo)
    POWIC_IMAGE_TAG         (todo)
    POWIC_PODMAN_ARGS       (todo)
    POWIC_PWSH_ARGS         (todo)
    POWIC_PWSH_ARGS_INLINE  (todo)
    POWIC_UPDATE_ON_INVOKE  (todo)
    POWIC_WORKDIR           (todo)

Examples:
    powic invoke -?
        As mentioned above, this bypasses PowerShell and sends all parameters
        to the -Command parameter, thus causing a ParserError as PowerShell
        attempts to run just \"-?\"

"

function echoc() {
    MESSAGE=${@:2}
    TYPE=$1

    OUTPUT=""

    case $TYPE in
        debug)
            if [[ $POWIC_DEBUG == true ]]; then
                OUTPUT="\033[0;33m$MESSAGE"
            fi
        ;;
        error)
            OUTPUT="\033[1;31m$MESSAGE"
        ;;
        info)
            OUTPUT="\033[0;34m$MESSAGE"
        ;;
        new)
            OUTPUT=""
        ;;
        *)
            OUTPUT="$TYPE $MESSAGE"
        ;;
    esac

    echo -e "$OUTPUT \033[0m"
}

function set_export() {
    if [[ ! -n $(eval "echo \$$1") ]]; then
        eval "$1"='$2'
    fi
}

POWIC_ARGS=$@
POWIC_ARGS_PARAMS=${@:2}
POWIC_ARGS_VERB=$1

set_export "POWIC_CONFIG_DIR" "$HOME/.local/share/powic/"
set_export "POWIC_DEBUG" false
set_export "POWIC_HOSTNAME_CMD" "powic-\$(echo \$RANDOM | md5sum | head -c 7)"
set_export "POWIC_IMAGE_SOURCE" "mcr.microsoft.com"
set_export "POWIC_IMAGE_TAG" "latest"
set_export "POWIC_PODMAN_ARGS" ""
set_export "POWIC_PWSH_ARGS" ""
set_export "POWIC_PWSH_ARGS_INLINE" "-NoProfile"
set_export "POWIC_UPDATE_ON_INVOKE" false
set_export "POWIC_WORKDIR" "$HOME"

POWIC_IMAGE="$POWIC_IMAGE_SOURCE/powershell:$POWIC_IMAGE_TAG"
POWIC_PWSH_CONFIG="$POWIC_CONFIG_DIR/powershell.config.json"
POWIC_PATH="$(realpath -s "$0")" # Handle missing GNUtools

function invoke() {
    function build_cmd() {
        CMD+="$1 "
    }

    ARGS=$@
    CMD=""
    NAME=$(echo $(eval echo $POWIC_HOSTNAME_CMD))

    build_cmd "podman run -it --rm --privileged --userns=keep-id"
    build_cmd "--name $NAME"
    build_cmd "--hostname $NAME"
    build_cmd "--volume $POWIC_WORKDIR:$POWIC_WORKDIR"
    build_cmd "--workdir $POWIC_WORKDIR"
    build_cmd "$POWIC_PODMAN_ARGS"
    build_cmd "$POWIC_IMAGE"
    build_cmd "/usr/bin/pwsh"

    build_cmd "-NoLogo"
    build_cmd "-SettingsFile $POWIC_PWSH_CONFIG"

    if [[ -n "$@" ]]; then
        if { [[ "$@" == -* ]] && [[ ! $POWIC_ARGS_VERB =~ ^(i|invoke)$ ]]; }; then
            build_cmd "$POWIC_PWSH_ARGS $ARGS"
        else
            build_cmd "$POWIC_PWSH_ARGS_INLINE -Command \"& { $ARGS }\""
        fi
    fi

    if [[ $POWIC_UPDATE_ON_INVOKE == true ]]; then
        echoc info "Updating $POWIC_IMAGE..."
        updatepwsh > /dev/null 2>&1
    fi

    echoc debug $CMD
    eval $CMD
}

function printvars() {
    echo "POWIC_DEBUG: $POWIC_DEBUG"
    echo "POWIC_HOSTNAME_CMD: $POWIC_HOSTNAME_CMD"
    echo "POWIC_IMAGE_SOURCE $POWIC_IMAGE_SOURCE"
    echo "POWIC_IMAGE_TAG: $POWIC_IMAGE_TAG"
    echo "POWIC_PODMAN_ARGS: $POWIC_PODMAN_ARGS"
    echo "POWIC_PWSH_ARGS: $POWIC_PWSH_ARGS"
    echo "POWIC_PWSH_ARGS_INLINE: $POWIC_PWSH_ARGS_INLINE"
    echo "POWIC_WORKDIR: $POWIC_WORKDIR"
}

function setup() {
    mkdir -p $POWIC_CONFIG_DIR
    touch $POWIC_PWSH_CONFIG
}

# TODO: Check if pwsh isn't actually PowerShell!
# TODO: Check if /usr/local/ is actually wrtiable if installing there
function togglealias() {
    DIR=""

    if { [[ $(id -u) == 0 ]] && [[ -f "/usr/local/bin/powic" ]]; }; then
        DIR="/usr/local/bin"
    else
        DIR="$HOME/.local/bin"
    fi

    mkdir -p $DIR
    INSTALL_PATH="$DIR/pwsh"

    if [[ -f $INSTALL_PATH ]]; then
        echoc info "Removing \`pwsh\` alias from $INSTALL_PATH..."
        rm $INSTALL_PATH
    else
        echoc info "Installing \`pwsh\` alias into $INSTALL_PATH..."
        echo "#!/usr/bin/env bash
$POWIC_PATH \$@" > $INSTALL_PATH
        chmod +x $INSTALL_PATH
    fi
}

function updatepwsh() {
    eval "podman pull $POWIC_IMAGE"
}

if { [[ -f "/run/.containerenv" ]] && [[ ! $POWIC_ARGS_VERB =~ ^("?"|i|invoke|help)$ ]]; }; then
    echoc error "Inside a container. Will not run!"
    exit
fi

setup

case $POWIC_ARGS_VERB in
    invoke|i)
        invoke $POWIC_ARGS_PARAMS
    ;;
    help|"?")
        echo "$USAGE"
    ;;
    print-hostname)
        echo $(eval echo $POWIC_HOSTNAME_CMD)
    ;;
    print-vars)
        printvars
    ;;
    toggle-alias|install-alias)
        togglealias
    ;;
    update-pwsh|update-image|u)
        updatepwsh
    ;;
    *)
        invoke $POWIC_ARGS
    ;;
esac
