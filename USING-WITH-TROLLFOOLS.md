# 在 TrollFools 里注入 Arc-shaped WeChat

## 产物

`ArcShapedWeChat_TrollFools.zip` 里只有一个文件：

```
ArcShapedWeChat.dylib
```

这是一个**裸 dylib**（arm64，最低部署版本 iOS 14.0，兼容 iOS 14.0 – 26.x、微信 8.0.72+），
不链接 CydiaSubstrate / libhooker / ElleKit，只依赖 UIKit / Foundation / QuartzCore /
CoreGraphics，可以直接交给 TrollFools。

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

入口有三条（互为备份）：

1. 微信 → **我 → 设置 → 插件**，列表里的 **你啊爸支鼎溜**；
2. **我 → 设置** 页面拉到底部的 **你啊爸支鼎溜** 按钮；
3. 前两条都看不到 = dylib 没有被加载（见下方排查表）。

点进去可以调：

- 总开关
- 卡片圆角 / 左右缩进 / 卡片间距 / 卡片内分隔线 / 描边 / 配色
- 强制圆角：头像、图片、九宫格、按钮、容器、单元格、整表，各自开关 + 半径
- 作用范围：白名单 / 全局
- 会话列表每行独立成卡

改完点右上角 **刷新** 立即生效。

## 它是怎么被加载的

以下规则来自 TrollFools 源码（`InjectorV3+Inject.swift` / `InjectorV3+Bundle.swift`）：

1. dylib 被拷进 `WeChat.app/Frameworks/ArcShapedWeChat.dylib`；
2. TrollFools 扫描微信包内 **主程序静态链接的内嵌 framework**，按策略排序
   （默认 lexicographic，按文件名排序）后选出第一个**未加密**的 Mach-O 作为注入点
   （微信主二进制加密，永远轮不到它，只会排在候选末位）；
3. 往选中的 framework 插入 `LC_RPATH = @executable_path/Frameworks` 和
   `LC_LOAD_DYLIB = @rpath/ArcShapedWeChat.dylib`（**默认弱引用**，加载失败不会
   导致微信崩溃，但也意味着不会报错——插件没生效时通常完全无感知）；
4. 对 dylib 和注入点做 CoreTrust bypass（用宿主 App 的 Team ID 重签）。

**推论**：本插件被加载的时机 = 微信加载那个 framework 的时机，不完全可控。
因此插件内部的策略是——

- 构造函数只做零风险初始化；
- hook 安装推迟到「App 启动完成 + 3.5s」（兜底 8s），另加 2s / 6s 补挂；
- 插件收纳注册由页面出现驱动（设置根页 / 我页 / 插件列表页），每次触发都会
  复查登记是否还在，被微信重建冲掉会自动补注册；
- 启动后 12s / 25s / 45s / 75s 另有一轮注册兜底。

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
| 设置 → 插件里没有入口 | 看「我 → 设置」页底部有没有 **你啊爸支鼎溜** 按钮：有 → 只是 WCPluginsMgr 注册没成功，从按钮进即可；没有 → dylib 未被加载，见下一行 |
| 两个入口都没有 | dylib 未被加载。依次尝试：① 完全杀掉微信重开；② TrollFools 移除后重新注入；③ 在 TrollFools 注入设置里把策略从 Lexicographic 换成 Fast / Pre-order 再注入（换一个被带起的 framework）；④ 重启手机 |
| 某些页面排版错乱 | 设置页把「作用范围」保持在白名单；或关掉对应类别的强制圆角 |
| 改了设置没变化 | 点右上角「刷新」，或杀掉微信重开 |
| 想彻底移除 | TrollFools → 微信 → 移除 → 删除插件 |

## 已知限制

- 只做视觉改动，不碰消息、数据、网络。
- 朋友圈 / 视频号这类高度自绘页面，卡片化效果依赖其 section 划分。
- 由于微信主二进制加密，注入目标是包内未加密的 framework；若微信更新后该 framework
  结构变化导致 dylib 未被加载，重新注入一次即可。
