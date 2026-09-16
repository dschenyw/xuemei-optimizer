#import <Cocoa/Cocoa.h>

static NSString * const XMCVersion = @"4.1.5";

@interface XMCAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSWindow *window;
@property (strong) NSView *rootView;
@property (strong) NSView *sidebar;
@property (strong) NSView *mainView;
@property (strong) NSMutableDictionary<NSString *, NSButton *> *checks;
@property (strong) NSMutableDictionary<NSString *, NSString *> *scanValues;
@property (strong) NSTextField *sourceField;
@property (strong) NSTextField *selectedSummaryLabel;
@property (strong) NSTextView *fullDiskTextView;
@property (strong) NSTextField *fullDiskProgressLabel;
@property (strong) NSProgressIndicator *fullDiskSpinner;
@property (strong) NSTimer *fullDiskProgressTimer;
@property (strong) NSTableView *fullDiskTable;
@property (strong) NSPopUpButton *fullDiskFilterPopup;
@property (strong) NSSearchField *fullDiskSearchField;
@property (strong) NSTextField *fullDiskResultSummaryLabel;
@property (strong) NSArray<NSDictionary *> *fullDiskItems;
@property (strong) NSArray<NSDictionary *> *filteredFullDiskItems;
@property (copy) NSString *fullDiskResultFile;

@property (strong) NSTableView *installerTable;
@property (strong) NSPopUpButton *installerFilterPopup;
@property (strong) NSSearchField *installerSearchField;
@property (strong) NSTextField *installerSummaryLabel;
@property (strong) NSArray<NSDictionary *> *installerItems;
@property (strong) NSArray<NSDictionary *> *filteredInstallerItems;
@property (copy) NSString *installerRoot;
@property (copy) NSString *installerResultFile;

@property (strong) NSTextView *diagnosticTextView;
@property (copy) NSString *diagnosticCommand;
@property (copy) NSString *diagnosticPageKey;

@property (copy) NSString *currentPage;
@end

@implementation XMCAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSString *state = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/雪梅清理"];
    [[NSFileManager defaultManager] createDirectoryAtPath:state withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *startupLog = [state stringByAppendingPathComponent:@"native-ui.log"];
    NSString *line = [NSString stringWithFormat:@"[%@] v4.1.5 applicationDidFinishLaunching\\n", [NSDate date]];
    [line writeToFile:startupLog atomically:YES encoding:NSUTF8StringEncoding error:nil];

    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    self.checks = [NSMutableDictionary dictionary];
    self.scanValues = [NSMutableDictionary dictionary];
    self.fullDiskItems = @[];
    self.filteredFullDiskItems = @[];
    self.installerItems = @[];
    self.filteredInstallerItems = @[];

    NSString *savedInstallerRoot = [self persistedInstallerRoot];
    if (savedInstallerRoot.length &&
        [[NSFileManager defaultManager] fileExistsAtPath:savedInstallerRoot]) {
        self.installerRoot = savedInstallerRoot;
    }

    self.currentPage = @"dashboard";
    [self buildWindow];
    [self renderCurrentPage];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (NSString *)installerRootStateFile {
    NSString *state =
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/雪梅清理"];
    [[NSFileManager defaultManager] createDirectoryAtPath:state
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return [state stringByAppendingPathComponent:@"installer-last-root.txt"];
}

- (NSString *)persistedInstallerRoot {
    NSString *path = [self installerRootStateFile];
    NSString *root = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
    return [root stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (void)saveInstallerRoot:(NSString *)root {
    if (!root.length) return;
    [root writeToFile:[self installerRootStateFile]
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:nil];
}

- (NSString *)installerRootForOneClick {
    if (self.installerRoot.length &&
        [[NSFileManager defaultManager] fileExistsAtPath:self.installerRoot]) {
        return self.installerRoot;
    }

    NSString *saved = [self persistedInstallerRoot];
    if (saved.length && [[NSFileManager defaultManager] fileExistsAtPath:saved]) {
        return saved;
    }

    NSString *downloads = [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:downloads]) {
        return downloads;
    }

    return @"";
}

- (NSString *)enginePath {

    return [[NSBundle mainBundle] pathForResource:@"engine" ofType:@"sh"];
}

- (NSString *)runEngine:(NSArray<NSString *> *)args {
    NSString *engine = [self enginePath];
    if (!engine) return @"ERROR=NO_ENGINE";

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];

    NSMutableArray *allArgs = [NSMutableArray arrayWithObject:engine];
    [allArgs addObjectsFromArray:args ?: @[]];
    task.arguments = allArgs;

    NSMutableDictionary *env = [NSMutableDictionary dictionaryWithDictionary:NSProcessInfo.processInfo.environment];
    env[@"XMC_APP_ROOT"] = NSBundle.mainBundle.bundlePath;
    task.environment = env;

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        return [NSString stringWithFormat:@"ERROR=%@", error.localizedDescription ?: @"launch failed"];
    }
    [task waitUntilExit];

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return text ?: @"";
}

- (NSDictionary<NSString *, NSString *> *)parseKV:(NSString *)text {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSRange r = [line rangeOfString:@"="];
        if (r.location == NSNotFound || r.location == 0) continue;
        NSString *k = [line substringToIndex:r.location];
        NSString *v = [line substringFromIndex:r.location + 1];
        d[k] = v;
    }
    return d;
}

- (NSString *)formatKB:(long long)kb {
    if (kb >= 1048576) return [NSString stringWithFormat:@"%.2f GB", (double)kb / 1048576.0];
    if (kb >= 1024) return [NSString stringWithFormat:@"%.2f MB", (double)kb / 1024.0];
    return [NSString stringWithFormat:@"%lld KB", kb];
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size bold:(BOOL)bold {
    NSTextField *l = [NSTextField labelWithString:text ?: @""];
    l.font = bold ? [NSFont systemFontOfSize:size weight:NSFontWeightSemibold] : [NSFont systemFontOfSize:size];
    l.textColor = NSColor.labelColor;
    return l;
}

- (NSTextField *)secondary:(NSString *)text size:(CGFloat)size {
    NSTextField *l = [self label:text size:size bold:NO];
    l.textColor = NSColor.secondaryLabelColor;
    return l;
}

- (NSImageView *)brandImageViewWithFrame:(NSRect)frame {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"BrandCalligraphy" ofType:@"png"];
    NSImageView *v = [[NSImageView alloc] initWithFrame:frame];
    v.imageScaling = NSImageScaleProportionallyUpOrDown;
    v.imageAlignment = NSImageAlignCenter;
    if (path) {
        NSImage *img = [[NSImage alloc] initWithContentsOfFile:path];
        v.image = img;
    }
    return v;
}

- (NSButton *)button:(NSString *)title tag:(NSInteger)tag action:(SEL)action {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bezelStyle = NSBezelStyleRounded;
    b.tag = tag;
    return b;
}

- (NSBox *)boxWithFrame:(NSRect)frame {
    NSBox *b = [[NSBox alloc] initWithFrame:frame];
    b.boxType = NSBoxCustom;
    b.cornerRadius = 12;
    b.borderColor = NSColor.separatorColor;
    b.fillColor = NSColor.controlBackgroundColor;
    return b;
}

- (void)add:(NSView *)child to:(NSView *)parent frame:(NSRect)frame {
    child.frame = frame;
    [parent addSubview:child];
}

- (void)clearMain {
    if (![self.currentPage isEqualToString:@"fullDisk"]) {
        [self stopFullDiskProgressTimer];
    }
    for (NSView *v in [self.mainView.subviews copy]) [v removeFromSuperview];
    [self.checks removeAllObjects];
    self.selectedSummaryLabel = nil;
    self.fullDiskProgressLabel = nil;
    self.fullDiskSpinner = nil;
    self.fullDiskTable = nil;
    self.fullDiskFilterPopup = nil;
    self.fullDiskSearchField = nil;
    self.fullDiskResultSummaryLabel = nil;
    self.installerTable = nil;
    self.installerFilterPopup = nil;
    self.installerSearchField = nil;
    self.installerSummaryLabel = nil;
    self.diagnosticTextView = nil;
}

- (void)buildWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1180, 760)
                                             styleMask:NSWindowStyleMaskTitled |
                                                       NSWindowStyleMaskClosable |
                                                       NSWindowStyleMaskMiniaturizable |
                                                       NSWindowStyleMaskResizable
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"雪梅优化";
    self.window.minSize = NSMakeSize(1040, 680);
    self.window.delegate = self;
    self.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;

    NSButton *zoomButton = [self.window standardWindowButton:NSWindowZoomButton];
    zoomButton.enabled = YES;

    [self.window center];

    NSView *content = self.window.contentView;
    content.wantsLayer = YES;
    content.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

    // 整个 UI 使用固定的 1180×760 逻辑坐标。
    // 当窗口最大化/全屏时，仅缩放这个根视图的 frame，
    // rootView.bounds 始终保持设计尺寸，因此所有子控件会按比例整体缩放，
    // 不再固定在左下角。
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1180, 760)];
    root.bounds = NSMakeRect(0, 0, 1180, 760);
    root.autoresizingMask = NSViewNotSizable;
    root.wantsLayer = YES;
    root.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    self.rootView = root;
    [content addSubview:root];

    NSVisualEffectView *sidebar = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 190, 760)];
    sidebar.material = NSVisualEffectMaterialSidebar;
    sidebar.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    sidebar.autoresizingMask = NSViewNotSizable;
    self.sidebar = sidebar;
    [root addSubview:sidebar];

    NSView *main = [[NSView alloc] initWithFrame:NSMakeRect(190, 0, 990, 760)];
    main.autoresizingMask = NSViewNotSizable;
    self.mainView = main;
    [root addSubview:main];

    NSImageView *brandMark = [self brandImageViewWithFrame:NSMakeRect(14, 678, 162, 58)];
    [sidebar addSubview:brandMark];
    NSTextField *brandSub = [self secondary:@"CXM System Optimizer" size:10.5];
    brandSub.alignment = NSTextAlignmentCenter;
    [self add:brandSub to:sidebar frame:NSMakeRect(14, 657, 162, 16)];

    // 紧凑主功能区：减少按钮高度与间距，避免侧栏纵向浪费。
    NSArray *primaryNav = @[
        @[@"总览", @1],
        @[@"智能优化", @2],
        @[@"全盘扫描", @3],
        @[@"安装包清理", @4],
        @[@"大文件", @5],
        @[@"应用管理", @6],
        @[@"启动项", @7],
        @[@"内存", @8],
        @[@"网络", @9],
        @[@"系统健康", @10]
    ];

    CGFloat y = 610;
    for (NSArray *item in primaryNav) {
        NSButton *b = [self button:item[0]
                               tag:[item[1] integerValue]
                            action:@selector(navClicked:)];
        b.alignment = NSTextAlignmentLeft;
        [self add:b to:sidebar frame:NSMakeRect(14, y, 162, 27)];
        y -= 31;
    }

    // 工具入口继续使用与主导航完全一致的 31px 垂直节距。
    NSArray *utilityNav = @[
        @[@"保护中心", @11],
        @[@"软件更新", @12],
        @[@"关于", @13]
    ];

    for (NSArray *item in utilityNav) {
        NSButton *b = [self button:item[0]
                               tag:[item[1] integerValue]
                            action:@selector(navClicked:)];
        b.alignment = NSTextAlignmentLeft;
        [self add:b to:sidebar frame:NSMakeRect(14, y, 162, 27)];
        y -= 31;
    }

    // 版本号 / 退出固定底部，和导航区保持适度距离。
    [self add:[self secondary:[NSString stringWithFormat:@"v%@", XMCVersion] size:10.5]
            to:sidebar frame:NSMakeRect(16, 50, 158, 18)];

    NSButton *quit = [self button:@"退出" tag:99 action:@selector(quitApp:)];
    [self add:quit to:sidebar frame:NSMakeRect(14, 14, 162, 28)];

    [self layoutRootViewForWindow];
}

