//
//  ArcSettingsController.m
//  Arc-shaped WeChat
//
//  纯 UIKit 实现，不依赖微信任何私有类，避免微信改版导致设置页打不开。
//  类名 ArcShapedWeChatSettingsController 会注册进 WCPluginsMgr。
//

#import "ArcSettingsController.h"
#import "ArcPrefs.h"
#import "ArcCardEngine.h"
#import "ArcStatus.h"
#import "ArcClassSettings.h"
#import "ArcClassConfig.h"
#import "ArcForceRound.h"

#define kArcVersion @"1.2-1"

typedef NS_ENUM(NSUInteger, ArcRow) {
    // 主开关
    ArcRowMasterSwitch,

    // 列表卡片化
    ArcRowRadius,
    ArcRowInset,
    ArcRowSpacing,
    ArcRowDivider,
    ArcRowBorderWidth,
    ArcRowCardStyle,

    // 强制圆角（逆向清单 [A] 组视图类）
    ArcRowForceRoundMaster,
    ArcRowRoundAvatar,
    ArcRowAvatarCircle,
    ArcRowAvatarRadius,
    ArcRowRoundImageView,
    ArcRowImageViewRadius,
    ArcRowRoundImageGrid,
    ArcRowImageGridRadius,
    ArcRowRoundButton,
    ArcRowButtonRadius,
    ArcRowRoundContainer,
    ArcRowContainerRadius,
    ArcRowRoundSettingCell,
    ArcRowSettingCellRadius,
    ArcRowRoundTableView,
    ArcRowTableViewRadius,
    ArcRowContinuousCorner,

    // 按类配置
    ArcRowPerClass,

    // 作用范围
    ArcRowScope,
    ArcRowSessionRowCard,
    ArcRowPageBg,

    // 其它
    ArcRowRefresh,
    ArcRowReset,
    ArcRowVersion,

    // 自检诊断
    ArcRowDiagnostic,
};

@interface ArcShapedWeChatSettingsController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSArray<NSNumber *> *> *sections;
@property (nonatomic, strong) NSArray<NSString *> *sectionFooters;
@end

@implementation ArcShapedWeChatSettingsController

#pragma mark - 生命周期

- (instancetype)init {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.title = @"你啊爸支鼎溜";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [[ArcPrefs shared] pageColorForTraitCollection:self.traitCollection];

    self.sections = @[
        @[ @(ArcRowMasterSwitch) ],
        @[ @(ArcRowRadius), @(ArcRowInset), @(ArcRowSpacing), @(ArcRowDivider), @(ArcRowBorderWidth), @(ArcRowCardStyle) ],
        @[ @(ArcRowForceRoundMaster),
           @(ArcRowRoundAvatar), @(ArcRowAvatarCircle), @(ArcRowAvatarRadius),
           @(ArcRowRoundImageView), @(ArcRowImageViewRadius),
           @(ArcRowRoundImageGrid), @(ArcRowImageGridRadius),
           @(ArcRowRoundButton), @(ArcRowButtonRadius),
           @(ArcRowRoundContainer), @(ArcRowContainerRadius),
           @(ArcRowRoundSettingCell), @(ArcRowSettingCellRadius),
           @(ArcRowRoundTableView), @(ArcRowTableViewRadius),
           @(ArcRowContinuousCorner) ],
        @[ @(ArcRowPerClass) ],
        @[ @(ArcRowScope), @(ArcRowSessionRowCard), @(ArcRowPageBg) ],
        @[ @(ArcRowRefresh), @(ArcRowReset), @(ArcRowVersion) ],
        @[ @(ArcRowDiagnostic) ],
    ];
    self.sectionFooters = @[
        @"总开关关闭后，所有页面恢复微信原样。",
        @"卡片化的三个核心参数：圆角半径决定弧线，左右缩进决定卡片离屏幕边的距离，卡片间距决定卡与卡之间的留白。",
        @"对应逆向得到的视图类清单：头像 MMHeadImageView、图片 WCImageView/MMWebImageView、九宫格 MMImageGridView、按钮 MMUIButton/MMTransparentButton、容器 MMUIView/ColorGradientView、单元格 MMTableViewCell/SettingCell、表格 MMTableView。容器类圆角最激进，出问题时优先关它。",
        @"按逆向清单逐个类单独设置：启用模式、背景色（系统取色器，支持透明度）、圆角半径、缩进上下左右。\n类级配置优先级高于以上所有全局设置。",
        @"白名单模式只处理已验证过的页面；全局模式会把所有列表都卡片化，可能出现个别页面排版异常。",
        @"",
        @"如果插件没有出现在「设置 → 插件」列表里，看这里：注册成功应为「是」。"
        "若为否则说明 WCPluginsMgr 当时还不可用，重启微信一般即可。",
    ];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52.0;
    [self.view addSubview:self.tableView];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"刷新"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(onRefresh:)];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[ArcPrefs shared] synchronize];
}

