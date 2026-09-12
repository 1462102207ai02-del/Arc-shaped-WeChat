//
//  ArcClassSettings.m
//  Arc-shaped WeChat
//
//  按类配置界面：
//    ArcClassListController   —— 所有已知类（视图类 / 控制器与其它），支持搜索
//    ArcClassDetailController —— 单个类：启用模式 / 背景色 / 圆角 / 缩进
//

#import "ArcClassSettings.h"
#import "ArcClassConfig.h"
#import "ArcPrefs.h"
#import "ArcCardEngine.h"

#pragma mark - 列表

@interface ArcClassListController () <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSArray<NSString *> *viewNames;
@property (nonatomic, strong) NSArray<NSString *> *controllerNames;
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *displaySections;
@property (nonatomic, strong) NSArray<NSString *> *sectionTitles;
@end

@implementation ArcClassListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"按类配置";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    ArcClassConfigStore *store = [ArcClassConfigStore shared];
    self.viewNames = [store viewClassNames];
    self.controllerNames = [store controllerClassNames];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 52;
    [self.view addSubview:self.tableView];

    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.hidesNavigationBarDuringPresentation = NO;
    self.searchController = search;
    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController = search;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
    } else {
        self.tableView.tableHeaderView = search.searchBar;
    }
    self.definesPresentationContext = YES;

    [self rebuildSections];

    UIBarButtonItem *resetAll = [[UIBarButtonItem alloc] initWithTitle:@"全部重置"
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(onResetAll)];
    self.navigationItem.rightBarButtonItem = resetAll;
}

- (void)rebuildSections {
    NSString *keyword = [[self.searchController.searchBar.text ?: @""] stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *views = self.viewNames;
    NSArray<NSString *> *ctrls = self.controllerNames;

    if (keyword.length > 0) {
        views = [views filteredArrayUsingPredicate:
                 [NSPredicate predicateWithFormat:@"SELF CONTAINS[cd] %@", keyword]];
        ctrls = [ctrls filteredArrayUsingPredicate:
                 [NSPredicate predicateWithFormat:@"SELF CONTAINS[cd] %@", keyword]];
    }

    NSMutableArray *sections = [NSMutableArray array];
    NSMutableArray *titles = [NSMutableArray array];
    if (views.count > 0) {
        [sections addObject:views];
        [titles addObject:[NSString stringWithFormat:@"视图类（%lu）", (unsigned long)views.count]];
    }
    if (ctrls.count > 0) {
        [sections addObject:ctrls];
        [titles addObject:[NSString stringWithFormat:@"控制器与其它（%lu）", (unsigned long)ctrls.count]];
    }
    self.displaySections = sections;
    self.sectionTitles = titles;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self rebuildSections];
    [self.tableView reloadData];
}