- (void)layoutRootViewForWindow {
    if (!self.window || !self.rootView) return;

    NSView *content = self.window.contentView;
    if (!content) return;

    const CGFloat designWidth = 1180.0;
    const CGFloat designHeight = 760.0;

    NSRect available = content.bounds;
    CGFloat availableWidth = NSWidth(available);
    CGFloat availableHeight = NSHeight(available);

    if (availableWidth <= 0 || availableHeight <= 0) return;

    CGFloat scaleX = availableWidth / designWidth;
    CGFloat scaleY = availableHeight / designHeight;
    CGFloat scale = MIN(scaleX, scaleY);

    // 不允许异常数值；窗口小于设计尺寸时允许等比例缩小。
    if (!isfinite(scale) || scale <= 0) scale = 1.0;

    CGFloat scaledWidth = floor(designWidth * scale);
    CGFloat scaledHeight = floor(designHeight * scale);

    // 侧栏必须始终贴住窗口最左边。
    // 宽屏产生的额外空间只留在主内容区右侧，不再左右对称留白。
    CGFloat originX = 0.0;
    CGFloat originY = floor((availableHeight - scaledHeight) / 2.0);

    self.rootView.frame = NSMakeRect(originX, originY, scaledWidth, scaledHeight);
    self.rootView.bounds = NSMakeRect(0, 0, designWidth, designHeight);
}

- (void)windowDidResize:(NSNotification *)notification {
    [self layoutRootViewForWindow];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self layoutRootViewForWindow];
    });
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self layoutRootViewForWindow];
    });
}

- (NSRect)windowWillUseStandardFrame:(NSWindow *)window
                         defaultFrame:(NSRect)newFrame {
    NSScreen *screen = window.screen ?: NSScreen.mainScreen;
    return screen ? screen.visibleFrame : newFrame;
}

- (void)navClicked:(NSButton *)sender {

    NSArray *pages = @[
        @"dashboard", @"scan", @"fullDisk", @"installers", @"large",
        @"applications", @"startup", @"memory", @"network", @"health",
        @"protection", @"update", @"about"
    ];
    NSInteger idx = sender.tag - 1;
    if (idx >= 0 && idx < (NSInteger)pages.count) {
        self.currentPage = pages[idx];
        [self renderCurrentPage];
    }
}

- (void)quitApp:(id)sender {
    [NSApp terminate:nil];
}

- (void)renderHeader:(NSString *)title subtitle:(NSString *)subtitle {
    [self add:[self label:title size:27 bold:YES] to:self.mainView frame:NSMakeRect(30, 700, 640, 36)];
    [self add:[self secondary:subtitle size:13] to:self.mainView frame:NSMakeRect(30, 676, 800, 22)];
}

- (long long)scanLong:(NSString *)key {
    return [self.scanValues[key] longLongValue];
}

- (void)renderCurrentPage {
    if ([self.currentPage isEqualToString:@"dashboard"]) [self renderDashboard];
    else if ([self.currentPage isEqualToString:@"scan"]) [self renderScanPage];
    else if ([self.currentPage isEqualToString:@"fullDisk"]) [self renderFullDiskPage];
    else if ([self.currentPage isEqualToString:@"installers"]) [self renderInstallerCleanerPage];
    else if ([self.currentPage isEqualToString:@"large"]) [self renderLargePage];
    else if ([self.currentPage isEqualToString:@"applications"]) [self renderApplicationsPage];
    else if ([self.currentPage isEqualToString:@"startup"]) [self renderStartupPage];
    else if ([self.currentPage isEqualToString:@"memory"]) [self renderMemoryPage];
    else if ([self.currentPage isEqualToString:@"network"]) [self renderNetworkPage];
    else if ([self.currentPage isEqualToString:@"health"]) [self renderHealthPage];
    else if ([self.currentPage isEqualToString:@"protection"]) [self renderProtection];
    else if ([self.currentPage isEqualToString:@"update"]) [self renderUpdate];
    else [self renderAbout];
}

- (long long)selectedCleanKB {
    long long total = 0;
    NSDictionary<NSString *, NSString *> *map = @{
        @"cache": @"CACHE_KB",
        @"dev": @"DEV_KB",
        @"xcode": @"XCODE_KB",
        @"logs": @"LOGS_KB"
    };

    for (NSString *key in map) {
        NSButton *button = self.checks[key];
        if (button && button.state == NSControlStateValueOn) {
            total += [self scanLong:map[key]];
        }
    }
    return total;
}

- (void)refreshSelectedSummary {
    if (!self.selectedSummaryLabel) return;
    long long selected = [self selectedCleanKB];
    self.selectedSummaryLabel.stringValue =
        [NSString stringWithFormat:@"当前已选择：%@", [self formatKB:selected]];
}

- (void)cleanSelectionChanged:(NSButton *)sender {
    [self refreshSelectedSummary];
}

- (void)renderCategoryRowsAtY:(CGFloat)y {
    NSArray *rows = @[
        @[@"cache", @"应用缓存", @"保护项已排除", @( [self scanLong:@"CACHE_KB"] ), @YES],
        @[@"dev", @"开发工具缓存", @"npm / pip / uv / Homebrew", @( [self scanLong:@"DEV_KB"] ), @YES],
        @[@"xcode", @"Xcode DerivedData", @"编译派生缓存，不删除源码", @( [self scanLong:@"XCODE_KB"] ), @YES],
        @[@"logs", @"用户日志", @"排障可能需要，默认不勾选", @( [self scanLong:@"LOGS_KB"] ), @NO]
    ];

    CGFloat ry = y;
    for (NSArray *r in rows) {
        NSBox *box = [self boxWithFrame:NSMakeRect(30, ry, 920, 58)];
        [self.mainView addSubview:box];
        [self add:[self label:r[1] size:14 bold:YES] to:box frame:NSMakeRect(16, 28, 260, 22)];
        [self add:[self secondary:r[2] size:11] to:box frame:NSMakeRect(16, 8, 470, 18)];
        [self add:[self label:[self formatKB:[r[3] longLongValue]] size:13 bold:YES]
                to:box frame:NSMakeRect(650, 19, 130, 22)];

        NSButton *c = [NSButton checkboxWithTitle:@"" target:self action:@selector(cleanSelectionChanged:)];
        c.state = [r[4] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
        [self add:c to:box frame:NSMakeRect(820, 18, 32, 24)];
        self.checks[r[0]] = c;
        ry -= 68;
    }
}

- (void)renderDashboard {
    [self clearMain];
    [self renderHeader:@"Mac 系统优化总览" subtitle:@"清理、存储、应用、内存、网络和系统健康统一管理。"];

    NSBox *disk = [self boxWithFrame:NSMakeRect(30, 470, 445, 170)];
    [self.mainView addSubview:disk];
    [self add:[self label:@"系统磁盘" size:16 bold:YES] to:disk frame:NSMakeRect(20, 120, 180, 24)];

    long long total = [self scanLong:@"DISK_TOTAL_KB"];
    long long free = [self scanLong:@"DISK_FREE_KB"];
    long long used = MAX(0, total - free);
    NSString *diskText = total > 0
        ? [NSString stringWithFormat:@"%@ 已用 / %@，可用 %@", [self formatKB:used], [self formatKB:total], [self formatKB:free]]
        : @"点击“立即扫描”读取磁盘状态";
    [self add:[self label:diskText size:14 bold:YES] to:disk frame:NSMakeRect(20, 86, 390, 25)];

    NSProgressIndicator *p = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 54, 390, 16)];
    p.indeterminate = NO;
    p.minValue = 0; p.maxValue = 100;
    p.doubleValue = total > 0 ? (double)used / (double)total * 100.0 : 0;
    [disk addSubview:p];
    [self add:[self secondary:[NSString stringWithFormat:@"已发现可清理：%@", [self formatKB:[self scanLong:@"TOTAL_SAFE_KB"]] ] size:11.5]
            to:disk frame:NSMakeRect(20, 27, 360, 20)];

    self.selectedSummaryLabel = [self secondary:@"当前已选择：0 KB" size:11.5];
    self.selectedSummaryLabel.textColor = NSColor.systemBlueColor;
    [self add:self.selectedSummaryLabel to:disk frame:NSMakeRect(20, 8, 360, 20)];

    NSBox *safe = [self boxWithFrame:NSMakeRect(490, 470, 470, 170)];
    [self.mainView addSubview:safe];
    [self add:[self label:@"安全策略" size:16 bold:YES] to:safe frame:NSMakeRect(20, 120, 180, 24)];
    [self add:[self secondary:@"默认只清理可重建缓存；日志默认不勾选。" size:12]
            to:safe frame:NSMakeRect(20, 88, 390, 24)];
    [self add:[self secondary:@"Chrome/TikTok、Codex、IOTA/SN9、Docker、密钥和源码均保护。" size:11]
            to:safe frame:NSMakeRect(20, 60, 395, 24)];
    [self add:[self button:@"立即扫描" tag:0 action:@selector(startScan:)] to:safe frame:NSMakeRect(20, 18, 130, 32)];
    [self add:[self button:@"清理已选" tag:0 action:@selector(startClean:)] to:safe frame:NSMakeRect(165, 18, 130, 32)];

    [self add:[self label:@"清理分类" size:18 bold:YES] to:self.mainView frame:NSMakeRect(30, 425, 200, 28)];
    [self renderCategoryRowsAtY:365];
    [self refreshSelectedSummary];
}

- (void)renderScanPage {
    [self clearMain];
    [self renderHeader:@"智能优化" subtitle:@"扫描低风险缓存与开发垃圾，确认后再执行安全清理。"];
    [self add:[self button:@"开始扫描" tag:0 action:@selector(startScan:)] to:self.mainView frame:NSMakeRect(30, 625, 140, 34)];
    [self add:[self button:@"打开扫描报告" tag:0 action:@selector(openReports:)] to:self.mainView frame:NSMakeRect(185, 625, 150, 34)];
    [self add:[self label:@"扫描结果" size:18 bold:YES] to:self.mainView frame:NSMakeRect(30, 580, 200, 28)];
    [self renderCategoryRowsAtY:515];
    [self add:[self secondary:[NSString stringWithFormat:@"已发现可清理：%@", [self formatKB:[self scanLong:@"TOTAL_SAFE_KB"]]] size:12.5]
            to:self.mainView frame:NSMakeRect(30, 225, 320, 22)];

    self.selectedSummaryLabel = [self secondary:@"当前已选择：0 KB" size:12.5];
    self.selectedSummaryLabel.textColor = NSColor.systemBlueColor;
    [self add:self.selectedSummaryLabel to:self.mainView frame:NSMakeRect(30, 198, 320, 22)];
    [self refreshSelectedSummary];

    [self add:[self button:@"安全清理已选择" tag:0 action:@selector(startClean:)] to:self.mainView frame:NSMakeRect(30, 150, 160, 36)];
}

