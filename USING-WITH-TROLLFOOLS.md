# 在 TrollFools 里注入 Arc-shaped WeChat

## 产物

`ArcShapedWeChat_TrollFools.zip` 里只有一个文件：

```
ArcShapedWeChat.dylib
```

这是一个**裸 dylib**（arm64，iOS 14.0+），不链接 CydiaSubstrate / libhooker / ElleKit，
只依赖 UIKit / Foundation / QuartzCore / CoreGraphics，可以直接交给 TrollFools。

## 为什么是裸 dylib 而不是 deb

TrollFools 官方 README 对目标应用的分类是：

- 可移除的系统应用
- 已解密的 App Store 应用
- **加密的 App Store 应用 —— 只支持 bare dynamic library**

微信属于第三类。另外 `.deb` / `.zip` 的支持在官方仓库里至今还列在 Milestones（未实现），
所以请不要尝试把 deb 直接丢给 TrollFools。

## 注入步骤

1. 用 **TrollStore** 安装 TrollFools（用其他方式签名安装无效）。
2. 把 `ArcShapedWeChat.dylib` 存到「文件」App，建议单独建个文件夹方便找。
3. 打开 TrollFools → 应用列表搜索 **微信** → 进入。
4. 点 **注入**，在文件选择器里选中 `ArcShapedWeChat.dylib`。
5. 等待提示完成（若提示成功但走了兼容回退，也会在结果页说明）。
6. **完全杀掉微信再重开**（上滑后台划掉），设置才会出现。

## 打开设置

微信 → **我 → 设置 → 插件**，列表里会出现 **Arc-shaped WeChat**。

点进去可以调：

- 总开关
- 卡片圆角 / 左右缩进 / 卡片间距 / 卡片内分隔线 / 描边 / 配色
- 强制圆角：头像、图片、九宫格、按钮、容器、单元格、整表，各自开关 + 半径
- 作用范围：白名单 / 全局
- 会话列表每行独立成卡

改完点右上角 **刷新** 立即生效。

## 它是怎么被加载的

TrollFools 做的事（对应 `InjectorV3+Inject.swift`）：

1. 把 dylib 拷进 `WeChat.app/Frameworks/`
2. 往目标 Mach-O 插入 `LC_RPATH = @executable_path/Frameworks`
3. 插入 `LC_LOAD_DYLIB = @rpath/ArcShapedWeChat.dylib`
4. 对 dylib 做 CoreTrust bypass（用宿主 App 的 Team ID 重签）

**注意**：因为微信主二进制是加密的，TrollFools 实际会挑微信包里某个**未加密**的 Mach-O
（通常是微信自己的某个 framework）作为注入目标。所以 dylib 的构造时机不完全可控，
插件内部做了 2s / 6s 两次延迟重试来兜底安装 hook。

## 配置文件在哪里

微信运行在 App 沙盒里，所以配置写在微信自己的容器里：

```
<微信 Data 容器>/Library/Preferences/com.arcshaped.wechat.plist
```

卸载插件后残留这个文件不影响使用；想彻底重置，在设置页点「恢复默认设置」。

## 出问题怎么办

| 现象 | 处理 |
| --- | --- |
| 注入后微信闪退 | 在 TrollFools 里移除插件；多半是某个页面被容器圆角裁坏了，重开后先关掉「容器圆角」 |
| 插件列表里没有入口 | 强制杀掉微信重开；仍没有则确认 dylib 与 TrollFools 版本匹配（iOS 14–17） |
| 某些页面排版错乱 | 设置页把「作用范围」保持在白名单；或关掉对应类别的强制圆角 |
| 改了设置没变化 | 点右上角「刷新」，或杀掉微信重开 |
| 想彻底移除 | TrollFools → 微信 → 移除 → 删除插件 |

## 已知限制

- 只做视觉改动，不碰消息、数据、网络。
- 朋友圈 / 视频号这类高度自绘页面，卡片化效果依赖其 section 划分。
- 由于微信主二进制加密，注入目标是包内未加密的 framework；若微信更新后该 framework
  结构变化导致 dylib 未被加载，重新注入一次即可。
