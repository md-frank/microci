# 什么是MicroCI
MicroCI是一个CI工具，它于基于[webhook](https://github.com/adnanh/webhook)提供HTTP监听服务，您只需要在Git服务器上配置推送Web钩子，MicroCI会帮您实现：
- 拉取代码
- 编译代码
- 同步配置文件
- 运行项目
- 如遇编译失败还会向您指定的钉钉或微信推送消息提醒


MicroCI的定位是：
- 轻量级（工具本身内存占用5M以内），让您可以在低配的云服务器上运行
- 可定制化（支持插件、Stage），简洁而不简单

# 如何使用

## 配置

**start.sh**  
服务配置脚本，在这里您可以配置监听的IP、端口。
```
./webhook -ip 127.0.0.1 -port 9000 -hooks ./hooks.json
```
通过如上配置就配置了一个HTTP服务，地址为：http://127.0.0.1:9000 

**hooks.json**  
管线配置文件，在这里您可以配置多个管线，一个管线对应一个git项目。  

```
{
    //管线ID，将来GIT勾子地址填：http://127.0.0.1:9000/hooks/example
    "id": "example",
    "execute-command": "./microci.sh",
    "command-working-directory": "/home/frank/microci",
    "response-message": "OK",
    "trigger-rule-mismatch-http-response-code": 400,
    "pass-environment-to-command": [
        {
            "source": "string",
            "envname": "NAME",
            "name": "example"
        },
        {
            "source": "string",
            "envname": "GIT_URL",
            //GIT地址，包含用户名:密码
            "name": "https://ci:xxx@github.com/Mondol/ProjName.git"
        },
        {
            "source": "string",
            "envname": "STAGE_SH",
            //【可选】触发钩子时要执行的Stage脚本（脚本里可调用插件方法）
            "name": "./stages/example.sh"
        }
    ],
    "pass-arguments-to-command": [
        {
            "source": "string",
            "name": "pipe"
        }
    ],
    "pass-file-to-command": [
        {
            "source": "entire-payload",
            "envname": "PFILE"
        }
    ],
    "trigger-rule": {
        "and": [
            {
                "match": {
                    "type": "payload-hash-sha256",
                    //以Gogs为例，这里填钩子秘钥文本，防止非法请求
                    "secret": "xxxxxxxxxxxxxxxxxxx",
                    "parameter": {
                        "source": "header",
                        "name": "X-Gogs-Signature"
                    }
                }
            }
        ]
    }
}
```

**microci.sh**  
MicroCI核心脚本，在这里您可以改全局配置。
```
#========== config begin ==========

# 仓库的根路径，用于存储拉取到的源代码、日志、临时文件等
REPOSITORY_DIR=/data/microci

#========== config end ==========
```

**plugins/dotnet.sh**  
.NET Core编译插件，本插件可实现按需编译，仅当提交的代码影响了相关项目才会重新编译

**stages/example.sh（可选）**  
示例脚本，用于触发钩子时调用，如果您不需要执行自定义脚本时则不需要，本示例使用了dotnet插件，用于编译ASP.NET Core项目
```
#========== config begin ==========

# 选择使用的消息推送方式（pushWechat ｜ pushDingding）
export PUSH_IM="pushWechat"
# 微信推送专用，appToken，获取参见http://wxpusher.zjiecode.com获取
export PUSH_WX_TOKEN="wxpusher.zjiecode.com需要的appToken"
export PUSH_WX_DEFUID="如果代码提交者没有绑定微信UID，使用此处的默认值"

# 项目前缀
export PROJ_PREFIX="Mondol.Example."

# 服务端口映射
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
```
