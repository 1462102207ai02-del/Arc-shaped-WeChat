//
//  ArcTargetClasses.h
//  Arc-shaped WeChat
//
//  目标类清单，全部来自《微信圆角 dylib 逆向分析报告》第三节的内嵌 NSString 常量。
//
//  [A] 视图/单元/按钮/图片/控件类（11）  -> 强制圆角
//  [B] 控制器/页面/窗口类（74）          -> 列表卡片化
//  [C] 其它（7）                        -> 纳入白名单
//

#ifndef ArcTargetClasses_h
#define ArcTargetClasses_h

#import <Foundation/Foundation.h>

#pragma mark - [A] 强制圆角目标（视图类）

static NSString *const kArcForceRoundClasses[] = {
    @"ColorGradientView",
    @"MMHeadImageView",
    @"MMImageGridView",
    @"MMTransparentButton",
    @"MMUIButton",
    @"MMUIView",
    @"MMWebImageView",
    @"WCImageView",
};
static const NSUInteger kArcForceRoundClassCount =
    sizeof(kArcForceRoundClasses) / sizeof(kArcForceRoundClasses[0]);

/// 单元格类单独处理：已被卡片化的 cell 会被跳过，避免二次裁剪
static NSString *const kArcForceRoundCellClasses[] = {
    @"MMTableViewCell",
    @"SettingCell",
};
static const NSUInteger kArcForceRoundCellClassCount =
    sizeof(kArcForceRoundCellClasses) / sizeof(kArcForceRoundCellClasses[0]);

/// 整表圆角（默认关闭，容易和页面背景冲突）
static NSString *const kArcForceRoundTableClasses[] = {
    @"MMTableView",
};
static const NSUInteger kArcForceRoundTableClassCount =
    sizeof(kArcForceRoundTableClasses) / sizeof(kArcForceRoundTableClasses[0]);

#pragma mark - [B] + [C] 列表卡片化白名单

static NSString *const kArcWhitelistClasses[] = {
    // —— [B] 控制器 / 页面 / 窗口（74）——
    @"BizTLPersonalCenterMainViewController",
    @"BrandProfileMsgTabViewController",
    @"BrandTimelineSettingViewController",
    @"BrandTimelineViewController",
    @"ChatBackgroundEntranceViewController",
    @"ChatBoxSessionListViewController6666",
    @"ChatRoomAdminMemberSelectViewController",
    @"ChatRoomInfoProfileRoomContactSelectViewController",
    @"ChatRoomInfoViewController",
    @"ChatRoomInvitationListViewController",
    @"ChatRoomManagementViewController",
    @"ChatRoomSpecialAttentionMemberSelectViewController",
    @"ChatRoomStillNotificationMsgViewController",
    @"ContactRelatedChatRoomListViewController",
    @"ContactSetPermissionsViewController",
    @"ContactSettingViewController",
    @"ContactsGenericViewController",
    @"DouTuSettingViewController",
    @"EmoticonManagePrivacySettingViewController",
    @"EmoticonManageViewController",
    @"FTSDetailResultViewController",
    @"FTSHomeViewController",
    @"FTSMsgScopeViewController",
    @"LiufsWxSettingViewController",
    @"LiufsWxThemesViewController",
    @"MMLogViewController",
    @"MMNewMultiSelectContactsViewController",
    @"MMPageSheetContainerViewController",
    @"MMPageSheetContainerWindowController",
    @"MMRegionPickerViewController",
    @"MMShowHelpViewController",
    @"MMUINavigationController",
    @"MiYouSettingViewController",
    @"MsgFileBrowseViewController",
    @"MsgRecordDetailViewController",
    @"MultiSelectContactsViewController",
    @"RoomContactSelectForHalfScreenViewController",
    @"RoomContactSelectViewController",
    @"SessionSelectController",
    @"SettingAboutMMViewController",
    @"SettingAddMeWayViewController",
    @"SettingChatCellViewController",
    @"SettingDarkModeViewController",
    @"SettingDiscoverEntranceViewControllerV2",
    @"SettingGeneralUserInterfaceViewController",
    @"SettingGeneralViewController",
    @"SettingLanguageViewController",
    @"SettingModifySignViewController",
    @"SettingMyAccountInfoViewController",
    @"SettingMyAccountMoreViewController",
    @"SettingMyProfileViewController",
    @"SettingNotificationDetailViewController",
    @"SettingNotificationViewController",
    @"SettingOtherFunctionCellViewController",
    @"SettingPluginsViewController",
    @"SettingPrivateConfigViewController",
    @"SettingPrivateSecondConfigViewController",
    @"SettingQuickReplyViewController",
    @"SettingVoipCellViewController",
    @"SettingsMomentsCellViewController",
    @"SettingsTingViewController",
    @"WCAppAuthListViewController",
    @"WCCommentDetailViewControllerFB",
    @"WCCustomizeViewController",
    @"WCDBRecoverViewController",
    @"WCFinderAccountSettingViewController",
    @"WCFinderPrimarySettingViewController",
    @"WCFinderPrivacySettingViewController",
    @"WCMomentsPrivacyViewController",
    @"WCPluginsViewController",
    @"WCRedEnvelopesMakeRedEnvelopesViewController",
    @"WCTimeLineViewController",
    @"WCVoicesViewController",
    @"WeChatRoundedCornersSettingsController",

    // —— [C] 其它（7）——
    @"Input",
    @"Notify",
    @"SettingUtil",
    @"Video",
    @"WCFinderInteractionLimitCommentBulletVC",
    @"WCFinderInteractionLimitMessageVC",
    @"WCPluginsMgr",

    // —— 补充：四个一级 Tab ——
    @"NewMainFrameViewController",
    @"ContactsViewController",
    @"MoreViewController",
    @"FindFriendEntryViewController",
};
static const NSUInteger kArcWhitelistClassCount =
    sizeof(kArcWhitelistClasses) / sizeof(kArcWhitelistClasses[0]);

#pragma mark - 永远跳过（破坏性 / 支付 / 输入类页面）

static NSString *const kArcBlacklistClasses[] = {
    @"BaseMsgContentViewController",
    @"ChatBoxViewController",
    @"EmoticonBoardViewController",
    @"MMWebViewController",
    @"WCPayViewController",
    @"WCPayMainViewController",
    @"WCRedEnvelopesViewController",
    @"ArcShapedWeChatSettingsController",
};
static const NSUInteger kArcBlacklistClassCount =
    sizeof(kArcBlacklistClasses) / sizeof(kArcBlacklistClasses[0]);

#pragma mark - 每一行独立成卡的页面

static NSString *const kArcRowCardClasses[] = {
    @"NewMainFrameViewController",
    @"ChatBoxSessionListViewController6666",
    @"SessionSelectController",
};
static const NSUInteger kArcRowCardClassCount =
    sizeof(kArcRowCardClasses) / sizeof(kArcRowCardClasses[0]);

#endif /* ArcTargetClasses_h */