- (void)renderFullDiskPage {
    [self clearMain];
    [self renderHeader:@"全盘扫描" subtitle:@"静默白名单扫描 + 结果浏览器：分类查看候选文件，双击即可在 Finder 定位。"];

    [self add:[self button:@"开始全盘扫描" tag:0 action:@selector(startFullDiskScan:)]
            to:self.mainView frame:NSMakeRect(30, 625, 140, 34)];

    [self add:[self button:@"停止扫描" tag:0 action:@selector(stopFullDiskScan:)]
            to:self.mainView frame:NSMakeRect(180, 625, 110, 34)];

    if (self.fullDiskResultFile.length) {
        [self add:[self button:@"打开原始结果" tag:0 action:@selector(revealFullDiskResult:)]
                to:self.mainView frame:NSMakeRect(300, 625, 130, 34)];
    }

    if (self.fullDiskItems.count) {
        [self add:[self button:@"Finder 定位所选" tag:0 action:@selector(revealSelectedFullDiskItem:)]
                to:self.mainView frame:NSMakeRect(440, 625, 145, 34)];

        [self add:[self button:@"一键安全清理" tag:0 action:@selector(cleanSafeFullDiskItems:)]
                to:self.mainView frame:NSMakeRect(595, 625, 140, 34)];
    }

    self.fullDiskSpinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(750, 632, 18, 18)];
    self.fullDiskSpinner.style = NSProgressIndicatorStyleSpinning;
    self.fullDiskSpinner.displayedWhenStopped = NO;
    [self.mainView addSubview:self.fullDiskSpinner];

    self.fullDiskProgressLabel = [self secondary:@"状态：等待扫描" size:11.5];
    [self add:self.fullDiskProgressLabel to:self.mainView frame:NSMakeRect(775, 625, 145, 30)];

    NSBox *notice = [self boxWithFrame:NSMakeRect(30, 548, 920, 56)];
    [self.mainView addSubview:notice];
    [self add:[self label:@"只读结果浏览器" size:14 bold:YES] to:notice frame:NSMakeRect(16, 28, 180, 22)];
    [self add:[self secondary:@"按类别筛选、搜索并在 Finder 定位。结果会深度识别来源：系统缓存、应用支持、运行时/SDK、开发工具、应用内部、系统目录、个人文件；未确认来源的压缩包只标为“其他压缩资源”，不再冒充安装包。" size:11.5]
            to:notice frame:NSMakeRect(16, 7, 830, 20)];

    if (!self.fullDiskItems.count) {
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(30, 70, 890, 455)];
        scroll.hasVerticalScroller = YES;
        scroll.borderType = NSBezelBorder;

        NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 870, 440)];
        tv.editable = NO;
        tv.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
        tv.string = self.fullDiskTextView.string.length ? self.fullDiskTextView.string : @"尚未进行全盘扫描。";
        scroll.documentView = tv;
        self.fullDiskTextView = tv;
        [self.mainView addSubview:scroll];
        return;
    }

    self.fullDiskFilterPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(30, 505, 170, 30) pullsDown:NO];
    [self.fullDiskFilterPopup addItemsWithTitles:@[@"全部", @"可安全清理", @"大文件", @"个人安装包", @"缓存/临时安装包", @"开发工具资源", @"应用支持资源", @"运行时/工具资源", @"系统缓存资源", @"其他压缩资源", @"应用内部资源", @"系统资源", @"长期未修改"]];
    self.fullDiskFilterPopup.target = self;
    self.fullDiskFilterPopup.action = @selector(fullDiskFilterChanged:);
    [self.mainView addSubview:self.fullDiskFilterPopup];

    self.fullDiskSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(215, 505, 330, 30)];
    self.fullDiskSearchField.placeholderString = @"搜索文件名或完整路径";
    self.fullDiskSearchField.target = self;
    self.fullDiskSearchField.action = @selector(fullDiskSearchChanged:);
    self.fullDiskSearchField.sendsSearchStringImmediately = YES;
    [self.mainView addSubview:self.fullDiskSearchField];

    self.fullDiskResultSummaryLabel = [self secondary:@"" size:11.5];
    [self add:self.fullDiskResultSummaryLabel to:self.mainView frame:NSMakeRect(565, 505, 355, 30)];

    NSScrollView *tableScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(30, 70, 920, 420)];
    tableScroll.hasVerticalScroller = YES;
    tableScroll.hasHorizontalScroller = YES;
    tableScroll.borderType = NSBezelBorder;
    tableScroll.autohidesScrollers = YES;

    NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 1050, 420)];
    table.rowHeight = 27;
    table.usesAlternatingRowBackgroundColors = YES;
    table.allowsMultipleSelection = NO;
    table.dataSource = self;
    table.delegate = self;
    table.target = self;
    table.doubleAction = @selector(revealSelectedFullDiskItem:);

    NSArray *columnSpecs = @[
        @[@"risk", @"安全性", @105],
        @[@"type", @"类型", @135],
        @[@"source", @"来源", @115],
        @[@"level", @"大小级别", @95],
        @[@"status", @"状态", @105],
        @[@"name", @"文件名", @235],
        @[@"path", @"路径", @480]
    ];

    for (NSArray *spec in columnSpecs) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        col.title = spec[1];
        col.width = [spec[2] doubleValue];
        col.minWidth = 70;
        [table addTableColumn:col];
    }

    tableScroll.documentView = table;
    self.fullDiskTable = table;
    [self.mainView addSubview:tableScroll];

    [self applyFullDiskFilter];
}

- (NSString *)normalizedDataPath:(NSString *)path {
    if (!path.length) return @"";

    NSString *prefix = @"/System/Volumes/Data";
    if ([path hasPrefix:prefix]) {
        NSString *stripped = [path substringFromIndex:prefix.length];
        return stripped.length ? stripped : @"/";
    }
    return path;
}

- (BOOL)isApplicationInternalResourcePath:(NSString *)path {
    NSString *normalized = [self normalizedDataPath:path];
    NSString *lower = normalized.lowercaseString;

    if ([lower containsString:@".app/contents/"]) return YES;

    // 全盘扫描结果来自 Applications 根目录时，即使路径因表格截断看不到
    // .app/Contents，也明确视为应用资源。
    if ([lower hasPrefix:@"/applications/"] ||
        [lower hasPrefix:[NSHomeDirectory().lowercaseString stringByAppendingString:@"/applications/"]]) {
        return YES;
    }

    return NO;
}

- (BOOL)isSystemProtectedResourcePath:(NSString *)path {
    NSString *normalized = [self normalizedDataPath:path];
    NSString *lower = normalized.lowercaseString;

    NSArray<NSString *> *prefixes = @[
        @"/system/",
        @"/library/",
        @"/usr/",
        @"/bin/",
        @"/sbin/"
    ];

    for (NSString *prefix in prefixes) {
        if ([lower hasPrefix:prefix]) return YES;
    }

    return NO;
}

- (NSString *)fullDiskSourceForPath:(NSString *)path {
    NSString *normalized = [self normalizedDataPath:path];
    NSString *home = NSHomeDirectory();
    NSString *lower = normalized.lowercaseString;

    if ([self isApplicationInternalResourcePath:path]) return @"应用内部";
    if ([self isSystemProtectedResourcePath:path]) return @"系统目录";

    // /private/var/folders 是 macOS 与应用生成的缓存/运行时区域，
    // 其中的 ZIP/IMG 不应算成用户安装包。
    if ([normalized hasPrefix:@"/private/var/folders/"]) return @"系统缓存";

    NSArray<NSString *> *temporaryPrefixes = @[
        @"/private/tmp/",
        @"/private/var/tmp/"
    ];
    for (NSString *prefix in temporaryPrefixes) {
        if ([normalized hasPrefix:prefix]) return @"临时目录";
    }

    NSArray<NSString *> *cachePrefixes = @[
        [home stringByAppendingPathComponent:@"Library/Caches/"],
        [home stringByAppendingPathComponent:@".cache/"],
        [home stringByAppendingPathComponent:@".npm/_cacache/"],
        [home stringByAppendingPathComponent:@".gradle/caches/"],
        [home stringByAppendingPathComponent:@".cargo/registry/cache/"]
    ];
    for (NSString *prefix in cachePrefixes) {
        if ([normalized hasPrefix:prefix]) return @"缓存目录";
    }

    NSString *derivedData =
        [home stringByAppendingPathComponent:@"Library/Developer/Xcode/DerivedData/"];
    if ([normalized hasPrefix:derivedData]) return @"Xcode DerivedData";

    // 系统级 + 用户级开发工具/运行时目录。
    NSArray<NSString *> *developerPrefixes = @[
        @"/opt/",
        @"/usr/local/",
        @"/Library/Developer/",
        [home stringByAppendingPathComponent:@"Library/Developer/"],
        [home stringByAppendingPathComponent:@".npm/"],
        [home stringByAppendingPathComponent:@".gradle/"],
        [home stringByAppendingPathComponent:@".cargo/"],
        [home stringByAppendingPathComponent:@".rustup/"]
    ];
    for (NSString *prefix in developerPrefixes) {
        if ([normalized hasPrefix:prefix]) return @"开发工具目录";
    }

    NSArray<NSString *> *appSupportPrefixes = @[
        @"/Library/Application Support/",
        [home stringByAppendingPathComponent:@"Library/Application Support/"]
    ];
    for (NSString *prefix in appSupportPrefixes) {
        if ([normalized hasPrefix:prefix]) return @"应用支持资源";
    }

    // 即便路径没有落在上面的固定根目录，只要明显属于框架、SDK、
    // 运行时、虚拟化工具等，也视为受保护运行资源。
    NSArray<NSString *> *runtimeTokens = @[
        @"/frameworks/",
        @"/resources/",
        @"/runtime/",
        @"/runtimes/",
        @"/sdk/",
        @"/sdks/",
        @"/toolchains/",
        @"/node_modules/",
        @"/site-packages/",
        @"/python",
        @"/ruby/",
        @"/java/",
        @"/jvm/",
        @"/flutter/",
        @"/android/",
        @"/parallels/",
        @"/virtualbox/",
        @"/vmware/"
    ];
    for (NSString *token in runtimeTokens) {
        if ([lower containsString:token]) return @"运行时/工具资源";
    }

    NSArray<NSString *> *personalPrefixes = @[
        [home stringByAppendingPathComponent:@"Downloads/"],
        [home stringByAppendingPathComponent:@"Desktop/"],
        [home stringByAppendingPathComponent:@"Documents/"],
        [home stringByAppendingPathComponent:@"Public/"]
    ];
    for (NSString *prefix in personalPrefixes) {
        if ([normalized hasPrefix:prefix]) return @"个人文件";
    }

    if ([lower containsString:@"/library/"]) return @"Library 资源";

    return @"其他";
}

- (NSString *)fullDiskSafetyForPath:(NSString *)path {
    if (!path.length) return @"仅查看";

    NSString *source = [self fullDiskSourceForPath:path];

    if ([source isEqualToString:@"应用内部"]) return @"应用保护";
    if ([source isEqualToString:@"系统目录"]) return @"系统保护";
    if ([source isEqualToString:@"开发工具目录"]) return @"开发资源保护";
    if ([source isEqualToString:@"应用支持资源"]) return @"应用资源保护";
    if ([source isEqualToString:@"运行时/工具资源"]) return @"运行时保护";
    if ([source isEqualToString:@"系统缓存"]) return @"系统缓存保护";

    if ([source isEqualToString:@"临时目录"] ||
        [source isEqualToString:@"缓存目录"] ||
        [source isEqualToString:@"Xcode DerivedData"]) {
        return @"可安全清理";
    }

    NSString *normalized = [self normalizedDataPath:path];
    NSString *lower = normalized.lowercaseString;

    NSArray<NSString *> *protectedTokens = @[
        @"/.codex/", @"/.ssh/", @"/keychains/", @"/keychain",
        @"google/chrome", @"tiktok", @"chatgpt", @"openai",
        @"clash", @"docker", @"iota", @"bittensor", @"macrocosmos",
        @"wallet", @"secret", @"api_key", @"apikey"
    ];

    for (NSString *token in protectedTokens) {
        if ([lower containsString:token]) return @"仅查看";
    }

    return @"仅查看";
}