- (void)onResetAll {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重置所有类的配置？"
                                                                  message:@"所有类将恢复为「跟随全局设置」。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[ArcClassConfigStore shared] resetAll];
        [self.tableView reloadData];
        [[ArcCardEngine shared] reloadAllVisibleTableViews];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.displaySections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.displaySections[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sectionTitles[section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0 && self.viewNames.count > 0) {
        return @"视图类的配置会沿继承链作用到子类。容器类（MMUIView 等）覆盖面很广，设置背景色时请谨慎。";
    }
    if (section == (NSInteger)self.displaySections.count - 1) {
        return @"未自定义的项一律跟随全局设置。类级配置优先级高于全局。";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ident = @"ArcClassCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:ident];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.textLabel.adjustsFontSizeToFitWidth = YES;
        cell.textLabel.minimumScaleFactor = 0.8;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }
    NSString *name = self.displaySections[indexPath.section][indexPath.row];
    ArcClassConfig *cfg = [[ArcClassConfigStore shared] configForClassName:name];

    cell.textLabel.text = name;
    if (cfg.isCustomized) {
        cell.detailTextLabel.text = [self summaryForConfig:cfg];
        cell.detailTextLabel.textColor = [UIColor systemBlueColor];
    } else {
        cell.detailTextLabel.text = @"跟随全局";
        cell.detailTextLabel.textColor = [UIColor tertiaryLabelColor];
    }
    return cell;
}

- (NSString *)summaryForConfig:(ArcClassConfig *)cfg {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (cfg.isExplicitlyEnabled)  { [parts addObject:@"强制开启"]; }
    if (cfg.isExplicitlyDisabled) { [parts addObject:@"强制关闭"]; }
    if (cfg.hasBackgroundColor)   { [parts addObject:[NSString stringWithFormat:@"背景 %@", ArcColorHexString(cfg.backgroundColor)]]; }
    if (cfg.hasCornerRadius)      { [parts addObject:[NSString stringWithFormat:@"圆角 %g", cfg.cornerRadius]]; }
    if (cfg.hasInsets) {
        [parts addObject:[NSString stringWithFormat:@"缩进 %g/%g/%g/%g",
                          cfg.insetTop, cfg.insetLeft, cfg.insetBottom, cfg.insetRight]];
    }
    if (cfg.hasForceCircle) { [parts addObject:cfg.forceCircle ? @"正圆" : @"非正圆"]; }
    return [parts componentsJoinedByString:@" · "];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *name = self.displaySections[indexPath.section][indexPath.row];
    ArcClassKind kind = [[ArcClassConfigStore shared] kindForClassName:name];
    ArcClassDetailController *detail = [[ArcClassDetailController alloc] initWithClassName:name kind:kind];
    [self.navigationController pushViewController:detail animated:YES];
}

@end

#pragma mark - 单个类的详情

typedef NS_ENUM(NSInteger, ArcDetailRow) {
    ArcDetailRowEnabled = 0,
    ArcDetailRowBackground,
    ArcDetailRowClearBackground,
    ArcDetailRowRadius,
    ArcDetailRowForceCircle,
    ArcDetailRowInsetTop,
    ArcDetailRowInsetLeft,
    ArcDetailRowInsetBottom,
    ArcDetailRowInsetRight,
    ArcDetailRowReset,
};

@interface ArcClassDetailController () <UITableViewDelegate, UITableViewDataSource,
                                        UITextFieldDelegate, UIColorPickerViewControllerDelegate>
@property (nonatomic, copy) NSString *className;
@property (nonatomic, assign) ArcClassKind kind;
@property (nonatomic, strong) ArcClassConfig *config;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSArray<NSNumber *> *> *sections;
@property (nonatomic, strong) NSArray<NSString *> *footers;
@end

@implementation ArcClassDetailController

- (instancetype)initWithClassName:(NSString *)className kind:(ArcClassKind)kind {
    if ((self = [super init])) {
        _className = [className copy];
        _kind = kind;
        _config = [[ArcClassConfigStore shared] configForClassName:className];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.className;
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tableView];

    [self rebuildSections];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.view endEditing:YES];
    [[ArcCardEngine shared] reloadAllVisibleTableViews];
}

- (void)rebuildSections {
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableArray *footers = [NSMutableArray array];

    [sections addObject:@[ @(ArcDetailRowEnabled) ]];
    [footers addObject:@"「跟随全局」= 由总开关和白名单决定；「强制开启 / 关闭」会覆盖全局判断。"];

    NSMutableArray *appearance = [NSMutableArray arrayWithArray:@[ @(ArcDetailRowBackground) ]];
    if (self.config.hasBackgroundColor) { [appearance addObject:@(ArcDetailRowClearBackground)]; }
    [appearance addObject:@(ArcDetailRowRadius)];
    if (self.kind == ArcClassKindView) { [appearance addObject:@(ArcDetailRowForceCircle)]; }
    [sections addObject:appearance];
    [footers addObject:(self.kind == ArcClassKindView)
        ? @"背景色直接作用于该类视图；圆角与正圆作用于其 layer。"
        : @"背景色 = 该类页面里卡片的填充色；圆角 = 卡片圆角。"];

    [sections addObject:@[ @(ArcDetailRowInsetTop), @(ArcDetailRowInsetLeft),
                           @(ArcDetailRowInsetBottom), @(ArcDetailRowInsetRight) ]];
    [footers addObject:@"左右缩进决定卡片距屏幕边缘的距离；上下缩进叠加在卡片间距之上。留空 = 跟随全局。"];

    [sections addObject:@[ @(ArcDetailRowReset) ]];
    [footers addObject:@""];

    self.sections = sections;
    self.footers = footers;
}

