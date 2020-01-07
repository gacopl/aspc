#!/bin/bash
##############################################################
## aspc - AWS switch profile with credentials
## 
## easily swim through OKTA secured AWS accounts and roles
##
## Released under MIT License, Copyright (c) 2020 Michal Gacek
##############################################################

ASPC_SESSION_FILE_PREFIX=/tmp/aspc-autorefresher
ASPC_AUTOREFRESHER_LOCK=/run/lock/aspc_autorefresher_${USER}
ASPC_AUTOREFRESHER_ENABLED=true
ASPC_AUTOREFRESHER_RUN_EVERY=180
ASPC_REFRESH_THRESHOLD=10
ASPC_OKTA_MFA_SETTINGS="--mfa-factor-type push --mfa-provider OKTA"

ASPC_YELLOW=$(tput setaf 3)
ASPC_RED=$(tput setaf 1)
ASPC_GREEN=$(tput setaf 2)
ASPC_RESET=$(tput sgr0)
ASPC_PREFIX="${ASPC_YELLOW}["
ASPC_SUFFIX="${ASPC_YELLOW}]${ASPC_RESET}"
ASPC_STATUS_COL="${ASPC_RED}"
ASPC_STATUS_AR_SIGN=`echo -e "\U221E"`
ASPC_STATUS_AR_COL="${ASPC_GREEN}"

