#!/usr/bin/env bash

set -o pipefail
set -o nounset

# Version 1.0.1

#========== config begin ==========

_COMMON_BUILD_FILES=(
    ".cs" ".csproj" ".sln"
)
_COMMON_RESTART_FILES=(
    "appsettings.json"
)

declare -A FUNCTIONS
FUNCTIONS=(
    ["buildOrRun"]='
    OPTION:
    $1 - Project Name
    '
)

declare -A PUSH_USER_DICT

#========== config end ==========

function requireBuild() {
    local buildPaths=(${COMMON_BUILD_PATHS[@]} $1)
    for e in ${CHGS[@]}; do
        local hasChg=0
        for e2 in ${buildPaths[@]}; do
            [[ $e =~ $PROJ_PREFIX$e2 ]] && hasChg=1 && break
        done

        if [[ $hasChg == 1 ]]; then
            for e2 in ${COMMON_BUILD_FILES[@]}; do
                [[ $e =~ $e2 ]] && hasChg=1 && break
            done

            [[ $hasChg == 1 ]] && return 0
        fi
    done

    return 1
}

function requireRestart() {
    for e in ${CHGS[@]}; do
        for e2 in ${COMMON_RESTART_FILES[@]}; do
            [[ $e =~ $e2 ]] && return 0
        done
    done
    return 1
}

function kill_proj() {
    kill $(ps -ef | grep "$PROJ_PREFIX$1" | tr -s " " | cut -d " " -f2) >/dev/null 2>&1
}

function pushMsg() {
    local msg=$1
    local user=${PUSH_USER_DICT[$GIT_LOGIN_NAME]:-}
    [ -z $user ] && echo "dotnet.cfg is not configured for $GIT_LOGIN_NAME" && return 1

    [[ $PUSH_IM == "pushDingding" ]] && msg="@$user $msg"
    ./microci.sh $PUSH_IM "$msg" "$user"
}

function build() {
    echo "Start compiling $PROJ_NAME..."
    dotnet build -c Debug -o $OUT_TMP_DIR "$SRC_DIR/src/$PROJ_PREFIX$PROJ_NAME"
    local exitCode=$?
    if [[ $exitCode != 0 ]]; then
        echo "compiling $PROJ_NAME fail, exitCode:$exitCode"
        pushMsg "你提交到Git的代码已编译失败，请检查后重新提交。\r\n变更记录：$GIT_COMMIT_URLS"

        return 1
    fi

    # sync
    kill_proj $PROJ_NAME
    cp -rf $OUT_TMP_DIR/* $OUT_DIR/
    if [ $? != 0 ]; then
        echo "Failed to copy binary file: $OUT_TMP_DIR -> $OUT_DIR"
        pushMsg "你提交到Git的代码编译成功，但复制失败。\r\n变更记录：$GIT_COMMIT_URLS"

        return 1
    fi
}

function run() {
    # sync configs
    cp -rf $SRC_DIR/src/$PROJ_PREFIX$PROJ_NAME/confs/* "$OUT_DIR/confs/"
    if [ $? != 0 ]; then
        echo "Failed to copy confs file: $SRC_DIR/src/$PROJ_PREFIX$PROJ_NAME/confs -> $OUT_DIR/confs"
        pushMsg "你提交到Git的代码同步配置文件失败。\r\n变更记录：$GIT_COMMIT_URLS"

        return 1
    fi

    export ASPNETCORE_ENVIRONMENT=Development
    export ASPNETCORE_URLS="http://localhost:$SVCE_PORT"
    export WEB_ROOT_PATH=$SVCE_WEBROOT
    pushd $OUT_DIR >/dev/null
    setsid dotnet "$PROJ_PREFIX$PROJ_NAME.dll" >$LOG_FILE 2>&1 &
    popd >/dev/null

    echo "Service $PROJ_NAME has been rerun"
}

function buildOrRun() {
    [[ ! -f ${CHGS_FILE:-} ]] && echo '$CHGS_FILE undefined' && exit 1

    CHGS=($(cat $CHGS_FILE))

    if requireBuild $PROJ_NAME; then
        if ! build $PROJ_NAME || ! run $PROJ_NAME; then
            exit 1
        fi
    elif requireRestart; then
        kill_proj $PROJ_NAME
        ! run $PROJ_NAME && exit 1
    else
        echo "Project $PROJ_NAME no effective changes"
    fi
}

function initVars() {
    OUT_DIR=$OUT_DIR/$1
    OUT_TMP_DIR=${OUT_DIR}_tmp
    LOG_FILE=$OUT_DIR/console.log
    COMMON_BUILD_PATHS=($COMMON_BUILD_PATHS)
    COMMON_BUILD_FILES=($COMMON_BUILD_FILES)
    COMMON_RESTART_FILES=($COMMON_RESTART_FILES)

    readConfig
}

function readConfig() {
    local cfgFileName=$SHELL_FOLDER/dotnet.cfg
    [ ! -f $cfgFileName ] && return 1

    while read -r line; do
        local arr=(${line//=/ })
        PUSH_USER_DICT[${arr[0]}]=${arr[1]}
    done <$cfgFileName
}

#========== main func begin ==========

SHELL_FOLDER=$(dirname $(readlink -f "$0"))
ACTION=${1:-help} && shift
set +o nounset
optTxt=${FUNCTIONS[$ACTION]}
set -o nounset
if [[ -z $optTxt ]]; then
    for i in $(echo ${!FUNCTIONS[*]}); do
        echo "$i ${FUNCTIONS[$i]}"
        echo ""
    done
else
    initVars $1
    $ACTION "$@"
fi

#========== main func end ==========
