#!/usr/bin/env bash

set -o pipefail
set -o nounset

#========== config begin ==========

# Repository root path for storing source code, logs, temporary files, etc
REPOSITORY_DIR=/data/microci

#========== config end ==========

function showHelp() {
	cat > /dev/stdout << END
microci v2.0.0

Usage:
${0} ACTION [OPTION]

pipe
    OPTION: none
pushDingding
    OPTION:
    \$1 - content text
    \$2 - atMobiles
pushWechat
    OPTION:
    \$1 - content test
    \$2 - uids
END
}

function readCommitInfo() {
    if [[ ! -f ${PFILE:-} ]]; then
        echo "\$PFILE Variable don't exist"
        return 1
    fi

    local res=$(cat $PFILE | python -c 'import sys, json;
jCommit = json.load(sys.stdin);
print jCommit["ref"]
print jCommit["commits"][0]["url"]
print jCommit["pusher"]["login"]
print jCommit["pusher"]["full_name"]
')
    local arr=($res)
    GIT_BRANCH=$(basename ${arr[0]})
    GIT_COMMIT_URLS=${arr[1]}
    GIT_LOGIN_NAME=${arr[2]}
    GIT_FULL_NAME=${arr[3]:-}


    # read changes
    local chgsStr=$(cat $PFILE | python -c 'import sys, json;
commits = json.load(sys.stdin)["commits"];
for commit in commits:
    for itm in commit["added"]:
        print itm
    for itm in commit["modified"]:
        print itm
    for itm in commit["removed"]:
        print itm
')
    GIT_CHANGES=($chgsStr)
}

function pull() {
    printToFile 'Start pulling the code...'
    repoPath=$branchPath/repo
    if [[ -d $repoPath && -d $repoPath/.git ]]; then
        pushd $repoPath >/dev/null
        git fetch --all
        git reset --hard origin/$GIT_BRANCH
        popd >/dev/null
    else
        mkdir -p $repoPath
        git clone -b $GIT_BRANCH $GIT_URL $repoPath
    fi
}

function clearLastStagePids() {
    if [[ -f $1 ]]; then
        local pids=`cat $1`
        pids=($pids)
        for pid in ${pids[@]:-}; do            
            if [[ -d /proc/$pid ]]; then
                ps --ppid $pid | awk '{if($1~/[0-9]+/) print $1}'| xargs kill
                kill $pid
            fi
        done
    fi
}

function printToFile() {
    if [[ ! -z ${log_file:-} ]]; then
        if [[ -z ${1:-} ]]; then
            tee -a $log_file
        else
            msg="[$(date "+%Y-%m-%d %H:%M:%S")] $1"
            echo $msg | tee -a $log_file
        fi
    fi
}

function clean() {
    printToFile 'Temporary files are being cleaned up'
    #[[ -f ${CHGS_FILE:-} ]] && rm -f $CHGS_FILE
}

#========== onXXX begin ==========

function onPipeline() {
    INCLUDES=(${INCLUDES:-""})
    EXCLUDES=(${EXCLUDES:-""})
    BRANCHS=(${BRANCHS:-"master"})

    readCommitInfo || exit 1
    branchPath="$REPOSITORY_DIR/$NAME/$GIT_BRANCH"
    log_file=$branchPath/ci.log
    CHGS_FILE=$branchPath/chgs.log

    [[ ! -d $branchPath ]] && mkdir -p $branchPath
    [[ -f $log_file ]] && >$log_file

    if [[ ! -d $REPOSITORY_DIR ]]; then
        printToFile "The $REPOSITORY_DIR directory does not exist"
        exit 1
    fi

    # Check branchs
    local skip=1;
    for b in ${BRANCHS[@]}; do
        if [[ $b == $GIT_BRANCH ]]; then
            skip=0
            break
        fi
    done
    if [[ $skip == 1 ]]; then
        printToFile "Branch $GIT_BRANCH has been skipped"
        exit 0
    fi

    # Check changes
    [[ -f $CHGS_FILE ]] && >$CHGS_FILE
    local hasChg=0
    for chg in ${GIT_CHANGES[@]}; do
        skip=0
        for e in ${EXCLUDES[@]}; do
            if [[ $chg == *$e* ]]; then
                skip=1
                break
            fi
        done
        [[ $skip == 1 ]] && continue

        [[ -z $INCLUDES ]] && skip=0 || skip=1
        for e in ${INCLUDES[@]}; do
            if [[ $chg == *$e* ]]; then
                skip=0
                break
            fi
        done
        [[ $skip == 1 ]] && continue

        hasChg=1
        echo $chg>>$CHGS_FILE
    done

    # Begin stage
    if [[ $hasChg == 1 ]]; then
        pull || exit 1
        if [[ ! -z ${STAGE_SH:-} ]]; then
            lastStagePidsFile=$branchPath/pids.txt
            export SRC_DIR=$branchPath/repo
            export OUT_DIR=$branchPath/bin
            export CHGS_FILE
            export GIT_BRANCH
            export GIT_COMMIT_URLS
            export GIT_LOGIN_NAME
            export GIT_FULL_NAME
        
            clearLastStagePids $lastStagePidsFile
            printToFile "Start executing Stage..."
            ($STAGE_SH 2>&1 | printToFile) &
            lastPid=$!
            echo $lastPid>$lastStagePidsFile
            wait $lastPid
            >$lastStagePidsFile
        fi
    else
        printToFile "Branch $GIT_BRANCH no effective changes"
    fi
}

function onPushDingding() {
    local content="$1"
    local atMobile=${2:-}
    [[ ${#atMobile} == 11 ]] && atMobile="\"$atMobile\"" || atMobile=""

    local data='{
        "msgtype": "text",
        "text": {
            "content": "'$content'"
        },
        "at": {
            "atMobiles": [
                '${atMobile:-}'
            ]
        }
    }'
    local res=$(curl -X POST -H "Content-type: application/json" -s -d "$data" \
    https://oapi.dingtalk.com/robot/send?access_token=$PUSH_DD_TOKEN)
    
    echo "onPushDingding: $res"
}

function onPushWechat() {
    local content=$1
    local uid=${2:-$PUSH_WX_DEFUID}
    uid="\"$uid\""

    local data='{
        "appToken": "'$PUSH_WX_TOKEN'",
        "contentType": 1,
        "content":"'$content'",
        "uids":[ '${uid:-}' ]
    }'
    local res=$(curl -X POST -H "Content-type: application/json" -s -d "$data" \
    http://wxpusher.zjiecode.com/api/send/message)

    echo "onPushWechat: $res"
}

#========== onXXX end ==========

#========== main func begin ==========

trap 'clean' INT TERM EXIT TSTP

# parse opts
ACTION=${1:-} && shift
case "$ACTION" in
    pipe)
        onPipeline "$@" ;;
    pushDingding)
        onPushDingding "$@" ;;
    pushWechat)
        onPushWechat "$@" ;;
    *)
        showHelp ;;
esac

#========== main func end ==========