- (void)loadFullDiskResultsFromFile:(NSString *)path {

    if (!path.length) {
        self.fullDiskItems = @[];
        self.filteredFullDiskItems = @[];
        return;
    }

    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:path
                                                 encoding:NSUTF8StringEncoding
                                                    error:&error];
    if (!content) {
        self.fullDiskItems = @[];
        self.filteredFullDiskItems = @[];
        return;
    }

    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    NSSet *archiveExtensions = [NSSet setWithArray:@[@"dmg", @"pkg", @"zip", @"tgz", @"gz", @"xz", @"7z", @"rar", @"iso"]];

    for (NSString *line in [content componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (!line.length) continue;

        NSArray<NSString *> *parts = [line componentsSeparatedByString:@"\t"];
        if (parts.count < 2) continue;

        NSString *level = parts[0];
        NSString *status = @"";
        NSString *filePath = @"";

        if (parts.count >= 3) {
            status = parts[1];
            filePath = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@"\t"];
        } else {
            // 向后兼容 v2.7.x 的两列结果：分类<TAB>路径
            filePath = parts[1];
        }

        if (!filePath.length) continue;

        NSString *ext = filePath.pathExtension.lowercaseString;
        NSString *source = [self fullDiskSourceForPath:filePath];

        BOOL archiveLike =
            [level isEqualToString:@"安装包/压缩包"] ||
            [archiveExtensions containsObject:ext];

        NSString *type = @"大文件";

        if ([source isEqualToString:@"应用内部"]) {
            type = @"应用内部资源";
        } else if ([source isEqualToString:@"系统目录"]) {
            type = @"系统资源";
        } else if ([source isEqualToString:@"系统缓存"]) {
            type = archiveLike ? @"系统缓存资源" : @"系统缓存大文件";
        } else if ([source isEqualToString:@"应用支持资源"]) {
            type = @"应用支持资源";
        } else if ([source isEqualToString:@"运行时/工具资源"]) {
            type = @"运行时/工具资源";
        } else if ([source isEqualToString:@"开发工具目录"]) {
            type = @"开发工具资源";
        } else if ([source isEqualToString:@"缓存目录"] ||
                   [source isEqualToString:@"临时目录"] ||
                   [source isEqualToString:@"Xcode DerivedData"]) {
            type = archiveLike ? @"缓存/临时安装包" : @"缓存/开发大文件";
        } else if ([source isEqualToString:@"个人文件"] && archiveLike) {
            type = @"个人安装包";
        } else if (archiveLike) {
            // 来源无法确认时只认作压缩/镜像资源，不再冒充“安装包”。
            type = @"其他压缩资源";
        }

        NSString *name = filePath.lastPathComponent.length ? filePath.lastPathComponent : filePath;
        NSString *risk = [self fullDiskSafetyForPath:filePath];

        [items addObject:@{
            @"type": type ?: @"",
            @"source": source ?: @"其他",
            @"level": level ?: @"",
            @"status": status.length ? status : @"—",
            @"risk": risk ?: @"仅查看",
            @"name": name ?: @"",
            @"path": filePath ?: @""
        }];
    }

    self.fullDiskItems = items;
    self.filteredFullDiskItems = items;

    if (items.count == 0 && content.length > 0) {
        NSLog(@"雪梅优化：扫描结果文件非空，但没有解析出表格行：%@", path);
    }
}

- (void)applyFullDiskFilter {
    NSArray<NSDictionary *> *source = self.fullDiskItems ?: @[];
    NSString *filter = self.fullDiskFilterPopup.selectedItem.title ?: @"全部";
    NSString *query = [self.fullDiskSearchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    NSMutableArray<NSDictionary *> *filtered = [NSMutableArray array];

    for (NSDictionary *item in source) {
        BOOL categoryMatch = YES;

        if ([filter isEqualToString:@"可安全清理"]) {
            categoryMatch = [item[@"risk"] isEqualToString:@"可安全清理"];
        } else if ([filter isEqualToString:@"大文件"]) {
            categoryMatch =
                [item[@"type"] isEqualToString:@"大文件"] ||
                [item[@"type"] isEqualToString:@"缓存/开发大文件"] ||
                [item[@"type"] isEqualToString:@"系统缓存大文件"];
        } else if ([filter isEqualToString:@"个人安装包"]) {
            categoryMatch = [item[@"type"] isEqualToString:@"个人安装包"];
        } else if ([filter isEqualToString:@"缓存/临时安装包"]) {
            categoryMatch = [item[@"type"] isEqualToString:@"缓存/临时安装包"];
        } else if ([filter isEqualToString:@"开发工具资源"]) {
            categoryMatch = [item[@"type"] isEqualToString:@"开发工具资源"];
        } else if ([filter isEqualToString:@"应用支持资源"]) {
            categoryMatch = [item[@"type"] isEqualToString:@"应用支持资源"];
        } else if ([filter isEqualToString:@"运行时/工具资源"]) {
            categoryMatch = [item[@"type"] isEqualToString:@"运行时/工具资源"];
        } else if ([filter isEqualToString:@"系统缓存资源"]) {
            categoryMatch =
                [item[@"type"] isEqualToString:@"系统缓存资源"] ||
                [item[@"type"] isEqualToString:@"系统缓存大文件"];
        } else if ([filter isEqualToString:@"其他压缩资源"]) {
            categoryMatch = [item[@"type"] isEqualToString:@"其他压缩资源"];
        } else if ([filter isEqualToString:@"应用内部资源"]) {
            categoryMatch = [item[@"type"] isEqualToString:@"应用内部资源"];
        } else if ([filter isEqualToString:@"系统资源"]) {
            categoryMatch = [item[@"type"] isEqualToString:@"系统资源"];
        } else if ([filter isEqualToString:@"长期未修改"]) {
            categoryMatch = [item[@"status"] isEqualToString:@"长期未修改"];
        }

        if (!categoryMatch) continue;

        BOOL searchMatch = YES;
        if (query.length) {
            NSRange r1 = [item[@"name"] rangeOfString:query options:NSCaseInsensitiveSearch];
            NSRange r2 = [item[@"path"] rangeOfString:query options:NSCaseInsensitiveSearch];
            searchMatch = (r1.location != NSNotFound || r2.location != NSNotFound);
        }

        if (searchMatch) [filtered addObject:item];
    }

    self.filteredFullDiskItems = filtered;
    [self.fullDiskTable reloadData];

    NSUInteger safeCount = 0;
    NSUInteger largeCount = 0;
    NSUInteger personalInstallerCount = 0;
    NSUInteger cacheInstallerCount = 0;
    NSUInteger developerCount = 0;
    NSUInteger supportCount = 0;
    NSUInteger runtimeCount = 0;
    NSUInteger systemCacheCount = 0;
    NSUInteger otherArchiveCount = 0;
    NSUInteger appResourceCount = 0;

    for (NSDictionary *item in source) {
        if ([item[@"risk"] isEqualToString:@"可安全清理"]) safeCount++;

        if ([item[@"type"] isEqualToString:@"大文件"] ||
            [item[@"type"] isEqualToString:@"缓存/开发大文件"] ||
            [item[@"type"] isEqualToString:@"系统缓存大文件"]) {
            largeCount++;
        }

        if ([item[@"type"] isEqualToString:@"个人安装包"]) personalInstallerCount++;
        if ([item[@"type"] isEqualToString:@"缓存/临时安装包"]) cacheInstallerCount++;
        if ([item[@"type"] isEqualToString:@"开发工具资源"]) developerCount++;
        if ([item[@"type"] isEqualToString:@"应用支持资源"]) supportCount++;
        if ([item[@"type"] isEqualToString:@"运行时/工具资源"]) runtimeCount++;
        if ([item[@"type"] isEqualToString:@"系统缓存资源"]) systemCacheCount++;
        if ([item[@"type"] isEqualToString:@"其他压缩资源"]) otherArchiveCount++;
        if ([item[@"type"] isEqualToString:@"应用内部资源"]) appResourceCount++;
    }

    if (self.fullDiskResultSummaryLabel) {
        self.fullDiskResultSummaryLabel.stringValue =
            [NSString stringWithFormat:
                @"显示 %lu/%lu · 可清理 %lu · 大文件 %lu · 个人安装包 %lu · 缓存包 %lu · 开发/运行时 %lu · 应用资源 %lu · 其他压缩 %lu",
             (unsigned long)filtered.count,
             (unsigned long)source.count,
             (unsigned long)safeCount,
             (unsigned long)largeCount,
             (unsigned long)personalInstallerCount,
             (unsigned long)cacheInstallerCount,
             (unsigned long)(developerCount + runtimeCount),
             (unsigned long)(supportCount + appResourceCount),
             (unsigned long)otherArchiveCount];
    }
}

- (void)fullDiskFilterChanged:(id)sender {
    [self applyFullDiskFilter];
}

- (void)fullDiskSearchChanged:(id)sender {
    [self applyFullDiskFilter];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.fullDiskTable) {
        return (NSInteger)self.filteredFullDiskItems.count;
    }
    if (tableView == self.installerTable) {
        return (NSInteger)self.filteredInstallerItems.count;
    }
    return 0;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    NSDictionary *item = nil;

    if (tableView == self.fullDiskTable) {
        if (row < 0 || row >= (NSInteger)self.filteredFullDiskItems.count) return nil;
        item = self.filteredFullDiskItems[(NSUInteger)row];
    } else if (tableView == self.installerTable) {
        if (row < 0 || row >= (NSInteger)self.filteredInstallerItems.count) return nil;
        item = self.filteredInstallerItems[(NSUInteger)row];
    } else {
        return nil;
    }

    NSString *identifier = tableColumn.identifier;
    NSString *value = item[identifier] ?: @"";

    NSTextField *field = [NSTextField labelWithString:value];
    field.font = [NSFont systemFontOfSize:11.5];
    field.lineBreakMode = NSLineBreakByTruncatingMiddle;
    field.toolTip = value;
    field.identifier = identifier;
    return field;
}

- (void)cleanSafeFullDiskItems:(id)sender {
    if (!self.fullDiskResultFile.length) {
        [self showAlert:@"一键安全清理" message:@"当前没有可用的全盘扫描结果。请先运行一次全盘扫描。"];
        return;
    }

    NSString *installerRoot = [self installerRootForOneClick];

    // 一键安全清理先自动刷新安装包判断，避免重启后 installerItems 为空。
    if (installerRoot.length) {
        self.window.title = @"雪梅优化 — 正在检查安装包…";

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSDictionary *installerKV =
                [self parseKV:[self runEngine:@[@"installer-scan", installerRoot]]];

            dispatch_async(dispatch_get_main_queue(), ^{
                self.window.title = @"雪梅优化";

                if ([installerKV[@"STATUS"] isEqualToString:@"OK"]) {
                    self.installerRoot = installerKV[@"ROOT"] ?: installerRoot;
                    [self saveInstallerRoot:self.installerRoot];
                    self.installerResultFile = installerKV[@"RESULT_FILE"] ?: @"";
                    [self loadInstallerResultsFromFile:self.installerResultFile];

                    [self continueSafeFullDiskCleanup];
                    return;
                }

                if ([installerKV[@"STATUS"] isEqualToString:@"ROOT_PERMISSION_DENIED"]) {
                    [self showAlert:@"安装包目录需要授权"
                            message:@"一键安全清理准备检查 Downloads 中的失效/损坏/已安装安装包，但当前没有访问权限。\n\n请进入“安装包清理”，点击“选择文件夹扫描”并选择 Downloads 一次。之后一键安全清理会自动记住该目录。"];
                    return;
                }

                // 安装包检测异常时不冒险自动删包，只继续缓存/临时文件清理。
                self.installerItems = @[];
                [self continueSafeFullDiskCleanup];
            });
        });

        return;
    }

    [self continueSafeFullDiskCleanup];
}

