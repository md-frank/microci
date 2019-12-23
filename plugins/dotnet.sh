#!/usr/bin/env bash

set -o pipefail
set -o nounset

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

function build() {
    echo "Start compiling $PROJ_NAME..."
    dotnet build -c Debug -o $OUT_TMP_DIR "$SRC_DIR/src/$PROJ_PREFIX$PROJ_NAME"
    if [[ $? != 0 ]]; then
        local msg="你提交到Git的代码已编译失败，请检查后重新提交。\r\n变更记录：$GIT_COMMIT_URLS"
        [[ $PUSH_IM == "pushDingding" ]] && msg="@$GIT_FULL_NAME $msg"
        ./microci.sh $PUSH_IM "$msg" "$GIT_FULL_NAME"

        echo "compiling $PROJ_NAME fail"
        return 1
    fi

    # sync
    kill_proj $PROJ_NAME
    cp -dfru $OUT_TMP_DIR/* $OUT_DIR/
}

function run() {
    # sync configs
    cp -rfu $SRC_DIR/src/$PROJ_PREFIX$PROJ_NAME/confs/* "$OUT_DIR/confs/"

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

    if requireBuild $PROJ_NAME && build $PROJ_NAME ; then
        run $PROJ_NAME
    elif requireRestart ; then
        kill_proj $PROJ_NAME
        run $PROJ_NAME
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
}

#========== main func begin ==========

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