#pragma mark - 事件

- (void)onRefresh:(id)sender {
    [[ArcPrefs shared] synchronize];
    [[ArcCardEngine shared] reloadAllVisibleTableViews];
}

- (void)onSwitchChanged:(UISwitch *)sender {
    ArcPrefs *prefs = [ArcPrefs shared];
    switch ((ArcRow)sender.tag) {
        case ArcRowMasterSwitch:      prefs.enabled = sender.on; break;
        case ArcRowDivider:           prefs.showDivider = sender.on; break;
        case ArcRowSessionRowCard:    prefs.sessionRowCard = sender.on; break;
        case ArcRowPageBg:            prefs.tintTableViewBg = sender.on; break;

        case ArcRowForceRoundMaster:  prefs.forceRoundEnabled = sender.on; break;
        case ArcRowRoundAvatar:       prefs.roundAvatar = sender.on; break;
        case ArcRowAvatarCircle:      prefs.avatarCircle = sender.on; break;
        case ArcRowRoundImageView:    prefs.roundImageView = sender.on; break;
        case ArcRowRoundImageGrid:    prefs.roundImageGrid = sender.on; break;
        case ArcRowRoundButton:       prefs.roundButton = sender.on; break;
        case ArcRowRoundContainer:    prefs.roundContainer = sender.on; break;
        case ArcRowRoundSettingCell:  prefs.roundSettingCell = sender.on; break;
        case ArcRowRoundTableView:    prefs.roundTableView = sender.on; break;
        case ArcRowContinuousCorner:  prefs.continuousCorner = sender.on; break;
        default: break;
    }
    [prefs synchronize];
}

- (void)onSliderChanged:(UISlider *)sender {
    ArcPrefs *prefs = [ArcPrefs shared];
    CGFloat v = sender.value;
    switch ((ArcRow)sender.tag) {
        case ArcRowRadius:            prefs.cornerRadius = v; break;
        case ArcRowInset:             prefs.horizontalInset = v; break;
        case ArcRowSpacing:           prefs.cardSpacing = v; break;
        case ArcRowBorderWidth:       prefs.borderWidth = v; break;
        case ArcRowAvatarRadius:      prefs.avatarRadius = v; break;
        case ArcRowImageViewRadius:   prefs.imageViewRadius = v; break;
        case ArcRowImageGridRadius:   prefs.imageGridRadius = v; break;
        case ArcRowButtonRadius:      prefs.buttonRadius = v; break;
        case ArcRowContainerRadius:   prefs.containerRadius = v; break;
        case ArcRowSettingCellRadius: prefs.settingCellRadius = v; break;
        case ArcRowTableViewRadius:   prefs.tableViewRadius = v; break;
        default: break;
    }
    [self updateValueLabelForSlider:sender];
}

- (void)onSliderCommit:(UISlider *)sender {
    [[ArcPrefs shared] synchronize];
    [[ArcCardEngine shared] reloadAllVisibleTableViews];
}

- (void)onSegmentChanged:(UISegmentedControl *)sender {
    [ArcPrefs shared].scopeMode = (sender.selectedSegmentIndex == 1) ? ArcScopeModeGlobal
                                                                    : ArcScopeModeWhitelist;
    [[ArcPrefs shared] synchronize];
    [[ArcCardEngine shared] reloadAllVisibleTableViews];
}

