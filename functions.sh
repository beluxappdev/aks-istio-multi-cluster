#!/usr/bin/env bash

##
# Prints and executes a command
#
# takes 1 parameter - the string command to run
#
# usage: pe "ls -l"
#
##

# Error handling
function handle_error {
    echo -e "${ERROR_COLOR}Error: ${BASH_COMMAND} at line ${BASH_LINENO[0]}.$NC"
    exit 1
}


trap 'handle_error $LINENO' ERR

function pe() {
    echo -e "${PE_COLOR}$@${NC}"
    eval "$@"
}

# Validate prerequisites
function validate_prerequisites {
    command -v az >/dev/null 2>&1 || { echo >&2 "Azure CLI (az) is not installed. Aborting."; exit 1; }
    command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl is not installed. Aborting."; exit 1; }
    command -v istioctl >/dev/null 2>&1 || { echo >&2 "istioctl is not installed. Aborting."; exit 1; }
}