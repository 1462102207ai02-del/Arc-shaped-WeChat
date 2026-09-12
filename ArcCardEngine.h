//
//  ArcCardEngine.h
//  Arc-shaped WeChat
//
//  卡片化引擎：判定作用域 → 计算单元格在"卡"中的位置 → 下发圆角/缩进/背景/描边/分隔线
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ArcCellPosition) {
    ArcCellPositionUnknown = 0,
    ArcCellPositionSingle,   // 分组内只有一行（或每行独立成卡）
    ArcCellPositionFirst,    // 卡顶
    ArcCellPositionMiddle,   // 卡中
    ArcCellPositionLast,     // 卡底
};

/// 画在 cell.backgroundView 上的卡片底板
@interface ArcCardBackgroundView : UIView
@property (nonatomic, assign) UIEdgeInsets cardInsets;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) UIRectCorner corners;
@property (nonatomic, strong) UIColor *fillColor;
@property (nonatomic, strong) UIColor *borderColor;
@property (nonatomic, assign) CGFloat borderWidth;
@property (nonatomic, assign) BOOL showDivider;
@property (nonatomic, assign) CGFloat dividerInset;
@property (nonatomic, strong) UIColor *dividerColor;
- (void)refresh;
@end

@interface ArcCardEngine : NSObject

+ (instancetype)shared;

/// 该表格是否需要卡片化（结果按 tableView 缓存）
- (BOOL)isCardEnabledForTableView:(UITableView *)tableView;

/// 给 cell 的 frame 施加左右缩进；由 -[UITableViewCell setFrame:] 钩子调用
- (CGRect)adjustedFrameForCell:(UITableViewCell *)cell frame:(CGRect)frame;

/// 主入口：在 willDisplay / _configureCellForDisplay 时调用
- (void)applyCardToCell:(UITableViewCell *)cell
              tableView:(UITableView *)tableView
              indexPath:(NSIndexPath *)indexPath;

/// 计算位置
- (ArcCellPosition)positionForTableView:(UITableView *)tableView
                              indexPath:(NSIndexPath *)indexPath
                            rowCardMode:(BOOL)rowCardMode;

/// 分组间距：由 heightForHeader/Footer 钩子调用
- (CGFloat)extraSpacingForHeaderInTableView:(UITableView *)tableView;
- (CGFloat)extraSpacingForFooterInTableView:(UITableView *)tableView;

/// 立刻重绘当前所有表格（改设置后即时生效）
- (void)reloadAllVisibleTableViews;

/// 作用页面白名单（可运行时追加）
@property (nonatomic, strong) NSMutableSet<NSString *> *whitelist;
@property (nonatomic, strong) NSMutableSet<NSString *> *blacklist;
/// 这些页面"每一行都是一张独立的卡"
@property (nonatomic, strong) NSMutableSet<NSString *> *rowCardPages;

@end

NS_ASSUME_NONNULL_END