- (void)continueSafeFullDiskCleanup {
    NSUInteger safeCount = 0;
    for (NSDictionary *item in self.fullDiskItems) {
        if ([item[@"risk"] isEqualToString:@"可安全清理"]) safeCount++;
    }

    NSUInteger installerRecommendedCount = 0;
    for (NSDictionary *item in self.installerItems) {
        if ([item[@"recommend"] isEqualToString:@"建议清理"]) {
            installerRecommendedCount++;
        }
    }

    if (safeCount == 0 && installerRecommendedCount == 0) {
        [self showAlert:@"一键安全清理"
                message:@"当前没有符合安全规则的缓存/临时文件，也没有检测到失效/损坏或已确认安装成功的安装包。"];
        return;
    }

    NSString *message = [NSString stringWithFormat:
        @"本次一键安全清理将处理：\n\n"
         "• 严格安全白名单缓存/临时文件：%lu 个\n"
         "• 失效/损坏/已安装安装包：%lu 个（移到废纸篓）\n\n"
         "正常但仅仅超过30天的安装包不会自动清理。\n"
         "Applications / Xcode.app / Codex / Chrome/TikTok / IOTA / Docker / 密钥 / 源码仍然保护。\n\n"
         "是否继续？",
         (unsigned long)safeCount,
         (unsigned long)installerRecommendedCount];

    if (![self confirm:@"一键安全清理" message:message]) return;

    self.window.title = @"雪梅优化 — 正在安全清理…";

    NSString *resultPath = self.fullDiskResultFile;
    NSArray<NSDictionary *> *installerSnapshot = [self.installerItems copy] ?: @[];
    NSString *installerRootSnapshot = [self.installerRoot copy] ?: @"";

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *kv =
            [self parseKV:[self runEngine:@[@"full-disk-clean-safe", resultPath]]];

        NSUInteger installerTrashed = 0;
        NSUInteger installerTrashFailed = 0;

        if (installerRootSnapshot.length && installerSnapshot.count) {
            NSString *root = [installerRootSnapshot stringByStandardizingPath];
            NSString *prefix =
                [root hasSuffix:@"/"] ? root : [root stringByAppendingString:@"/"];

            for (NSDictionary *item in installerSnapshot) {
                if (![item[@"recommend"] isEqualToString:@"建议清理"]) continue;

                NSString *path = [item[@"path"] stringByStandardizingPath];

                // 二次安全边界：安装包必须仍在用户授权的目录内。
                if (![path hasPrefix:prefix]) {
                    installerTrashFailed++;
                    continue;
                }

                if (![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;

                NSError *trashError = nil;
                NSURL *resultURL = nil;

                if ([[NSFileManager defaultManager]
                        trashItemAtURL:[NSURL fileURLWithPath:path]
                     resultingItemURL:&resultURL
                               error:&trashError]) {
                    installerTrashed++;
                } else {
                    installerTrashFailed++;
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.window.title = @"雪梅优化";

            if (![kv[@"STATUS"] isEqualToString:@"OK"]) {
                [self showAlert:@"一键安全清理失败"
                        message:[NSString stringWithFormat:
                            @"状态：%@", kv[@"STATUS"] ?: @"ENGINE_NO_STATUS"]];
                return;
            }

            long long deletedKB = [kv[@"DELETED_KB"] longLongValue];

            [self showAlert:@"一键安全清理完成"
                    message:[NSString stringWithFormat:
                        @"缓存/临时文件已删除：%@ 个\n"
                         "安装包已移到废纸篓：%lu 个\n"
                         "安装包处理失败：%lu 个\n"
                         "跳过受保护/非白名单：%@ 个\n"
                         "缓存清理失败：%@ 个\n"
                         "缓存实际删除约：%@",
                        kv[@"DELETED_COUNT"] ?: @"0",
                        (unsigned long)installerTrashed,
                        (unsigned long)installerTrashFailed,
                        kv[@"SKIPPED_COUNT"] ?: @"0",
                        kv[@"FAILED_COUNT"] ?: @"0",
                        [self formatKB:deletedKB]]];

            // 清理后重新扫描，刷新全盘结果。
            [self startFullDiskScan:nil];
        });
    });
}


- (void)revealSelectedFullDiskItem:(id)sender {

    NSInteger row = self.fullDiskTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.filteredFullDiskItems.count) {
        [self showAlert:@"Finder 定位" message:@"请先在结果表格中选择一个文件。"];
        return;
    }

    NSDictionary *item = self.filteredFullDiskItems[(NSUInteger)row];
    NSString *path = item[@"path"];
    if (!path.length) return;

    NSURL *url = [NSURL fileURLWithPath:path];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[url]];
}

- (void)stopFullDiskProgressTimer {
    if (self.fullDiskProgressTimer) {
        [self.fullDiskProgressTimer invalidate];
        self.fullDiskProgressTimer = nil;
    }
    [self.fullDiskSpinner stopAnimation:nil];
}

- (void)pollFullDiskProgress:(NSTimer *)timer {
    NSDictionary *kv = [self parseKV:[self runEngine:@[@"full-disk-progress"]]];
    NSString *status = kv[@"STATUS"] ?: @"IDLE";
    NSString *elapsed = kv[@"ELAPSED_SEC"] ?: @"0";
    NSString *seen = kv[@"SEEN_COUNT"] ?: @"0";
    NSString *count = kv[@"CANDIDATE_COUNT"] ?: @"0";
    NSString *skipped = kv[@"SKIPPED_COUNT"] ?: @"0";
    NSString *privacy = kv[@"PRIVACY_SKIPPED_COUNT"] ?: @"0";
    NSString *path = kv[@"CURRENT_PATH"] ?: @"";

    if ([status isEqualToString:@"ENUMERATING"]) {
        self.fullDiskProgressLabel.stringValue =
            [NSString stringWithFormat:@"静默扫描中 · 隐私跳过 %@ · %@ 秒", privacy, elapsed];

        if (self.fullDiskTextView) {
            self.fullDiskTextView.string =
                [NSString stringWithFormat:
                    @"正在进行静默白名单扫描…\n\n"
                     "当前阶段：%@\n"
                     "已用：%@ 秒\n"
                     "隐私目录主动跳过：%@ 个\n\n"
                     "不会访问桌面、文稿、下载、Music、照片、邮件、信息、iCloud/云盘等受保护目录。",
                     path.length ? path : @"正在扫描安全目录…",
                     elapsed,
                     privacy];
        }
    } else if ([status isEqualToString:@"ANALYZING"]) {
        NSString *shortPath = path;
        if (shortPath.length > 64) {
            shortPath = [NSString stringWithFormat:@"…%@", [shortPath substringFromIndex:shortPath.length - 63]];
        }

        self.fullDiskProgressLabel.stringValue =
            [NSString stringWithFormat:@"候选 %@ · 隐私跳过 %@ · %@ 秒", seen, privacy, elapsed];

        if (self.fullDiskTextView) {
            self.fullDiskTextView.string =
                [NSString stringWithFormat:
                    @"正在全盘扫描…\n\n"
                     "已发现候选：%@ 个\n"
                     "已成功分析：%@ 个\n"
                     "已跳过慢/异常文件：%@ 个\n"
                     "隐私目录主动跳过：%@ 个\n"
                     "扫描耗时：%@ 秒\n\n"
                     "当前候选：\n%@\n\n"
                     "当前版本不再逐个读取文件元数据，直接由 find 完成分级扫描。扫描结果只读，不会自动删除。",
                     seen, count, skipped, privacy, elapsed,
                     shortPath.length ? shortPath : @"正在分析…"];
        }
    } else if ([status isEqualToString:@"FAILED"]) {
        self.fullDiskProgressLabel.stringValue = @"状态：扫描失败";
        [self stopFullDiskProgressTimer];
    } else if ([status isEqualToString:@"CANCELLED"]) {
        self.fullDiskProgressLabel.stringValue = @"状态：已停止";
        [self stopFullDiskProgressTimer];
    } else if ([status isEqualToString:@"DONE"]) {
        self.fullDiskProgressLabel.stringValue =
            [NSString stringWithFormat:@"扫描完成 · %@ 秒", elapsed];
        [self stopFullDiskProgressTimer];
    }
}

- (void)startFullDiskProgressTimer {
    [self stopFullDiskProgressTimer];
    [self.fullDiskSpinner startAnimation:nil];
    self.fullDiskProgressLabel.stringValue = @"状态：正在扫描…";

    self.fullDiskProgressTimer =
        [NSTimer scheduledTimerWithTimeInterval:0.8
                                         target:self
                                       selector:@selector(pollFullDiskProgress:)
                                       userInfo:nil
                                        repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.fullDiskProgressTimer forMode:NSRunLoopCommonModes];
}

- (void)stopFullDiskScan:(id)sender {
    NSDictionary *kv = [self parseKV:[self runEngine:@[@"full-disk-stop"]]];
    NSString *status = kv[@"STATUS"] ?: @"";

    if ([status isEqualToString:@"STOP_SENT"]) {
        self.fullDiskProgressLabel.stringValue = @"状态：正在停止…";
    } else {
        [self showAlert:@"停止扫描" message:@"当前没有正在运行的全盘扫描。"];
    }
}

- (void)startFullDiskScan:(id)sender {

    if (![self confirm:@"开始全盘扫描"
               message:@"静默白名单扫描不会进入桌面、文稿、下载、Music、照片、邮件、信息、iCloud/云盘等隐私目录，因此不会主动触发这些授权弹窗。\n\n整个过程只分析，不删除任何文件。是否继续？"]) return;

    self.window.title = @"雪梅优化 — 正在全盘扫描…";
    [self startFullDiskProgressTimer];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *kv = [self parseKV:[self runEngine:@[@"full-disk"]]];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.window.title = @"雪梅优化";
            [self stopFullDiskProgressTimer];

            if ([kv[@"STATUS"] isEqualToString:@"CANCELLED"]) {
                [self renderFullDiskPage];
                self.fullDiskProgressLabel.stringValue = @"状态：已停止";
                self.fullDiskTextView.string = @"全盘扫描已由用户停止。\n\n已经生成的临时扫描不会执行任何删除。";
                return;
            }

            if (![kv[@"STATUS"] isEqualToString:@"OK"]) {
                NSString *message = nil;
                if ([kv[@"STATUS"] isEqualToString:@"FIND_FATAL"]) {
                    message = [NSString stringWithFormat:
                        @"全盘扫描命令执行失败。\n\nfind 返回码：%@\n错误日志：%@",
                        kv[@"FIND_EXIT"] ?: @"?",
                        kv[@"ERROR_FILE"] ?: @"-"];
                } else if ([kv[@"STATUS"] isEqualToString:@"POSTPROCESS_FAILED"]) {
                    message = [NSString stringWithFormat:
                        @"扫描已经完成，但结果整理失败。\n\n失败阶段：%@\n结果文件：%@\n错误日志：%@",
                        kv[@"POSTPROCESS_STAGE"] ?: @"unknown",
                        kv[@"RESULT_FILE"] ?: @"-",
                        kv[@"ERROR_FILE"] ?: @"-"];
                } else {
                    message = [NSString stringWithFormat:
                        @"状态：%@\n错误日志：%@",
                        kv[@"STATUS"] ?: @"ENGINE_NO_STATUS",
                        kv[@"ERROR_FILE"] ?: @"-"];
                }
                [self showAlert:@"全盘扫描失败" message:message];
                return;
            }

            self.fullDiskResultFile = kv[@"RESULT_FILE"] ?: @"";
            [self loadFullDiskResultsFromFile:self.fullDiskResultFile];

            NSString *summary = [NSString stringWithFormat:
                @"扫描模式：静默白名单 find-only\n"
                 "扫描根目录：%@\n"
                 "扫描耗时：%@ 秒\n"
                 "find 返回码：%@\n"
                 "磁盘总容量：%@\n"
                 "磁盘可用空间：%@\n\n"
                 "发现候选文件：%@ 个\n"
                 "成功分析：%@ 个\n"
                 "跳过慢/异常文件：%@ 个\n"
                 "隐私目录主动跳过：%@ 个\n"
                 "≥500 MB：%@ 个\n"
                 "≥1 GB：%@ 个\n"
                 "≥5 GB：%@ 个\n"
                 "长期未修改的大文件：%@ 个\n"
                 "安装包/压缩包（<500MB）：%@ 个\n"
                 "无权限/受系统保护项：%@ 个\n\n"
                 "提示：完整候选文件清单已保存为扫描结果文件。",
                 kv[@"SCAN_ROOT"] ?: @"-",
                 kv[@"ELAPSED_SEC"] ?: @"0",
                 kv[@"FIND_EXIT"] ?: @"0",
                 [self formatKB:[kv[@"DISK_TOTAL_KB"] longLongValue]],
                 [self formatKB:[kv[@"DISK_FREE_KB"] longLongValue]],
                 kv[@"SEEN_COUNT"] ?: @"0",
                 kv[@"CANDIDATE_COUNT"] ?: @"0",
                 kv[@"SKIPPED_COUNT"] ?: @"0",
                 kv[@"PRIVACY_SKIPPED_COUNT"] ?: @"0",
                 kv[@"GE500_COUNT"] ?: @"0",
                 kv[@"GE1G_COUNT"] ?: @"0",
                 kv[@"GE5G_COUNT"] ?: @"0",
                 kv[@"OLD_LARGE_COUNT"] ?: @"0",
                 kv[@"INSTALLER_COUNT"] ?: @"0",
                 kv[@"DENIED_COUNT"] ?: @"0"];

            [self renderFullDiskPage];
            if (self.fullDiskTextView) {
                self.fullDiskTextView.string = summary;
            }
            self.fullDiskProgressLabel.stringValue =
                [NSString stringWithFormat:@"扫描完成 · %@ 秒", kv[@"ELAPSED_SEC"] ?: @"0"];

            [self showAlert:@"全盘扫描完成"
                    message:[NSString stringWithFormat:
                        @"发现 %@ 个需要关注的候选文件。\n结果表格已载入 %lu 条。\n\n扫描结果只供分析，不会自动删除。",
                        kv[@"SEEN_COUNT"] ?: kv[@"CANDIDATE_COUNT"] ?: @"0",
                        (unsigned long)self.fullDiskItems.count]];
        });
    });
}

