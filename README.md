# CS:GO Weapon Replace

一个使用 SourcePawn 编写的 SourceMod 插件。玩家可以为“买到的武器”设置个人替换规则；规则以 SteamID 独立保存，并在服务器重启后继续生效。

## 功能

- 聊天输入 `!replace` 开始设置。
- 输入购买时的武器 ID（例如 `weapon_ak47`），再输入希望获得的武器 ID（例如 `weapon_awp`）。
- 在任一步输入 `list`，可在聊天区和控制台查看全部可用武器 ID。
- 聊天输入 `!replacements` 查看自己的全部已有规则；设置过程中也可以输入 `rules` 查看。
- 输入 `cancel` 取消本次设置。
- 将目标 ID 设置成与来源 ID 相同，可删除该来源武器的替换规则。
- 每名玩家可以保存多条规则，配置互不影响。
- 购买成功后插件才执行替换，并按目标武器价格结算：目标更便宜会返还差价，目标更贵会补扣差价。
- 如果余额不足以支付更贵目标武器的差价，本次不会替换，并保留已经购买的原武器。
- 退款不会使玩家金钱超过服务器的 `mp_maxmoney` 上限。

示例：输入 `!replace`，依次输入 `weapon_ak47` 和 `weapon_awp`，以后购买 AK-47 时会获得 AWP。

删除规则时，依次输入相同的来源和目标武器 ID。例如输入 `!replace`，然后连续输入两次 `weapon_ak47`，即可删除 AK-47 的替换规则。

## 安装

1. 服务器需安装 SourceMod 1.10 或更高版本。
2. 将 `weapon_replace.smx` 放入`addons/sourcemod/plugins/`。
3. 更换地图或执行 `sm plugins load weapon_replace`。

玩家配置会自动创建在：

```text
addons/sourcemod/data/weapon_replace.cfg
```

## 自动构建与发布

GitHub Actions 会在每次推送、Pull Request 以及手动触发时使用固定版本的 spcomp 编译插件，并上传构建 Artifact。

推送以 `v` 开头的 Git 标签时（例如 `v1.2.0`），工作流会自动创建 GitHub Release 并上传 `weapon_replace.smx`。Release 名称和构建 Artifact 名称都会包含所用的 spcomp 完整版本。

```text
git tag v1.2.0
git push origin v1.2.0
```

仓库不保存编译后的 `.smx` 文件；请从 GitHub Actions Artifact 或 Releases 下载。

## 本地编译

在 SourceMod 的 `addons/sourcemod/scripting` 目录执行：

```text
spcomp weapon_replace.sp -o../plugins/weapon_replace.smx
```

插件仅列出并接受可由 `GivePlayerItem` 安全生成的 CS:GO 武器、枪械和手雷 ID，不包含护甲、拆弹器、C4、刀具及危险区专用道具。