- (void)onReset:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认设置"
                                                                  message:@"所有自定义参数会被重置。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"重置"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [[ArcPrefs shared] resetToDefaults];
        [[ArcCardEngine shared] reloadAllVisibleTableViews];
        [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 单元格

- (UITableViewCell *)switchCellForRow:(ArcRow)row {
    static NSString *ident = @"ArcSwitchCell";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:ident];
        UISwitch *sw = [[UISwitch alloc] init];
        [sw addTarget:self action:@selector(onSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.numberOfLines = 0;
    }
    UISwitch *sw = (UISwitch *)cell.accessoryView;
    sw.tag = row;

    ArcPrefs *prefs = [ArcPrefs shared];
    switch (row) {
        case ArcRowMasterSwitch:
            cell.textLabel.text = @"启用列表卡片化";
            cell.detailTextLabel.text = @"卡片式分组 / 圆角 / 缩进";
            sw.on = prefs.enabled; break;
        case ArcRowDivider:
            cell.textLabel.text = @"卡片内分隔线";
            cell.detailTextLabel.text = @"在卡内多行之间画细线";
            sw.on = prefs.showDivider; break;
        case ArcRowSessionRowCard:
            cell.textLabel.text = @"会话列表每行独立成卡";
            cell.detailTextLabel.text = @"微信首页的每条会话单独一张卡片";
            sw.on = prefs.sessionRowCard; break;
        case ArcRowPageBg:
            cell.textLabel.text = @"同时调整页面底色";
            cell.detailTextLabel.text = @"把列表背景换成卡片衬底色";
            sw.on = prefs.tintTableViewBg; break;

        case ArcRowForceRoundMaster:
            cell.textLabel.text = @"启用强制圆角";
            cell.detailTextLabel.text = @"对逆向得到的视图类清单统一加圆角";
            sw.on = prefs.forceRoundEnabled; break;
        case ArcRowRoundAvatar:
            cell.textLabel.text = @"头像圆角";
            cell.detailTextLabel.text = @"MMHeadImageView";
            sw.on = prefs.roundAvatar; break;
        case ArcRowAvatarCircle:
            cell.textLabel.text = @"头像强制正圆";
            cell.detailTextLabel.text = @"忽略半径，按最短边取一半";
            sw.on = prefs.avatarCircle; break;
        case ArcRowRoundImageView:
            cell.textLabel.text = @"图片圆角";
            cell.detailTextLabel.text = @"WCImageView / MMWebImageView";
            sw.on = prefs.roundImageView; break;
        case ArcRowRoundImageGrid:
            cell.textLabel.text = @"九宫格圆角";
            cell.detailTextLabel.text = @"MMImageGridView";
            sw.on = prefs.roundImageGrid; break;
        case ArcRowRoundButton:
            cell.textLabel.text = @"按钮圆角";
            cell.detailTextLabel.text = @"MMUIButton / MMTransparentButton";
            sw.on = prefs.roundButton; break;
        case ArcRowRoundContainer:
            cell.textLabel.text = @"容器圆角";
            cell.detailTextLabel.text = @"MMUIView / ColorGradientView";
            sw.on = prefs.roundContainer; break;
        case ArcRowRoundSettingCell:
            cell.textLabel.text = @"单元格圆角";
            cell.detailTextLabel.text = @"MMTableViewCell / SettingCell";
            sw.on = prefs.roundSettingCell; break;
        case ArcRowRoundTableView:
            cell.textLabel.text = @"整表圆角";
            cell.detailTextLabel.text = @"MMTableView（默认关，易与页面背景冲突）";
            sw.on = prefs.roundTableView; break;
        case ArcRowContinuousCorner:
            cell.textLabel.text = @"连续圆角曲线";
            cell.detailTextLabel.text = @"kCACornerCurveContinuous，苹果原生观感";
            sw.on = prefs.continuousCorner; break;
        default: break;
    }
    return cell;
}

- (UITableViewCell *)sliderCellForRow:(ArcRow)row {
    static NSString *ident = @"ArcSliderCell";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"";

        UILabel *title = [[UILabel alloc] init];
        title.tag = 9003;
        title.font = [UIFont systemFontOfSize:16];
        title.textColor = [UIColor labelColor];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:title];

        UISlider *slider = [[UISlider alloc] init];
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        slider.minimumValue = 0;
        [slider addTarget:self action:@selector(onSliderChanged:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(onSliderCommit:)
         forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [cell.contentView addSubview:slider];

        UILabel *label = [[UILabel alloc] init];
        label.tag = 9002;
        label.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
        label.textColor = [UIColor secondaryLabelColor];
        label.textAlignment = NSTextAlignmentRight;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:label];

        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [title.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [title.widthAnchor constraintEqualToConstant:96],
            [label.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [label.widthAnchor constraintEqualToConstant:46],
            [slider.leadingAnchor constraintEqualToAnchor:title.trailingAnchor constant:8],
            [slider.trailingAnchor constraintEqualToAnchor:label.leadingAnchor constant:-8],
            [slider.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [cell.contentView.heightAnchor constraintEqualToConstant:52],
        ]];
    }

    UISlider *slider = nil;
    for (UIView *sub in cell.contentView.subviews) {
        if ([sub isKindOfClass:[UISlider class]]) { slider = (UISlider *)sub; break; }
    }
    UILabel *label = [cell.contentView viewWithTag:9002];
    UILabel *title = [cell.contentView viewWithTag:9003];
    if (!slider) { return cell; }
    slider.tag = row;

    ArcPrefs *prefs = [ArcPrefs shared];
    CGFloat value = 0;
    slider.maximumValue = 24;
    switch (row) {
        case ArcRowRadius:            title.text = @"卡片圆角"; value = prefs.cornerRadius; break;
        case ArcRowInset:             title.text = @"左右缩进"; value = prefs.horizontalInset; break;
        case ArcRowSpacing:           title.text = @"卡片间距"; value = prefs.cardSpacing; break;
        case ArcRowAvatarRadius:      title.text = @"头像半径"; value = prefs.avatarRadius; break;
        case ArcRowImageViewRadius:   title.text = @"图片半径"; value = prefs.imageViewRadius; break;
        case ArcRowImageGridRadius:   title.text = @"九宫格";   value = prefs.imageGridRadius; break;
        case ArcRowButtonRadius:      title.text = @"按钮半径"; value = prefs.buttonRadius; break;
        case ArcRowContainerRadius:   title.text = @"容器半径"; value = prefs.containerRadius; break;
        case ArcRowSettingCellRadius: title.text = @"单元格";   value = prefs.settingCellRadius; break;
        case ArcRowTableViewRadius:   title.text = @"表格半径"; value = prefs.tableViewRadius; break;
        case ArcRowBorderWidth:
            title.text = @"描边宽度"; value = prefs.borderWidth; slider.maximumValue = 3; break;
        default: break;
    }
    slider.value = value;
    label.text = (row == ArcRowBorderWidth) ? [NSString stringWithFormat:@"%.1f", value]
                                            : [NSString stringWithFormat:@"%.0f", value];
    return cell;
}

- (void)updateValueLabelForSlider:(UISlider *)slider {
    ArcRow row = (ArcRow)slider.tag;
    UILabel *label = [slider.superview viewWithTag:9002];
    label.text = (row == ArcRowBorderWidth) ? [NSString stringWithFormat:@"%.1f", slider.value]
                                            : [NSString stringWithFormat:@"%.0f", slider.value];
}

- (UITableViewCell *)scopeCell {
    static NSString *ident = @"ArcScopeCell";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:ident];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"白名单", @"全局"]];
        seg.frame = CGRectMake(0, 0, 148, 30);
        seg.apportionsSegmentWidthsByContent = NO;
        [seg addTarget:self action:@selector(onSegmentChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = seg;
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }
    cell.textLabel.text = @"作用范围";
    cell.detailTextLabel.text = @"白名单 = 只处理已验证页面";
    UISegmentedControl *seg = (UISegmentedControl *)cell.accessoryView;
    seg.selectedSegmentIndex = ([ArcPrefs shared].scopeMode == ArcScopeModeGlobal) ? 1 : 0;
    return cell;
}

