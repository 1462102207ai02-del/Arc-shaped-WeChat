# Arc-shaped WeChat

iOS 微信的列表**卡片化 + 圆角 + 缩进**插件，以**裸 dylib** 形式交付，
可直接用 **TrollFools**（TrollStore）注入微信，无需越狱。

---

## 一、它做了什么

### 列表卡片化

一个 section 渲染成一张连续的卡片；可选「每行独立成卡」（首页会话列表）。

- **圆角** —— 卡片顶/底按位置分别圆角，中间行保持直角
- **卡片缩进** —— 整个 cell 的 frame 左右内缩，内容跟着一起缩进
- **卡片间距** —— 通过追加 section footer 高度拉开卡与卡的距离
- **卡片内分隔线** —— 自绘发丝线，替掉微信原生分割线
- **描边 / 配色** —— 可选描边；配色支持跟随系统 / 浅色 / 深色

### 强制圆角

对逆向得到的视图类清单逐类加圆角（详见下方清单），每类都有独立开关和半径：

| 类别 | 类名 | 默认 |
| --- | --- | --- |
| 头像 | `MMHeadImageView` | 开（正圆） |
| 图片 | `WCImageView` / `MMWebImageView` | 开，半径 8 |
| 九宫格 | `MMImageGridView` | 开，半径 8 |
| 按钮 | `MMUIButton` / `MMTransparentButton` | 开，半径 10 |
| 容器 | `MMUIView` / `ColorGradientView` | 开，半径 8 |
| 单元格 | `MMTableViewCell` / `SettingCell` | 开，半径 10 |
| 整表 | `MMTableView` | 关（易与页面背景冲突） |

支持 `kCACornerCurveContinuous`（苹果原生连续圆角曲线），默认开。

### 作用范围

白名单里的 85 个页面（来自《微信圆角 dylib 逆向分析报告》的 [B]+[C] 组，外加四个一级 Tab），
黑名单永远跳过聊天页 / 支付页 / 表情面板等。

---

## 二、为什么不用 Logos / MobileSubstrate

TrollFools 官方 README 写明，对**加密的 App Store 应用**（微信正是）**只支持 bare dynamic library**。
而且 `.deb` / `.zip` 的支持至今还列在 Milestones 里没实现。

所以本工程：

- 不使用 Logos，改用纯 Objective-C runtime swizzling（`ArcHook`）
- 不链接 CydiaSubstrate / libhooker / ElleKit
- 只链接 UIKit / Foundation / QuartzCore / CoreGraphics
- 产物就是单个 `ArcShapedWeChat.dylib`

另外两个针对 TrollFools 的关键适配：

1. **微信仍在 App 沙盒里** → 配置写 `<微信容器>/Library/Preferences/`，不写 `/var/mobile`
2. **注入点是微信包里某个未加密的 Mach-O，加载时机不保证** → hook 安装做了 2s / 6s 延迟重试

---

## 三、源码结构

```
ArcShapedWeChat.m          dylib 入口 + 全部 hook（纯 runtime）
ArcHook.h / .m             零依赖 swizzling 工具（替代 MSHookMessageEx）
ArcTargetClasses.h         逆向报告里的全量类名清单（白/黑/行卡/强制圆角）
ArcCardEngine.h / .m       卡片化引擎：作用域判定 → 位置计算 → 下发样式
ArcForceRound.h / .m       强制圆角：对视图类清单逐类 hook layoutSubviews
ArcPrefs.h / .m            配置读写（App 容器，兼容 rootless 越狱路径）
ArcSettingsController.*    设置页（纯 UIKit，零微信依赖）
Makefile                   xcrun 直接构建裸 dylib
.github/workflows/build.yml macOS runner 构建 + 打包 + 发布
```

### Hook 点

| 钩子 | 作用 |
| --- | --- |
| `-[UITableView _configureCellForDisplay:forIndexPath:]` | 通用入口，覆盖所有 UITableView（私有但稳定，做了存在性检查） |
| `-[UITableViewCell setFrame:]` | 左右缩进，旋转/尺寸变化自动重算 |
| `-[WCTableViewManager tableView:willDisplayCell:...]` | 微信表格构造器，覆盖设置/我/通用/插件等绝大多数页面 |
| `-[WCTableViewManager tableView:heightForFooterInSection:]` | 追加分组间距 |
| `-[NewMainFrameVC/ContactsVC/MoreVC willDisplayCell]` | 一级 Tab（自己当 delegate，不走 WCTableViewManager） |
| `-[MinimizeViewController viewDidLoad]` | 注册进「设置 → 插件」 |
| 各视图类 `layoutSubviews` | 强制圆角 |

卡片画在 `cell.backgroundView` 上（`ArcCardBackgroundView`，两个 `CAShapeLayer` + 一层发丝线），
**不给 cell 加 mask**，因此不影响微信自己的子视图布局和点击热区。

---

## 四、本地构建

需要 macOS + Xcode 命令行工具：

```bash
cd ArcShapedWeChat
make            # 产出 build/ArcShapedWeChat.dylib
make clean
```

`make` 会自动校验产物里**没有 substrate 依赖**，有就直接报错。

---

## 五、注入

见 **[USING-WITH-TROLLFOOLS.md](USING-WITH-TROLLFOOLS.md)**。

简要流程：TrollStore 装 TrollFools → 存好 dylib → TrollFools 里选中微信 → 注入 →
杀掉微信重开 → 微信「我 → 设置 → 插件」里出现 **Arc-shaped WeChat**。

---

## 六、调参建议

| 场景 | 圆角 | 缩进 | 间距 |
| --- | --- | --- | --- |
| 克制、接近原生 | 10 | 10 | 8 |
| 明显卡片流 | 14 | 14 | 12 |
| 会话列表每行一卡 | 12 | 12 | 8（并打开「每行独立成卡」） |

---

## 七、限制

- 只做视觉改动，不碰任何消息、数据、网络逻辑。
- 朋友圈 / 视频号这类高度自绘页面，卡片化效果依赖其 section 划分。
- 容器类（`MMUIView` / `ColorGradientView`）圆角覆盖面最广，是唯一可能裁坏界面的开关；
  出问题先关它（已对 40pt 以下元素做了保护）。