- (void)refreshAfterChange {
    [self.config save];
    [self rebuildSections];
    [self.tableView reloadData];
    [[ArcCardEngine shared] reloadAllVisibleTableViews];
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.sections[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.footers[section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ArcDetailRow row = (ArcDetailRow)[self.sections[indexPath.section][indexPath.row] integerValue];

    switch (row) {
        case ArcDetailRowEnabled:         return [self enabledCell];
        case ArcDetailRowBackground:      return [self backgroundCell];
        case ArcDetailRowClearBackground: return [self clearBackgroundCell];
        case ArcDetailRowRadius:          return [self numberCellForRow:row];
        case ArcDetailRowForceCircle:     return [self forceCircleCell];
        case ArcDetailRowInsetTop:
        case ArcDetailRowInsetLeft:
        case ArcDetailRowInsetBottom:
        case ArcDetailRowInsetRight:      return [self numberCellForRow:row];
        case ArcDetailRowReset:           return [self resetCell];
    }
    return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    ArcDetailRow row = (ArcDetailRow)[self.sections[indexPath.section][indexPath.row] integerValue];
    if (row == ArcDetailRowBackground) {
        [self presentColorPicker];
    } else if (row == ArcDetailRowClearBackground) {
        self.config.hasBackgroundColor = NO;
        self.config.backgroundColor = nil;
        [self refreshAfterChange];
    } else if (row == ArcDetailRowReset) {
        [self confirmReset];
    }
}

#pragma mark - 单元格

- (UITableViewCell *)enabledCell {
    static NSString *ident = @"ArcEnabledCell";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"跟随全局", @"开启", @"关闭"]];
        seg.translatesAutoresizingMaskIntoConstraints = NO;
        [seg addTarget:self action:@selector(onEnabledChanged:) forControlEvents:UIControlEventValueChanged];
        [cell.contentView addSubview:seg];
        [NSLayoutConstraint activateConstraints:@[
            [seg.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [seg.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [seg.widthAnchor constraintEqualToConstant:210],
        ]];
    }
    cell.textLabel.text = @"作用";
    UISegmentedControl *seg = nil;
    for (UIView *v in cell.contentView.subviews) {
        if ([v isKindOfClass:[UISegmentedControl class]]) { seg = (UISegmentedControl *)v; break; }
    }
    seg.selectedSegmentIndex = (NSInteger)self.config.enabledMode;
    return cell;
}

- (void)onEnabledChanged:(UISegmentedControl *)seg {
    self.config.enabledMode = (ArcClassEnabledMode)seg.selectedSegmentIndex;
    [self refreshAfterChange];
}

- (UITableViewCell *)backgroundCell {
    static NSString *ident = @"ArcBgCell";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:ident];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.detailTextLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    }
    cell.textLabel.text = @"背景色";
    if (self.config.hasBackgroundColor) {
        cell.detailTextLabel.text = ArcColorHexString(self.config.backgroundColor);
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 22, 22)];
        swatch.backgroundColor = self.config.backgroundColor;
        swatch.layer.cornerRadius = 5;
        swatch.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
        swatch.layer.borderColor = [UIColor separatorColor].CGColor;
        cell.accessoryView = swatch;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.detailTextLabel.text = @"跟随全局";
        cell.detailTextLabel.textColor = [UIColor tertiaryLabelColor];
        cell.accessoryView = nil;
    }
    return cell;
}

- (UITableViewCell *)clearBackgroundCell {
    static NSString *ident = @"ArcClearBgCell";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
        cell.textLabel.font = [UIFont systemFontOfSize:16];
    }
    cell.textLabel.text = @"清除背景色（恢复跟随全局）";
    cell.textLabel.textColor = [UIColor systemRedColor];
    return cell;
}

- (UITableViewCell *)forceCircleCell {
    static NSString *ident = @"ArcCircleCell";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:ident];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        UISwitch *sw = [[UISwitch alloc] init];
        [sw addTarget:self action:@selector(onCircleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    }
    cell.textLabel.text = @"强制正圆";
    cell.detailTextLabel.text = @"忽略半径，按最短边取一半";
    UISwitch *sw = (UISwitch *)cell.accessoryView;
    sw.on = self.config.hasForceCircle ? self.config.forceCircle : [ArcPrefs shared].avatarCircle;
    return cell;
}

- (void)onCircleChanged:(UISwitch *)sw {
    self.config.forceCircle = sw.on;
    self.config.hasForceCircle = YES;
    [self refreshAfterChange];
}

- (UITableViewCell *)resetCell {
    static NSString *ident = @"ArcResetCell";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
        cell.textLabel.font = [UIFont systemFontOfSize:16];
    }
    cell.textLabel.text = @"重置该类的配置";
    cell.textLabel.textColor = [UIColor systemRedColor];
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    return cell;
}

- (void)confirmReset {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重置配置？"
                                                                  message:self.className
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self.config reset];
        [self rebuildSections];
        [self.tableView reloadData];
        [[ArcCardEngine shared] reloadAllVisibleTableViews];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 数值输入