- (UITableViewCell *)cardStyleCell {
    static NSString *ident = @"ArcStyleCell";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:ident];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.font = [UIFont systemFontOfSize:16];
    }
    cell.textLabel.text = @"卡片配色";
    ArcCardStyle style = [ArcPrefs shared].cardStyle;
    cell.detailTextLabel.text = (style == ArcCardStyleLight) ? @"浅色" :
                                (style == ArcCardStyleDark)  ? @"深色" : @"跟随系统";
    return cell;
}

- (UITableViewCell *)actionCellForRow:(ArcRow)row {
    static NSString *ident = @"ArcActionCell";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:ident];
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = @"";
    switch (row) {
        case ArcRowRefresh:
            cell.textLabel.text = @"立即刷新所有列表";
            cell.textLabel.textColor = [UIColor systemBlueColor];
            break;
        case ArcRowReset:
            cell.textLabel.text = @"恢复默认设置";
            cell.textLabel.textColor = [UIColor systemRedColor];
            break;
        case ArcRowVersion:
            cell.textLabel.text = @"版本";
            cell.textLabel.textColor = [UIColor labelColor];
            cell.detailTextLabel.text = kArcVersion;
            break;
        default: break;
    }
    return cell;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.sections[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSString *text = self.sectionFooters[section];
    return text.length ? text : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ArcRow row = (ArcRow)[self.sections[indexPath.section][indexPath.row] integerValue];
    switch (row) {
        case ArcRowMasterSwitch:
        case ArcRowDivider:
        case ArcRowSessionRowCard:
        case ArcRowPageBg:
        case ArcRowForceRoundMaster:
        case ArcRowRoundAvatar:
        case ArcRowAvatarCircle:
        case ArcRowRoundImageView:
        case ArcRowRoundImageGrid:
        case ArcRowRoundButton:
        case ArcRowRoundContainer:
        case ArcRowRoundSettingCell:
        case ArcRowRoundTableView:
        case ArcRowContinuousCorner:
            return [self switchCellForRow:row];

        case ArcRowRadius:
        case ArcRowInset:
        case ArcRowSpacing:
        case ArcRowBorderWidth:
        case ArcRowAvatarRadius:
        case ArcRowImageViewRadius:
        case ArcRowImageGridRadius:
        case ArcRowButtonRadius:
        case ArcRowContainerRadius:
        case ArcRowSettingCellRadius:
        case ArcRowTableViewRadius:
            return [self sliderCellForRow:row];

        case ArcRowPerClass: return [self perClassCell];
        case ArcRowDiagnostic: return [self diagnosticCell];
        case ArcRowScope:   return [self scopeCell];
        case ArcRowCardStyle: return [self cardStyleCell];
        default: return [self actionCellForRow:row];
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    ArcRow row = (ArcRow)[self.sections[indexPath.section][indexPath.row] integerValue];

    if (row == ArcRowPerClass)  { [self openPerClassSettings]; return; }
    if (row == ArcRowRefresh) { [self onRefresh:nil]; return; }
    if (row == ArcRowReset)   { [self onReset:nil];   return; }
    if (row == ArcRowCardStyle) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"卡片配色"
                                                                      message:nil
                                                               preferredStyle:UIAlertControllerStyleActionSheet];
        __weak typeof(self) weakSelf = self;
        void (^pick)(ArcCardStyle) = ^(ArcCardStyle style) {
            [ArcPrefs shared].cardStyle = style;
            [[ArcPrefs shared] synchronize];
            [[ArcCardEngine shared] reloadAllVisibleTableViews];
            [weakSelf.tableView reloadData];
        };
        [alert addAction:[UIAlertAction actionWithTitle:@"跟随系统" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { pick(ArcCardStyleSystem); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"始终浅色" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { pick(ArcCardStyleLight); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"始终深色" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { pick(ArcCardStyleDark); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        alert.popoverPresentationController.sourceView = tableView;
        alert.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark - 按类配置

- (void)openPerClassSettings {
    ArcClassListController *list = [[ArcClassListController alloc] init];
    if (self.navigationController) {
        [self.navigationController pushViewController:list animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
        [self presentViewController:nav animated:YES completion:nil];
    }
}

- (UITableViewCell *)perClassCell {
    static NSString *ident = @"ArcPerClassCell";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:ident];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    }
    cell.textLabel.text = @"按类配置";
    NSUInteger n = [[ArcClassConfigStore shared] customizedCount];
    if (n > 0) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"已自定义 %lu 个类", (unsigned long)n];
        cell.detailTextLabel.textColor = [UIColor systemBlueColor];
    } else {
        cell.detailTextLabel.text = @"";
        cell.detailTextLabel.textColor = [UIColor tertiaryLabelColor];
    }
    return cell;
}

- (UITableViewCell *)diagnosticCell {
    static NSString *ident = @"ArcDiagnosticCell";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UILabel *label = [[UILabel alloc] init];
        label.tag = 9101;
        label.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
        label.textColor = [UIColor secondaryLabelColor];
        label.numberOfLines = 0;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [label.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [label.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
            [label.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
        ]];
    }
    UILabel *label = [cell.contentView viewWithTag:9101];
    label.text = [[ArcStatus shared] diagnosticText];
    return cell;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 从「按类配置」返回时刷新"已自定义 N 个类"，同时刷新自检信息
    [self.tableView reloadData];
}

@end
