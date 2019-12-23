#!/usr/bin/env bash

set -o pipefail
set -o nounset

#========== config begin ==========

export PUSH_IM="pushWechat"
export PUSH_WX_TOKEN="wxpusher.zjiecode.com需要的appToken"
export PUSH_WX_DEFUID="如果代码提交者没有绑定微信UID，使用此处的默认值"

# 项目前缀
export PROJ_PREFIX="Mondol.Example."

declare -A SVCE_PORTS
SVCE_PORTS=(
    ["Api"]="5001"
    ["Identity"]="5002"
)

declare -A SVCE_WEBROOTS
SVCE_WEBROOTS=(
    ["Api"]="/data/microci/aowu_be/master/repo/src/wwwroot"
    ["Identity"]="/data/microci/aowu_be/master/repo/src/wwwroot"
)

_COMMON_BUILD_PATHS=(
    "Common" "Db" "Caching" "Service"
)
_COMMON_BUILD_FILES=(
    ".cs" ".csproj" ".sln" "DocDesc.txt"
)
_COMMON_RESTART_FILES=(
    "appsettings.json"
)

#========== config end ==========

function exportVars() {
    SVCE_WEBROOTS_RAW=""
    for i in ${!_SVCE_WEBROOTS[*]}; do
        SVCE_WEBROOTS_RAW+="$i:${_SVCE_WEBROOTS[$i]} "
    done
    export SVCE_WEBROOTS_RAW

    SVCE_PORTS_RAW=""
    for i in ${!_SVCE_PORTS[*]}; do
        SVCE_PORTS_RAW+="$i:${_SVCE_PORTS[$i]} "
    done
    export SVCE_PORTS_RAW
}

#========== main func begin ==========

export COMMON_BUILD_PATHS="${_COMMON_BUILD_PATHS[@]}"
export COMMON_BUILD_FILES="${_COMMON_BUILD_FILES[@]}"
export COMMON_RESTART_FILES="${_COMMON_RESTART_FILES[@]}"

for i in "${!SVCE_PORTS[@]}"; do
    export PROJ_NAME=$i
    export SVCE_PORT=${SVCE_PORTS[$i]}
    export SVCE_WEBROOT=${SVCE_WEBROOTS[$i]}

    ./plugins/dotnet.sh buildOrRun $i
done

#========== main func end ==========