- (UIToolbar *)numberToolbar {
    UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                          target:nil action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                          target:self
                                                                          action:@selector(dismissKeyboard)];
    bar.items = @[flex, done];
    return bar;
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (UITableViewCell *)numberCellForRow:(ArcDetailRow)row {
    static NSString *ident = @"ArcNumberCell";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont systemFontOfSize:16];

        UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 96, 32)];
        tf.borderStyle = UITextBorderStyleRoundedRect;
        tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        tf.returnKeyType = UIReturnKeyDone;
        tf.textAlignment = NSTextAlignmentRight;
        tf.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
        tf.placeholder = @"全局";
        tf.delegate = self;
        tf.inputAccessoryView = [self numberToolbar];
        cell.accessoryView = tf;
    }
    UITextField *tf = (UITextField *)cell.accessoryView;
    tf.tag = row;
    tf.placeholder = @"全局";

    NSString *title = @"";
    NSString *value = @"";
    switch (row) {
        case ArcDetailRowRadius:
            title = @"圆角半径 (pt)";
            value = self.config.hasCornerRadius
                ? [NSString stringWithFormat:@"%g", self.config.cornerRadius] : @"";
            break;
        case ArcDetailRowInsetTop:
            title = @"上缩进 (pt)";
            value = self.config.hasInsets ? [NSString stringWithFormat:@"%g", self.config.insetTop] : @"";
            break;
        case ArcDetailRowInsetLeft:
            title = @"左缩进 (pt)";
            value = self.config.hasInsets ? [NSString stringWithFormat:@"%g", self.config.insetLeft] : @"";
            break;
        case ArcDetailRowInsetBottom:
            title = @"下缩进 (pt)";
            value = self.config.hasInsets ? [NSString stringWithFormat:@"%g", self.config.insetBottom] : @"";
            break;
        case ArcDetailRowInsetRight:
            title = @"右缩进 (pt)";
            value = self.config.hasInsets ? [NSString stringWithFormat:@"%g", self.config.insetRight] : @"";
            break;
        default: break;
    }
    cell.textLabel.text = title;
    tf.text = value;
    return cell;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    // 用户一开始输入就视为"该类要自定义这一项"
    if (textField.tag == ArcDetailRowRadius) {
        self.config.hasCornerRadius = YES;
    } else {
        self.config.hasInsets = YES;
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    NSString *raw = [textField.text stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    CGFloat value = MAX(0, MIN(999, [raw doubleValue]));
    textField.text = raw.length ? [NSString stringWithFormat:@"%g", value] : @"";

    switch (textField.tag) {
        case ArcDetailRowRadius:       self.config.cornerRadius = value; break;
        case ArcDetailRowInsetTop:     self.config.insetTop = value; break;
        case ArcDetailRowInsetLeft:    self.config.insetLeft = value; break;
        case ArcDetailRowInsetBottom:  self.config.insetBottom = value; break;
        case ArcDetailRowInsetRight:   self.config.insetRight = value; break;
        default: break;
    }
    [self refreshAfterChange];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - 取色

- (void)presentColorPicker {
    if (@available(iOS 14.0, *)) {
        UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
        picker.delegate = self;
        picker.supportsAlpha = YES;
        picker.selectedColor = self.config.hasBackgroundColor ? self.config.backgroundColor : [UIColor whiteColor];
        [self presentViewController:picker animated:YES completion:nil];
        return;
    }
    [self presentLegacyColorSheet];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {
    self.config.backgroundColor = viewController.selectedColor;
    self.config.hasBackgroundColor = YES;
    [self refreshAfterChange];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController API_AVAILABLE(ios(14.0)) {
    [self dismissViewControllerAnimated:YES completion:nil];
}

/// iOS 14 以下没有系统取色器时的兜底：预设色板
- (void)presentLegacyColorSheet {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择背景色"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    NSDictionary<NSString *, UIColor *> *colors = @{
        @"纯白":   [UIColor whiteColor],
        @"浅灰":   [UIColor colorWithRed:0.957 green:0.957 blue:0.969 alpha:1.0],
        @"深空灰": [UIColor colorWithRed:0.11 green:0.11 blue:0.118 alpha:1.0],
        @"纯黑":   [UIColor blackColor],
        @"微信绿": [UIColor colorWithRed:0.055 green:0.737 blue:0.361 alpha:1.0],
        @"半透明黑": [UIColor colorWithWhite:0.0 alpha:0.35],
        @"半透明白": [UIColor colorWithWhite:1.0 alpha:0.35],
    };
    for (NSString *name in colors) {
        [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            self.config.backgroundColor = colors[name];
            self.config.hasBackgroundColor = YES;
            [self refreshAfterChange];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