- (void)revealFullDiskResult:(id)sender {
    if (!self.fullDiskResultFile.length) return;
    NSURL *url = [NSURL fileURLWithPath:self.fullDiskResultFile];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[url]];
}

- (void)renderInstallerCleanerPage {
    [self clearMain];
    [self renderHeader:@"安装包清理"
              subtitle:@"主动选择 Downloads / Desktop / Documents 文件夹扫描；系统应用内部安装镜像不会进入此模块。"];

    [self add:[self button:@"选择文件夹扫描" tag:0 action:@selector(scanInstallerFolder:)]
            to:self.mainView frame:NSMakeRect(30, 625, 150, 34)];

    if (self.installerItems.count) {
        [self add:[self button:@"全选当前结果" tag:0 action:@selector(selectAllInstallerRows:)]
                to:self.mainView frame:NSMakeRect(195, 625, 125, 34)];

        [self add:[self button:@"取消全选" tag:0 action:@selector(deselectAllInstallerRows:)]
                to:self.mainView frame:NSMakeRect(330, 625, 105, 34)];

        [self add:[self button:@"Finder 定位所选" tag:0 action:@selector(revealSelectedInstaller:)]
                to:self.mainView frame:NSMakeRect(445, 625, 140, 34)];

        [self add:[self button:@"移到废纸篓所选" tag:0 action:@selector(trashSelectedInstaller:)]
                to:self.mainView frame:NSMakeRect(595, 625, 145, 34)];

        [self add:[self button:@"清理失效/损坏/已安装" tag:0 action:@selector(trashRecommendedInstallers:)]
                to:self.mainView frame:NSMakeRect(750, 625, 135, 34)];
    }

    NSBox *notice = [self boxWithFrame:NSMakeRect(30, 548, 920, 58)];
    [self.mainView addSubview:notice];
    [self add:[self label:@"安全规则" size:14 bold:YES] to:notice frame:NSMakeRect(16, 30, 120, 22)];
    [self add:[self secondary:@"只扫描你主动选择的个人文件夹；Applications、Xcode.app、Library、Codex、密钥等不会进入删除范围。删除统一移到废纸篓，可恢复。" size:11.5]
            to:notice frame:NSMakeRect(16, 8, 840, 20)];

    if (!self.installerItems.count) {
        NSTextField *hint = [self secondary:@"点击“选择文件夹扫描”，建议选择 Downloads。不会自动申请桌面/文稿等权限。" size:13];
        hint.alignment = NSTextAlignmentCenter;
        [self add:hint to:self.mainView frame:NSMakeRect(70, 350, 800, 30)];
        return;
    }

    self.installerFilterPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(30, 505, 170, 30) pullsDown:NO];
    [self.installerFilterPopup addItemsWithTitles:@[@"全部", @"建议清理", @"失效/损坏", @"已安装", @"30天以上", @"近期文件", @"DMG", @"PKG", @"压缩包"]];
    self.installerFilterPopup.target = self;
    self.installerFilterPopup.action = @selector(installerFilterChanged:);
    [self.mainView addSubview:self.installerFilterPopup];

    self.installerSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(215, 505, 330, 30)];
    self.installerSearchField.placeholderString = @"搜索文件名或路径";
    self.installerSearchField.target = self;
    self.installerSearchField.action = @selector(installerSearchChanged:);
    self.installerSearchField.sendsSearchStringImmediately = YES;
    [self.mainView addSubview:self.installerSearchField];

    self.installerSummaryLabel = [self secondary:@"" size:11.5];
    [self add:self.installerSummaryLabel to:self.mainView frame:NSMakeRect(565, 505, 355, 30)];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(30, 70, 920, 420)];
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.autohidesScrollers = YES;

    NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 1050, 420)];
    table.rowHeight = 27;
    table.usesAlternatingRowBackgroundColors = YES;
    table.allowsMultipleSelection = YES;
    table.allowsEmptySelection = YES;
    table.dataSource = self;
    table.delegate = self;
    table.target = self;
    table.doubleAction = @selector(revealSelectedInstaller:);

    NSArray *specs = @[
        @[@"recommend", @"建议", @90],
        @[@"reason", @"原因", @120],
        @[@"type", @"类型", @120],
        @[@"health", @"有效性", @90],
        @[@"installed", @"安装状态", @90],
        @[@"age", @"时间", @90],
        @[@"name", @"文件名", @250],
        @[@"path", @"路径", @500]
    ];

    for (NSArray *spec in specs) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        col.title = spec[1];
        col.width = [spec[2] doubleValue];
        col.minWidth = 70;
        [table addTableColumn:col];
    }

    scroll.documentView = table;
    self.installerTable = table;
    [self.mainView addSubview:scroll];

    [self applyInstallerFilter];
}

- (void)scanInstallerFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.prompt = @"扫描此文件夹";
    panel.message = @"请选择 Downloads、Desktop、Documents 或 Public 中的文件夹。";

    if ([panel runModal] != NSModalResponseOK) return;

    NSString *folder = panel.URL.path;
    if (!folder.length) return;

    [self scanInstallerFolderAtPath:folder showCompletion:YES];
}

- (void)loadInstallerResultsFromFile:(NSString *)path {
    if (!path.length) {
        self.installerItems = @[];
        self.filteredInstallerItems = @[];
        return;
    }

    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:path
                                                 encoding:NSUTF8StringEncoding
                                                    error:&error];

    if (!content) {
        self.installerItems = @[];
        self.filteredInstallerItems = @[];
        return;
    }

    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];

    for (NSString *line in [content componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (!line.length) continue;

        NSArray<NSString *> *parts = [line componentsSeparatedByString:@"\t"];
        if (parts.count < 6) continue;

        NSString *type = parts[0];
        NSString *age = parts[1];
        NSString *health = parts[2];
        NSString *installed = parts[3];
        NSString *reason = parts[4];
        NSString *filePath = [[parts subarrayWithRange:NSMakeRange(5, parts.count - 5)] componentsJoinedByString:@"\t"];
        if (!filePath.length) continue;

        NSString *recommend = [reason isEqualToString:@"保留"] ? @"保留" : @"建议清理";
        NSString *name = filePath.lastPathComponent.length ? filePath.lastPathComponent : filePath;

        [items addObject:@{
            @"recommend": recommend,
            @"type": type ?: @"",
            @"age": age ?: @"",
            @"health": health ?: @"",
            @"installed": installed ?: @"",
            @"reason": reason ?: @"",
            @"name": name ?: @"",
            @"path": filePath ?: @""
        }];
    }

    self.installerItems = items;
    self.filteredInstallerItems = items;
}

- (void)applyInstallerFilter {
    NSArray<NSDictionary *> *source = self.installerItems ?: @[];
    NSString *filter = self.installerFilterPopup.selectedItem.title ?: @"全部";
    NSString *query = [self.installerSearchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    NSMutableArray<NSDictionary *> *filtered = [NSMutableArray array];

    for (NSDictionary *item in source) {
        BOOL match = YES;

        if ([filter isEqualToString:@"建议清理"]) {
            match = [item[@"recommend"] isEqualToString:@"建议清理"];
        } else if ([filter isEqualToString:@"失效/损坏"]) {
            match = [item[@"health"] isEqualToString:@"失效"];
        } else if ([filter isEqualToString:@"已安装"]) {
            match = [item[@"installed"] isEqualToString:@"已安装"];
        } else if ([filter isEqualToString:@"30天以上"]) {
            match = [item[@"age"] isEqualToString:@"30天以上"];
        } else if ([filter isEqualToString:@"近期文件"]) {
            match = [item[@"age"] isEqualToString:@"近期"];
        } else if ([filter isEqualToString:@"DMG"]) {
            match = [item[@"type"] hasPrefix:@"DMG"];
        } else if ([filter isEqualToString:@"PKG"]) {
            match = [item[@"type"] hasPrefix:@"PKG"];
        } else if ([filter isEqualToString:@"压缩包"]) {
            match = [item[@"type"] isEqualToString:@"压缩包"];
        }

        if (!match) continue;

        if (query.length) {
            NSRange r1 = [item[@"name"] rangeOfString:query options:NSCaseInsensitiveSearch];
            NSRange r2 = [item[@"path"] rangeOfString:query options:NSCaseInsensitiveSearch];
            if (r1.location == NSNotFound && r2.location == NSNotFound) continue;
        }

        [filtered addObject:item];
    }

    self.filteredInstallerItems = filtered;
    [self.installerTable reloadData];

    NSUInteger recommendedCount = 0;
    NSUInteger invalidCount = 0;
    NSUInteger installedCount = 0;
    NSUInteger oldCount = 0;

    for (NSDictionary *item in source) {
        if ([item[@"recommend"] isEqualToString:@"建议清理"]) recommendedCount++;
        if ([item[@"health"] isEqualToString:@"失效"]) invalidCount++;
        if ([item[@"installed"] isEqualToString:@"已安装"]) installedCount++;
        if ([item[@"age"] isEqualToString:@"30天以上"]) oldCount++;
    }

    if (self.installerSummaryLabel) {
        self.installerSummaryLabel.stringValue =
            [NSString stringWithFormat:@"显示 %lu/%lu · 建议 %lu · 失效 %lu · 已安装 %lu · 过期 %lu",
             (unsigned long)filtered.count,
             (unsigned long)source.count,
             (unsigned long)recommendedCount,
             (unsigned long)invalidCount,
             (unsigned long)installedCount,
             (unsigned long)oldCount];
    }
}

- (void)installerFilterChanged:(id)sender {
    [self applyInstallerFilter];
}

- (void)installerSearchChanged:(id)sender {
    [self applyInstallerFilter];
}

- (void)selectAllInstallerRows:(id)sender {
    if (!self.installerTable || self.filteredInstallerItems.count == 0) return;

    NSIndexSet *rows =
        [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.filteredInstallerItems.count)];

    [self.installerTable selectRowIndexes:rows byExtendingSelection:NO];
}

- (void)deselectAllInstallerRows:(id)sender {
    [self.installerTable deselectAll:nil];
}