function asp() {
    rm ${ASPC_SESSION_FILE} &>/dev/null
    unset AWS_ACCESS_KEY_ID AWS_SECRET_KEY_ID AWS_OKTA_ASSUMED_ROLE AWS_OKTA_ASSUMED_ROLE_ARN AWS_OKTA_PROFILE AWS_OKTA_SESSION_EXPIRATION AWS_PROFILE AWS_SECRET_ACCESS_KEY AWS_SECURITY_TOKEN AWS_SESSION_TOKEN ASPC_SESSION_FILE
    AWS_PROFILE=${1:-$AWS_DEFAULT_PROFILE}
    if [[ `echo ${AWS_PROFILE} | grep '\.'` == "" ]]; then
        AWS_PROFILE=${AWS_PROFILE}.${AWS_DEFAULT_ROLE}
    fi
    export AWS_PROFILE
    export AWS_DEFAULT_ROLE=${AWS_PROFILE#*.}
    export AWS_DEFAULT_PROFILE=${AWS_PROFILE}
}

function __aspc_check_creds() {
    AWS_OKTA_PROFILE_EXP_CREDS=`awk '/\['${1}'\]/{flag=1;next}/\[.*\]/{flag=0}flag && NF {split($0,arr,"expiration = "); if (arr[2]) print arr[2] }' ~/.aws/credentials`
    if [ "${AWS_OKTA_PROFILE_EXP_CREDS}" == "" ]; then
        echo 0
    else
        echo $(( (${AWS_OKTA_PROFILE_EXP_CREDS} - `date +"%s"`) / 60 ))
    fi
}

function __aspc_autorefresher() {
    echo ${BASHPID} > ${ASPC_AUTOREFRESHER_LOCK}
    trap 'rm $ASPC_AUTOREFRESHER_LOCK' EXIT
    while true; do
        if [[ -f "${ASPC_AUTOREFRESHER_LOCK}" ]]; then
            for SESSION in `ls ${ASPC_SESSION_FILE_PREFIX}_${USER}_* | cut -d_ -f 3 | uniq`; do
                __aspc_refresh ${SESSION}
            done
            sleep 180 &
            wait $!
        else
            exit
        fi
    done
} 

function __aspc_refresh() {
    local PROFILE=${1}
    local EXPIRES_IN=`__aspc_check_creds ${PROFILE}`
    if [[ "${EXPIRES_IN}" -lt ${ASPC_REFRESH_THRESHOLD} ]]; then
        echo "Refreshing ${PROFILE} credentials"
        $(aws-okta write-to-credentials ${PROFILE} ~/.aws/credentials ${ASPC_OKTA_MFA_SETTINGS})
    fi
}

function __aspc_autorefresher_enable() {
    if [[ ! -f "${ASPC_AUTOREFRESHER_LOCK}" ]] || [[ ! $(ps $(<${ASPC_AUTOREFRESHER_LOCK}) &>/dev/null) -eq 0 ]]; then
        echo "Starting autorefresher in background for current and future aspc sessions"
        ( __aspc_autorefresher & disown ) &> /dev/null
    fi
}

function aspc() {
    [[ ${1} == "autooff" ]] && echo "Turning off autorefresher for all sessions" && ASPC_AUTOREFRESHER_ENABLED=false && kill $(<${ASPC_AUTOREFRESHER_LOCK}) && sleep 1 && return
    [[ ${1} == "autoon" ]] && ASPC_AUTOREFRESHER_ENABLED=true && __aspc_autorefresher_enable && sleep 1 && return
    asp ${1}
    [[ "${AWS_DEFAULT_PROFILE}" == "wr-login.${AWS_DEFAULT_ROLE}" ]] && echo "Credential process found in config will not autorefresh" && return
    local TIMESTAMP=`date +"%s"`
    export ASPC_SESSION_FILE="${ASPC_SESSION_FILE_PREFIX}_${USER}_${AWS_DEFAULT_PROFILE}_${TIMESTAMP}"
    touch ${ASPC_SESSION_FILE}
    __aspc_refresh ${AWS_DEFAULT_PROFILE}
    [[ "${ASPC_AUTOREFRESHER_ENABLED}" == true ]] && __aspc_autorefresher_enable
    trap 'rm ${ASPC_SESSION_FILE}' EXIT
}

function aspe {
    asp ${1}
    $(aws-okta env ${AWS_PROFILE} ${ASPC_OKTA_MFA_SETTINGS})
}

function __asp_expiry() {
    ASPC_PREFIX+=${AWS_DEFAULT_PROFILE}
    if [[ "${AWS_OKTA_SESSION_EXPIRATION}" != "" ]]; then
        echo ${ASPC_PREFIX} ${ASPC_STATUS_COL}"*$(( (${AWS_OKTA_SESSION_EXPIRATION} - `date +"%s"`) / 60 ))m"${ASPC_SUFFIX}
    else
        if [[ -f "${ASPC_AUTOREFRESHER_LOCK}" ]] && [[ $(ps $(<${ASPC_AUTOREFRESHER_LOCK}) &>/dev/null) -eq 0 ]]; then
            if [[ "${ASPC_SESSION_FILE}" != "" ]]; then 
                echo ${ASPC_PREFIX} ${ASPC_STATUS_AR_COL}^${ASPC_STATUS_AR_SIGN}${ASPC_SUFFIX}
            elif [[ $(ls ${ASPC_SESSION_FILE_PREFIX}_${USER}_${AWS_DEFAULT_PROFILE}_* 2>/dev/null | wc -l) -gt 0 ]];then
                local EXPIRES_IN=`__aspc_check_creds ${AWS_DEFAULT_PROFILE}`
                echo ${ASPC_PREFIX} ${ASPC_STATUS_COL}^${ASPC_STATUS_AR_SIGN} ${EXPIRES_IN}m${ASPC_SUFFIX}
            else
                local EXPIRES_IN=`__aspc_check_creds ${AWS_DEFAULT_PROFILE}` 
                if [[ "$EXPIRES_IN" -gt 0 ]]; then
                    echo ${ASPC_PREFIX} ${ASPC_STATUS_COL}"^${EXPIRES_IN}m"${ASPC_SUFFIX}
                else
                    echo ${ASPC_PREFIX}${ASPC_SUFFIX}
                fi
            fi
        else
            local EXPIRES_IN=`__aspc_check_creds ${AWS_DEFAULT_PROFILE}` 
            if [[ "$EXPIRES_IN" -gt 0 ]]; then
                echo ${ASPC_PREFIX} ${ASPC_STATUS_COL}"^${EXPIRES_IN}m"${ASPC_SUFFIX}
            else
                echo ${ASPC_PREFIX}${ASPC_SUFFIX}
            fi
        fi
    fi
}

_asp_completions() {
  COMPREPLY=($(compgen -W "$(grep '\[profile' ~/.aws/config | sed -n 's/\[profile \(.*\).*\]/\1/p' | sort)" -- "${COMP_WORDS[1]}"))
}

_aspc_completions() {
  COMPREPLY=("autoon" "autooff" $(compgen -W "$(grep '\[profile' ~/.aws/config | sed -n 's/\[profile \(.*\).*\]/\1/p' | sort)" -- "${COMP_WORDS[1]}"))
}

complete -F _asp_completions asp aspe
complete -F _aspc_completions aspc