- (void)revealSelectedInstaller:(id)sender {
    NSIndexSet *rows = self.installerTable.selectedRowIndexes;
    NSUInteger row = rows.firstIndex;

    if (row == NSNotFound || row >= self.filteredInstallerItems.count) {
        [self showAlert:@"Finder 定位" message:@"请先选择一个安装包或压缩包。"];
        return;
    }

    NSString *path = self.filteredInstallerItems[row][@"path"];
    if (!path.length) return;

    [[NSWorkspace sharedWorkspace]
        activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
}

- (BOOL)isInstallerPathInsideSelectedRoot:(NSString *)path {
    if (!path.length || !self.installerRoot.length) return NO;

    NSString *root = [self.installerRoot stringByStandardizingPath];
    NSString *candidate = [path stringByStandardizingPath];

    NSString *prefix = [root hasSuffix:@"/"] ? root : [root stringByAppendingString:@"/"];
    return [candidate hasPrefix:prefix];
}

- (BOOL)trashInstallerItem:(NSDictionary *)item error:(NSError **)error {
    NSString *path = item[@"path"];
    if (![self isInstallerPathInsideSelectedRoot:path]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.cxm.xuemeicleaner"
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"文件不在本次用户选择的扫描目录内"}];
        }
        return NO;
    }

    NSURL *url = [NSURL fileURLWithPath:path];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return YES;

    NSURL *resultURL = nil;
    return [[NSFileManager defaultManager] trashItemAtURL:url
                                          resultingItemURL:&resultURL
                                                    error:error];
}

- (void)trashSelectedInstaller:(id)sender {
    NSIndexSet *rows = self.installerTable.selectedRowIndexes;

    if (rows.count == 0) {
        [self showAlert:@"移到废纸篓" message:@"请先选择一个或多个安装包/压缩包。"];
        return;
    }

    NSMutableArray<NSDictionary *> *targets = [NSMutableArray array];

    [rows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        if (idx < self.filteredInstallerItems.count) {
            [targets addObject:self.filteredInstallerItems[idx]];
        }
    }];

    if (targets.count == 0) return;

    NSString *message = [NSString stringWithFormat:
        @"将把 %lu 个所选文件移到废纸篓，可从废纸篓恢复。\n\n"
         "只处理本次你主动选择的扫描目录内文件。\n"
         "Applications / Xcode.app / Library 等受保护位置不会进入此模块。\n\n"
         "是否继续？",
         (unsigned long)targets.count];

    if (![self confirm:@"批量移到废纸篓" message:message]) return;

    NSUInteger success = 0;
    NSUInteger failed = 0;

    for (NSDictionary *item in targets) {
        NSError *error = nil;

        if ([self trashInstallerItem:item error:&error]) {
            success++;
        } else {
            failed++;
        }
    }

    [self showAlert:@"批量清理完成"
            message:[NSString stringWithFormat:
                @"已移到废纸篓：%lu 个\n失败：%lu 个",
                (unsigned long)success,
                (unsigned long)failed]];

    [self scanInstallerFolderAtPath:self.installerRoot showCompletion:NO];
}

- (void)trashRecommendedInstallers:(id)sender {
    NSMutableArray<NSDictionary *> *targets = [NSMutableArray array];

    for (NSDictionary *item in self.installerItems) {
        if ([item[@"recommend"] isEqualToString:@"建议清理"]) {
            [targets addObject:item];
        }
    }

    if (targets.count == 0) {
        [self showAlert:@"一键清理建议项"
                message:@"当前没有明确判定为失效/损坏或已安装成功的安装包。"];
        return;
    }

    if (![self confirm:@"一键清理建议项"
               message:[NSString stringWithFormat:
                   @"将把 %lu 个建议清理的安装包/压缩包移到废纸篓。\n\n"
                    "规则只包括：失效/损坏，或已确认对应应用/PKG 已安装。\n"
                    "文件年龄仅作参考；正常但仅仅超过30天的文件不会自动清理。\n\n"
                    "所有文件都进入废纸篓，可恢复。是否继续？",
                   (unsigned long)targets.count]]) return;

    NSUInteger success = 0;
    NSUInteger failed = 0;

    for (NSDictionary *item in targets) {
        NSError *error = nil;
        if ([self trashInstallerItem:item error:&error]) success++;
        else failed++;
    }

    [self showAlert:@"安装包智能清理完成"
            message:[NSString stringWithFormat:
                @"已移到废纸篓：%lu 个\n失败：%lu 个",
                (unsigned long)success,
                (unsigned long)failed]];

    [self scanInstallerFolderAtPath:self.installerRoot showCompletion:NO];
}

- (void)scanInstallerFolderAtPath:(NSString *)folder showCompletion:(BOOL)showCompletion {
    if (!folder.length) return;

    self.window.title = @"雪梅优化 — 正在扫描安装包…";

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *kv = [self parseKV:[self runEngine:@[@"installer-scan", folder]]];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.window.title = @"雪梅优化";

            if (![kv[@"STATUS"] isEqualToString:@"OK"]) {
                [self showAlert:@"安装包扫描失败"
                        message:[NSString stringWithFormat:@"状态：%@", kv[@"STATUS"] ?: @"ENGINE_NO_STATUS"]];
                return;
            }

            self.installerRoot = kv[@"ROOT"] ?: folder;
            [self saveInstallerRoot:self.installerRoot];
            self.installerResultFile = kv[@"RESULT_FILE"] ?: @"";
            [self loadInstallerResultsFromFile:self.installerResultFile];
            [self renderInstallerCleanerPage];

            if (showCompletion) {
                [self showAlert:@"安装包扫描完成"
                        message:[NSString stringWithFormat:
                            @"共发现 %@ 个安装包/压缩包。\n"
                             "建议清理：%@ 个\n"
                             "失效：%@ 个\n"
                             "已安装：%@ 个\n"
                             "30天以上：%@ 个",
                            kv[@"TOTAL_COUNT"] ?: @"0",
                            kv[@"RECOMMENDED_COUNT"] ?: @"0",
                            kv[@"INVALID_COUNT"] ?: @"0",
                            kv[@"INSTALLED_COUNT"] ?: @"0",
                            kv[@"OLD_COUNT"] ?: @"0"]];
            }
        });
    });
}

- (void)renderLargePage {

    [self clearMain];
    [self renderHeader:@"大文件" subtitle:@"仅查看 ≥ 1 GB 文件，不会自动删除。"];
    [self add:[self button:@"扫描大文件" tag:0 action:@selector(loadLargeFiles:)] to:self.mainView frame:NSMakeRect(30, 625, 140, 34)];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(30, 70, 920, 535)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;

    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 870, 520)];
    tv.editable = NO;
    tv.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    tv.string = @"点击“扫描大文件”开始。";
    tv.identifier = @"largeText";
    scroll.documentView = tv;
    [self.mainView addSubview:scroll];
}

- (void)renderDiagnosticPageWithTitle:(NSString *)title
                              subtitle:(NSString *)subtitle
                               command:(NSString *)command
                               pageKey:(NSString *)pageKey {
    [self clearMain];

    self.diagnosticCommand = command;
    self.diagnosticPageKey = pageKey;

    [self renderHeader:title subtitle:subtitle];

    [self add:[self button:@"刷新分析" tag:0 action:@selector(refreshDiagnosticReport:)]
            to:self.mainView frame:NSMakeRect(30, 625, 130, 34)];

    [self add:[self secondary:@"只读诊断模式：当前版本不会在这些页面直接修改系统配置。" size:11.5]
            to:self.mainView frame:NSMakeRect(180, 630, 620, 22)];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(30, 70, 920, 535)];
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = YES;
    scroll.borderType = NSBezelBorder;

    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 870, 520)];
    tv.editable = NO;
    tv.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    tv.string = @"正在分析…";

    scroll.documentView = tv;
    self.diagnosticTextView = tv;
    [self.mainView addSubview:scroll];

    [self refreshDiagnosticReport:nil];
}

- (void)refreshDiagnosticReport:(id)sender {
    NSString *command = self.diagnosticCommand;
    NSString *pageKey = self.diagnosticPageKey;

    if (!command.length || !pageKey.length) return;

    self.diagnosticTextView.string = @"正在分析，请稍候…";

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *output = [self runEngine:@[command]];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self.currentPage isEqualToString:pageKey]) return;
            self.diagnosticTextView.string = output.length ? output : @"没有可显示的数据。";
        });
    });
}

- (void)renderApplicationsPage {
    [self renderDiagnosticPageWithTitle:@"应用管理"
                               subtitle:@"查看 Applications 中应用的磁盘占用；v4.0.0 先做只读分析，不直接卸载。"
                                command:@"apps-report"
                                pageKey:@"applications"];
}

- (void)renderStartupPage {
    [self renderDiagnosticPageWithTitle:@"启动项"
                               subtitle:@"查看用户和系统 LaunchAgents / LaunchDaemons；不自动禁用后台服务。"
                                command:@"startup-report"
                                pageKey:@"startup"];
}

- (void)renderMemoryPage {
    [self renderDiagnosticPageWithTitle:@"内存"
                               subtitle:@"查看物理内存、交换空间、vm_stat 与高内存进程。"
                                command:@"memory-report"
                                pageKey:@"memory"];
}

- (void)renderNetworkPage {
    [self renderDiagnosticPageWithTitle:@"网络"
                               subtitle:@"查看默认路由、系统代理、DNS 与活动网络接口。"
                                command:@"network-report"
                                pageKey:@"network"];
}

- (void)renderHealthPage {
    [self renderDiagnosticPageWithTitle:@"系统健康"
                               subtitle:@"查看 macOS、机型、芯片、负载、磁盘、交换空间、电源与温控状态。"
                                command:@"health-report"
                                pageKey:@"health"];
}

- (void)renderProtection {

    [self clearMain];
    [self renderHeader:@"保护中心" subtitle:@"以下项目不会被“安全清理”自动删除。"];
    NSArray *items = @[
        @"✓ Codex（~/.codex）",
        @"✓ SSH（~/.ssh）",
        @"✓ macOS Keychain",
        @"✓ Chrome / TikTok 登录资料",
        @"✓ ChatGPT / OpenAI 配置",
        @"✓ Clash / 代理配置",
        @"✓ Docker 数据与镜像",
        @"✓ IOTA / SN9 / Bittensor",
        @"✓ 钱包、证书、API Key / Secret",
        @"✓ 开发项目源码",
        @"✓ Desktop / Documents / Downloads / Pictures / Movies / Music 个人文件"
    ];
    CGFloat y = 620;
    for (NSString *t in items) {
        NSBox *b = [self boxWithFrame:NSMakeRect(30, y, 920, 42)];
        [self.mainView addSubview:b];
        [self add:[self label:t size:13 bold:NO] to:b frame:NSMakeRect(16, 10, 820, 22)];
        y -= 48;
    }
    [self add:[self secondary:@"雪梅优化不使用 sudo，也不会执行 docker prune。" size:12]
            to:self.mainView frame:NSMakeRect(30, 75, 500, 22)];
}

- (void)renderUpdate {
    [self clearMain];
    [self renderHeader:@"软件更新" subtitle:@"以后新版本直接在这里更新，不需要重新安装。"];

    NSBox *current = [self boxWithFrame:NSMakeRect(30, 530, 920, 115)];
    [self.mainView addSubview:current];
    [self add:[self label:@"当前版本" size:15 bold:YES] to:current frame:NSMakeRect(18, 72, 150, 24)];
    [self add:[self label:[NSString stringWithFormat:@"雪梅优化 v%@", XMCVersion] size:19 bold:YES]
            to:current frame:NSMakeRect(18, 38, 260, 26)];
    [self add:[self secondary:@"原生 AppKit：已启用" size:12] to:current frame:NSMakeRect(18, 14, 260, 20)];

    NSBox *local = [self boxWithFrame:NSMakeRect(30, 385, 430, 120)];
    [self.mainView addSubview:local];
    [self add:[self label:@"本地更新包" size:15 bold:YES] to:local frame:NSMakeRect(18, 78, 180, 24)];
    [self add:[self secondary:@"选择 ZIP，自动编译新版、备份、替换、重启。" size:11]
            to:local frame:NSMakeRect(18, 50, 380, 20)];
    [self add:[self button:@"选择 ZIP 更新" tag:0 action:@selector(localUpdate:)] to:local frame:NSMakeRect(18, 12, 140, 32)];
    [self add:[self button:@"打开版本备份" tag:0 action:@selector(openBackups:)] to:local frame:NSMakeRect(170, 12, 140, 32)];

    NSBox *online = [self boxWithFrame:NSMakeRect(480, 385, 440, 120)];
    [self.mainView addSubview:online];
    [self add:[self label:@"在线更新" size:15 bold:YES] to:online frame:NSMakeRect(18, 78, 160, 24)];
    [self add:[self secondary:@"配置 HTTPS manifest.json 后可一键检查。" size:11]
            to:online frame:NSMakeRect(18, 50, 390, 20)];
    [self add:[self button:@"检查在线更新" tag:0 action:@selector(checkOnline:)] to:online frame:NSMakeRect(18, 12, 140, 32)];

    NSBox *src = [self boxWithFrame:NSMakeRect(30, 210, 920, 145)];
    [self.mainView addSubview:src];
    [self add:[self label:@"更新源" size:15 bold:YES] to:src frame:NSMakeRect(18, 102, 180, 24)];
    [self add:[self secondary:@"当前尚未绑定公开托管地址；以后可以在这里配置。" size:11]
            to:src frame:NSMakeRect(18, 76, 520, 20)];

    self.sourceField = [[NSTextField alloc] initWithFrame:NSMakeRect(18, 39, 680, 28)];
    self.sourceField.placeholderString = @"https://.../manifest.json";
    NSString *source = [[self runEngine:@[@"get-source"]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.sourceField.stringValue = source ?: @"";
    [src addSubview:self.sourceField];
    [self add:[self button:@"保存" tag:0 action:@selector(saveSource:)] to:src frame:NSMakeRect(715, 37, 110, 30)];

    [self add:[self secondary:@"更新前自动备份；新版编译/校验失败不会覆盖当前版本；替换失败自动回滚。" size:12]
            to:self.mainView frame:NSMakeRect(30, 165, 800, 22)];
}

- (void)renderAbout {
    [self clearMain];
    [self renderHeader:@"关于雪梅优化" subtitle:@"CXM System Optimizer"];
    NSImageView *aboutBrand = [self brandImageViewWithFrame:NSMakeRect(30, 505, 520, 150)];
    [self.mainView addSubview:aboutBrand];

    NSTextField *aboutSub = [self secondary:@"CXM System Optimizer" size:12];
    aboutSub.alignment = NSTextAlignmentCenter;
    [self add:aboutSub to:self.mainView frame:NSMakeRect(30, 487, 520, 20)];

    [self add:[self label:[NSString stringWithFormat:@"v%@", XMCVersion] size:15 bold:YES]
            to:self.mainView frame:NSMakeRect(30, 445, 200, 24)];
    [self add:[self secondary:@"原生 Objective-C + AppKit" size:13]
            to:self.mainView frame:NSMakeRect(30, 410, 400, 24)];
    [self add:[self secondary:@"系统优化 · 安全清理 · 存储分析 · 应用/内存/网络诊断 · 内置更新" size:13]
            to:self.mainView frame:NSMakeRect(30, 375, 500, 24)];
    [self add:[self secondary:@"图标：CXM + 红梅" size:12]
            to:self.mainView frame:NSMakeRect(30, 340, 300, 22)];
    [self add:[self secondary:@"品牌字标：毛体书法 + 红梅" size:12]
            to:self.mainView frame:NSMakeRect(30, 312, 340, 22)];
    [self add:[self secondary:@"Bundle ID：com.cxm.xuemeicleaner" size:12]
            to:self.mainView frame:NSMakeRect(30, 284, 380, 22)];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = title;
    a.informativeText = message ?: @"";
    [a addButtonWithTitle:@"好"];
    [a runModal];
}

- (BOOL)confirm:(NSString *)title message:(NSString *)message {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = title;
    a.informativeText = message ?: @"";
    [a addButtonWithTitle:@"取消"];
    [a addButtonWithTitle:@"继续"];
    return [a runModal] == NSAlertSecondButtonReturn;
}

- (void)startScan:(id)sender {
    self.window.title = @"雪梅优化 — 正在扫描…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *out = [self runEngine:@[@"scan"]];
        NSDictionary *kv = [self parseKV:out];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.scanValues addEntriesFromDictionary:kv];
            self.window.title = @"雪梅优化";
            [self renderCurrentPage];
            [self showAlert:@"扫描完成"
                    message:[NSString stringWithFormat:@"预计可安全清理：%@\n\n用户日志默认不勾选。",
                             [self formatKB:[self scanLong:@"TOTAL_SAFE_KB"]]]];
        });
    });
}

- (NSArray<NSString *> *)selectedCategories {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *key in self.checks) {
        if (self.checks[key].state == NSControlStateValueOn) [a addObject:key];
    }
    return a;
}

- (void)startClean:(id)sender {
    NSArray *cats = [self selectedCategories];
    if (!cats.count) {
        [self showAlert:@"雪梅优化" message:@"没有选择可清理项目。"];
        return;
    }

    NSDictionary *names = @{
        @"cache": @"应用缓存",
        @"dev": @"开发工具缓存",
        @"xcode": @"Xcode DerivedData",
        @"logs": @"用户日志"
    };
    NSMutableArray *pretty = [NSMutableArray array];
    for (NSString *k in cats) [pretty addObject:names[k] ?: k];

    NSString *msg = [NSString stringWithFormat:
        @"将清理：%@\n\n受保护的登录资料、Codex、IOTA/SN9、Docker、密钥、源码和个人文件不会自动删除。",
        [pretty componentsJoinedByString:@"、"]];
    if (![self confirm:@"确认安全清理" message:msg]) return;

    self.window.title = @"雪梅优化 — 正在清理…";
    NSString *arg = [cats componentsJoinedByString:@","];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *kv = [self parseKV:[self runEngine:@[@"clean", arg]]];
        long long cleaned = [kv[@"CLEANED_KB"] longLongValue];
        long long diskDelta = [kv[@"DISK_DELTA_KB"] longLongValue];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.window.title = @"雪梅优化";

            NSString *message = nil;
            if (diskDelta > 0) {
                message = [NSString stringWithFormat:
                    @"本次实际清理文件约：%@\n磁盘可用空间增加约：%@\n\nAPFS 的可用空间统计可能有延迟，清理文件量以第一项为准。",
                    [self formatKB:cleaned],
                    [self formatKB:diskDelta]];
            } else {
                message = [NSString stringWithFormat:
                    @"本次实际清理文件约：%@\n\n当前 APFS 可用空间尚未即时刷新，这是正常现象。\n清理文件量已按清理前后实际文件大小重新计算。",
                    [self formatKB:cleaned]];
            }

            [self showAlert:@"清理完成" message:message];
            [self startScan:nil];
        });
    });
}

- (void)openReports:(id)sender {
    [self runEngine:@[@"open-reports"]];
}

- (void)openBackups:(id)sender {
    [self runEngine:@[@"open-backups"]];
}

- (void)loadLargeFiles:(id)sender {
    self.window.title = @"雪梅优化 — 正在扫描大文件…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *out = [self runEngine:@[@"large"]];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.window.title = @"雪梅优化";
            [self renderLargePage];

            NSScrollView *scroll = nil;
            for (NSView *v in self.mainView.subviews) {
                if ([v isKindOfClass:NSScrollView.class]) { scroll = (NSScrollView *)v; break; }
            }
            NSTextView *tv = (NSTextView *)scroll.documentView;

            NSMutableString *text = [NSMutableString string];
            for (NSString *line in [out componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                if (!line.length) continue;
                NSArray *parts = [line componentsSeparatedByString:@"\t"];
                if (parts.count < 2) continue;
                long long kb = [parts[0] longLongValue];
                NSString *path = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@"\t"];
                [text appendFormat:@"%@   %@\n", [self formatKB:kb], path];
            }
            tv.string = text.length ? text : @"当前扫描范围内未发现 ≥ 1 GB 的文件。";
        });
    });
}

- (void)localUpdate:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedFileTypes = @[@"zip"];

    if ([panel runModal] != NSModalResponseOK) return;

    if (![self confirm:@"安装本地更新包"
               message:@"更新器会先在临时目录编译并校验新版，然后完整备份当前版本，再替换 APP。\n\n更新成功后雪梅优化会自动退出并重新启动。"]) return;

    NSString *path = panel.URL.path;
    self.window.title = @"雪梅优化 — 正在准备更新…";

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *kv = [self parseKV:[self runEngine:@[@"local-update", path]]];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.window.title = @"雪梅优化";
            if ([kv[@"STATUS"] isEqualToString:@"READY"]) {
                NSString *msg = [NSString stringWithFormat:@"将从 v%@ 更新到 v%@。\n\nAPP 即将退出并自动重启。",
                                 kv[@"OLD_VERSION"] ?: XMCVersion,
                                 kv[@"NEW_VERSION"] ?: @"?"];
                [self showAlert:@"更新已准备完成" message:msg];
                [NSApp terminate:nil];
            } else {
                [self showAlert:@"更新失败"
                        message:[NSString stringWithFormat:@"状态：%@\n\n当前版本没有被替换。\n构建日志：~/Library/Application Support/雪梅清理/native-update-build.log",
                                 kv[@"STATUS"] ?: @"未知错误"]];
            }
        });
    });
}

- (void)saveSource:(id)sender {
    NSString *url = [self.sourceField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![url hasPrefix:@"https://"]) {
        [self showAlert:@"更新设置" message:@"在线更新源必须使用 HTTPS。"];
        return;
    }
    NSDictionary *kv = [self parseKV:[self runEngine:@[@"set-source", url]]];
    [self showAlert:@"更新设置" message:[kv[@"STATUS"] isEqualToString:@"OK"] ? @"在线更新源已保存。" : @"保存失败。"];
}

- (void)checkOnline:(id)sender {
    NSDictionary *kv = [self parseKV:[self runEngine:@[@"check-online"]]];
    NSString *status = kv[@"STATUS"];

    if ([status isEqualToString:@"NO_SOURCE"]) {
        [self showAlert:@"在线更新" message:@"尚未配置在线更新源。\n\n目前可以使用“选择 ZIP 更新”。"];
        return;
    }
    if ([status isEqualToString:@"UP_TO_DATE"]) {
        [self showAlert:@"在线更新"
                message:[NSString stringWithFormat:@"当前已经是最新版本。\n\n当前：v%@\n在线：v%@",
                         XMCVersion, kv[@"LATEST"] ?: XMCVersion]];
        return;
    }
    if (![status isEqualToString:@"AVAILABLE"]) {
        [self showAlert:@"在线更新失败"
                message:[NSString stringWithFormat:@"状态：%@", status ?: @"未知错误"]];
        return;
    }

    NSString *latest = kv[@"LATEST"] ?: @"?";
    if (![self confirm:@"发现新版本"
               message:[NSString stringWithFormat:@"当前：v%@\n最新：v%@\n\n是否下载并安装？", XMCVersion, latest]]) return;

    self.window.title = @"雪梅优化 — 正在下载更新…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *result = [self parseKV:[self runEngine:@[@"online-update"]]];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.window.title = @"雪梅优化";
            if ([result[@"STATUS"] isEqualToString:@"READY"]) {
                [self showAlert:@"更新已准备完成" message:@"雪梅优化将退出并自动重启新版。"];
                [NSApp terminate:nil];
            } else {
                [self showAlert:@"在线更新失败"
                        message:[NSString stringWithFormat:@"状态：%@", result[@"STATUS"] ?: @"未知错误"]];
            }
        });
    });
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        XMCAppDelegate *delegate = [[XMCAppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
