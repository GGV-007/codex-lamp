#import <Cocoa/Cocoa.h>

static const NSTimeInterval kPollInterval = 1.0;
static const NSTimeInterval kBlinkInterval = 0.55;
static const NSTimeInterval kStaleBusyWindow = 180.0;
static const NSTimeInterval kUnfinishedTurnTimeout = 30.0;
static const NSTimeInterval kMinSoundGap = 2.0;   // 两声「叮」之间至少隔这么久，防止判定抖动时连响
static const NSTimeInterval kBreathTick = 0.05;   // 黄色呼吸的步进（50ms 一帧，肉眼平滑）
static const NSTimeInterval kBreathPeriod = 2.6;  // 呼吸一个明→暗→明周期（秒），"慢慢"呼吸

// ---- 关于 / 开源署名（V1.6，交接单 JJ-2026-1101-01）----
// 版本号唯一来源：菜单「关于 Codex小灯 → 版本 x.y」从这里读。
// 升版时改这一处即可；同时记得 Info.plist 的 CFBundleShortVersionString / CFBundleVersion 要跟上
// （启动时在 CODEX_LIGHT_DEBUG=1 下会比对，不一致会打印告警）。
static NSString * const kAppVersion = @"1.6";
static NSString * const kProjectURL = @"https://github.com/GGV-007/codex-lamp";
static NSString * const kIssuesURL  = @"https://github.com/GGV-007/codex-lamp/issues";

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (strong) NSStatusItem *item;
@property (strong) NSMenu *menu;
@property (strong) NSTextField *detailField;
@property (strong) NSTextField *taskField;
// ---- Codex 真实用量（5小时窗口 / 本周）----
@property (strong) NSTextField *usageFiveField;
@property (strong) NSTextField *usageWeekField;
@property (strong) NSTextField *usageCardField;   // V1.6：充值卡（额度重置卡）行
@property (copy)   NSString *lastFiveLine;    // 最近一次菜单用量文案（呼吸帧重画用）
@property (copy)   NSString *lastWeekLine;
@property (copy)   NSString *lastCardLine;    // V1.6：充值卡行文案
@property (strong) NSTimer *usageTimer;
@property (strong) NSTimer *cardTimer;        // V1.6：充值卡查询定时器（10 分钟）
@property (nonatomic) BOOL usageFetching;
@property (nonatomic) BOOL cardFetching;      // V1.6
@property (nonatomic) NSTimeInterval usageFetchedAt;
@property (nonatomic) NSInteger fiveHourLeft;   // 5小时剩余百分比，-1 = 还没拿到数据
@property (nonatomic) NSInteger weekLeft;       // 本周（5天）剩余百分比，-1 = 还没拿到数据
@property (copy) NSString *fiveHourReset;       // 5小时窗口重置时间点（本地 HH:mm），如 22:00
@property (strong) NSTimer *pollTimer;
@property (strong) NSTimer *blinkTimer;
@property (strong) NSTimer *breathTimer;          // 5小时额度耗尽（0%）时的黄色呼吸定时器
@property (nonatomic) CFAbsoluteTime breathStart; // 呼吸起点，用于算当前 alpha
@property (nonatomic) BOOL busy;
@property (nonatomic) BOOL blinkOn;
@property (nonatomic) NSTimeInterval lastActivity;
@property (copy) NSString *lastSessionPath;
@property (copy) NSString *currentTitle;
@property (copy) NSString *lastActionText;
@property (copy) NSString *stateReason;
@property (nonatomic) NSTimeInterval busySince;   // 本次变忙的时刻（V1.3：「已忙 X 分 X 秒」用）
// ---- 干完活提示音 ----
@property (nonatomic) BOOL soundEnabled;
@property (copy) NSString *soundPath;
@property (nonatomic) NSTimeInterval lastSoundAt;
@property (strong) NSSound *player;                       // 必须持有，否则声音会被提前释放
@property (strong) NSMenuItem *soundToggleItem;
@property (strong) NSMutableArray<NSMenuItem *> *soundChoiceItems;
- (void)loadSoundPrefs;
- (void)saveSoundPrefs;
- (NSString *)defaultSoundPath;
- (NSArray<NSDictionary<NSString *, NSString *> *> *)availableSounds;
- (void)refreshSoundMenuItems;
- (void)playCompletionSound;
- (void)toggleSound:(id)sender;
- (void)selectSound:(id)sender;
- (void)previewSound:(id)sender;
// ---- Codex 用量 ----
- (void)fetchUsage;
- (void)applyUsage:(NSDictionary *)json;
- (NSString *)formatResetAfter:(NSNumber *)secs;
- (NSString *)resetClockFrom:(NSDictionary *)window;
- (void)setUsageLine:(NSString *)five week:(NSString *)week;
- (void)renderUsageLines;   // 菜单用量两行重画（0% 时由呼吸帧驱动，黄字忽明忽暗）
- (void)renderUsageField:(NSTextField *)field text:(NSString *)text baseColor:(NSColor *)baseColor breathing:(BOOL)breath;
- (void)renderCardLine;   // V1.6：充值卡行（张数绿色加粗）
- (void)openResetLink:(id)sender;   // V1.6：跳 X 上 Tibo（@thsottiaux）
- (void)openAboutLink:(id)sender;   // V1.6：跳「关于」里的外链（项目主页 / Issues）
- (void)renderDetailLine;
// ---- 充值卡（rate-limit reset credits）V1.6 ----
- (void)fetchResetCredits;
- (void)applyResetCredits:(NSDictionary *)json;
- (NSDate *)dateFromISO:(id)value;
- (void)setCardLine:(NSString *)line;
- (void)startUsageTimer;
- (void)updateBreathTimer;   // 5小时额度=0 → 黄色呼吸开/关
- (CGFloat)breathAlpha;      // 当前呼吸亮度 0.25~1.0
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.blinkOn = YES;
    [self loadSoundPrefs];

    // V1.6（交接单 JJ-2026-1101-01）：版本常量与 Info.plist 对不上时告警，
    // 防止「改了源码忘了升 plist」或反过来——只在调试模式下打印，正常启动静默。
    if (getenv("CODEX_LIGHT_DEBUG")) {
        NSString *plistVer = [[NSBundle mainBundle]
            objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        NSLog(@"[boot] Codex小灯 v%@ (plist=%@)%@", kAppVersion, plistVer ?: @"(无)",
              [plistVer isEqualToString:kAppVersion] ? @"" : @"  ⚠️ 版本不一致，请同步！");
    }

    // NSStatusItemVariableLength(-1)：宽度随内容自适应，挂上百分比后不会截断
    self.item = [[NSStatusBar systemStatusBar] statusItemWithLength:-1.0];
    self.fiveHourLeft = -1;   // -1 = 用量还没拿到，菜单栏先只显示 C
    self.weekLeft = -1;

    self.menu = [[NSMenu alloc] initWithTitle:@"Codex小灯"];
    self.menu.delegate = self;
    // V1.0 改版（2026-10-26 刚哥指定）：「当前任务」提为第一行、整行绿字大一号；「最近活动」第二行原样式
    [self.menu addItem:[self fieldItemWithTitle:@"当前任务：未检测" assign:^(NSTextField *field) {
        self.taskField = field;
    }]];
    [self.menu addItem:[self fieldItemWithTitle:@"闲置中" assign:^(NSTextField *field) {
        self.detailField = field;
    }]];
    // 任务行：15 半粗 + 绿色（比常规菜单行大一号），框加高防截字
    self.taskField.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    self.taskField.textColor = [NSColor systemGreenColor];
    self.taskField.frame = NSMakeRect(16, 1, 314 - 16 - 14, 22);
    // 状态行（V1.3）：与其他行同字号（13 半粗），文字白、数字绿由 renderDetailLine 逐段染色
    self.detailField.textColor = [NSColor labelColor];
    [self.menu addItem:[NSMenuItem separatorItem]];

    [self.menu addItem:[self fieldItemWithTitle:@"5小时剩余：--" assign:^(NSTextField *field) {
        self.usageFiveField = field;
    }]];
    [self.menu addItem:[self fieldItemWithTitle:@"本周剩余：--" assign:^(NSTextField *field) {
        self.usageWeekField = field;
    }]];
    // V1.6（2026-11-01 刚哥指定）：本周剩余下面加一行充值卡，只显示「几张 + 最近到期日」
    [self.menu addItem:[self fieldItemWithTitle:@"充值卡：--" assign:^(NSTextField *field) {
        self.usageCardField = field;
    }]];
    self.usageFiveField.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    self.usageWeekField.font = [NSFont systemFontOfSize:12];
    self.usageCardField.font = [NSFont systemFontOfSize:12];
    self.usageFiveField.textColor = [NSColor secondaryLabelColor];
    self.usageWeekField.textColor = [NSColor secondaryLabelColor];
    self.usageCardField.textColor = [NSColor secondaryLabelColor];
    [self.menu addItem:[NSMenuItem separatorItem]];

    // ---- V1.6（2026-11-01 刚哥指定）：一键跳 Tibo 的 X，单独放两个分隔线中间 ----
    // OpenAI 每次发 Codex 额度重置，都是 Codex&ChatGPT 负责人 Tibo（Thibault Sottiaux）
    // 先在 X 上发帖（@thsottiaux），官方没有重置状态页，盯他最快。
    NSMenuItem *tibo = [[NSMenuItem alloc] initWithTitle:@"去Tibo 的 X 账号看看"
                                                  action:@selector(openResetLink:)
                                           keyEquivalent:@""];
    tibo.target = self;
    tibo.representedObject = @"https://x.com/thsottiaux";
    // 只有「Tibo」这个词黑体粗，其余常规（2026-11-01 刚哥指定：看好，就粗 Tibo 一个词）
    {
        NSString *tiboTitle = tibo.title;
        NSMutableAttributedString *ta = [[NSMutableAttributedString alloc]
            initWithString:tiboTitle
                attributes:@{NSFontAttributeName: [NSFont menuFontOfSize:[NSFont systemFontSize]]}];
        NSRange r = [tiboTitle rangeOfString:@"Tibo"];
        if (r.location != NSNotFound)
            [ta addAttribute:NSFontAttributeName
                       value:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]
                       range:r];
        tibo.attributedTitle = ta;
    }
    [self.menu addItem:tibo];
    [self.menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *fastCom = [[NSMenuItem alloc] initWithTitle:@"测试网速" action:@selector(openFastCom:) keyEquivalent:@""];
    fastCom.target = self;
    [self.menu addItem:fastCom];

    NSMenuItem *openCodex = [[NSMenuItem alloc] initWithTitle:@"打开 Codex" action:@selector(openCodex:) keyEquivalent:@""];
    openCodex.target = self;
    [self.menu addItem:openCodex];

    // ---- 完成提示音：绿变红时「叮」一声，可开关、可换音 ----
    NSMenuItem *soundRoot = [[NSMenuItem alloc] initWithTitle:@"更换提示音" action:nil keyEquivalent:@""];
    NSMenu *soundMenu = [[NSMenu alloc] initWithTitle:@"更换提示音"];

    self.soundToggleItem = [[NSMenuItem alloc] initWithTitle:@"提示音：开启"
                                                      action:@selector(toggleSound:)
                                               keyEquivalent:@""];
    self.soundToggleItem.target = self;
    [soundMenu addItem:self.soundToggleItem];
    [soundMenu addItem:[NSMenuItem separatorItem]];

    self.soundChoiceItems = [NSMutableArray array];
    NSString *lastGroup = nil;
    for (NSDictionary<NSString *, NSString *> *s in [self availableSounds]) {
        NSString *group = s[@"group"];
        if (![group isEqualToString:lastGroup ?: @""]) {
            NSMenuItem *h = [[NSMenuItem alloc] initWithTitle:group action:nil keyEquivalent:@""];
            h.enabled = NO;
            [soundMenu addItem:h];
            lastGroup = group;
        }
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:s[@"name"]
                                                    action:@selector(selectSound:)
                                             keyEquivalent:@""];
        it.target = self;
        it.representedObject = s[@"path"];
        [self.soundChoiceItems addObject:it];
        [soundMenu addItem:it];
    }
    [soundMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *preview = [[NSMenuItem alloc] initWithTitle:@"试听当前提示音"
                                                     action:@selector(previewSound:)
                                              keyEquivalent:@""];
    preview.target = self;
    [soundMenu addItem:preview];

    soundRoot.submenu = soundMenu;
    [self.menu addItem:soundRoot];
    [self refreshSoundMenuItems];

    // ---- 关于（V1.6，交接单 JJ-2026-1101-01）：版本号 + 项目主页 + 问题反馈 ----
    // 目的：应用内留出处。用户看到新版本 → 点链接去 Releases 下载 → 形成升级闭环。
    NSMenuItem *aboutRoot = [[NSMenuItem alloc] initWithTitle:@"关于 Codex小灯" action:nil keyEquivalent:@""];
    NSMenu *aboutMenu = [[NSMenu alloc] initWithTitle:@"关于 Codex小灯"];

    // 版本行：纯显示，不可点（刚哥定的视觉分层——灰＝只读信息，亮白＝可点按钮）
    NSMenuItem *verItem = [[NSMenuItem alloc]
        initWithTitle:[NSString stringWithFormat:@"版本 %@", kAppVersion]
               action:nil
        keyEquivalent:@""];
    verItem.enabled = NO;
    [aboutMenu addItem:verItem];

    NSMenuItem *homeItem = [[NSMenuItem alloc] initWithTitle:@"打开项目主页 ↗"
                                                      action:@selector(openAboutLink:)
                                               keyEquivalent:@""];
    homeItem.target = self;
    homeItem.representedObject = kProjectURL;
    [aboutMenu addItem:homeItem];

    NSMenuItem *issueItem = [[NSMenuItem alloc] initWithTitle:@"问题反馈 ↗"
                                                       action:@selector(openAboutLink:)
                                                keyEquivalent:@""];
    issueItem.target = self;
    issueItem.representedObject = kIssuesURL;
    [aboutMenu addItem:issueItem];

    aboutRoot.submenu = aboutMenu;
    [self.menu addItem:aboutRoot];

    // 分隔线：把「重启 / 退出」这类 app 操作和上面的功能项隔开（2026-10-26 刚哥指定，与 WB小灯 一致）
    [self.menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *restart = [[NSMenuItem alloc] initWithTitle:@"重启 Codex 小灯" action:@selector(restartApp:) keyEquivalent:@""];
    restart.target = self;
    // V1.4：左侧配「循环箭头」图标（与 WB小灯 同款同尺寸），和「退出」的图标位对齐（2026-10-27 刚哥指定）
    NSImage *restartSym = [NSImage imageWithSystemSymbolName:@"arrow.triangle.2.circlepath"
                                      accessibilityDescription:@"重启"];
    if (restartSym) {
        restart.image = [restartSym imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium]];
    }
    [self.menu addItem:restart];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出 Codex小灯" action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    // V1.4：退出配「方框叉」图标（xmark.square），与重启同一尺寸（2026-10-27 刚哥指定）
    NSImage *quitSym = [NSImage imageWithSystemSymbolName:@"xmark.square"
                                   accessibilityDescription:@"退出"];
    if (quitSym) {
        quit.image = [quitSym imageWithSymbolConfiguration:
            [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium]];
    }
    [self.menu addItem:quit];

    self.item.menu = self.menu;

    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:kPollInterval target:self selector:@selector(updateState) userInfo:nil repeats:YES];
    [self updateState];
    [self startUsageTimer];
}

- (NSMenuItem *)fieldItemWithTitle:(NSString *)title assign:(void (^)(NSTextField *field))assign {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    // 外层容器负责留白：左侧 16pt（与原生菜单文字对齐）、右侧 12pt；整体比旧版 300pt 窄
    NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 314, 24)];   // V1.1：与 WB小灯 菜单同宽 314（刚哥定：按宽的统一）
    NSTextField *field = [NSTextField labelWithString:title];
    field.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    field.lineBreakMode = NSLineBreakByTruncatingTail;      // 任务名过长截断，不再硬裁半截字
    field.frame = NSMakeRect(16, 4, 314 - 16 - 14, 17);
    [box addSubview:field];
    item.view = box;
    assign(field);
    return item;
}

- (NSArray<NSString *> *)recentSessionFiles {
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@".codex/sessions"];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:root];
    for (NSString *relative in enumerator) {
        if ([relative.pathExtension isEqualToString:@"jsonl"]) {
            [files addObject:[root stringByAppendingPathComponent:relative]];
        }
    }
    [files sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSDictionary *aa = [[NSFileManager defaultManager] attributesOfItemAtPath:a error:nil];
        NSDictionary *bb = [[NSFileManager defaultManager] attributesOfItemAtPath:b error:nil];
        NSDate *da = aa[NSFileModificationDate];
        NSDate *db = bb[NSFileModificationDate];
        return [db compare:da];
    }];
    if (files.count > 12) {
        return [files subarrayWithRange:NSMakeRange(0, 12)];
    }
    return files;
}

- (void)updateState {
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSTimeInterval latest = 0;
    NSString *latestPath = nil;

    for (NSString *path in [self recentSessionFiles]) {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        NSDate *date = attrs[NSFileModificationDate];
        NSTimeInterval t = date.timeIntervalSince1970;
        if (t > latest) {
            latest = t;
            latestPath = path;
        }
    }

    self.lastActivity = latest;
    self.lastSessionPath = latestPath ?: @"";
    BOOL wasBusy = self.busy;
    BOOL sessionBusy = [self sessionAppearsBusy:self.lastSessionPath now:now];
    self.busy = sessionBusy;

    if (self.busy && !wasBusy) { [self startBlink]; self.busySince = now; }   // V1.3：记下"这次忙了多久"
    if (!self.busy) {
        [self stopBlink];
        self.blinkOn = YES;
        self.busySince = 0;
    }
    if (wasBusy && !self.busy) [self playCompletionSound];   // 绿 → 红：活干完了，叮一声
    [self updateBreathTimer];   // 0% → 黄色呼吸开；回到有量 → 关（挂巡检，比只挂拉取那一刻稳）
    [self renderStatusTitle];

    [self updateCurrentTitleAndAction];

    [self renderDetailLine];   // V1.3：状态行「工作中 · 已忙 X 分 X 秒」，每秒刷新

    self.taskField.stringValue = [NSString stringWithFormat:@"当前任务：%@", self.currentTitle ?: @"未检测"];
}

- (BOOL)sessionAppearsBusy:(NSString *)path now:(NSTimeInterval)now {
    if (!path.length) return NO;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSDate *date = attrs[NSFileModificationDate];
    if (!date) {
        self.stateReason = @"无日志文件";
        return NO;
    }
    NSTimeInterval fileAge = now - date.timeIntervalSince1970;
    if (fileAge > kStaleBusyWindow) {
        self.stateReason = [NSString stringWithFormat:@"日志 %.0f 秒未更新，按闲置", fileAge];
        return NO;
    }

    NSString *state = [self latestSubstantiveStateFrom:path];
    if ([state isEqualToString:@"idle"]) return NO;
    if ([state isEqualToString:@"busy"]) return YES;

    // If the tail cannot be parsed, fall back to a very short write window, not the old 45 seconds.
    return now - date.timeIntervalSince1970 < 3.0;
}

- (NSString *)latestSubstantiveStateFrom:(NSString *)path {
    NSArray<NSDictionary *> *events = [self tailEventObjectsFrom:path bytes:524288];
    NSString *latestTurn = nil;
    for (NSDictionary *obj in [events reverseObjectEnumerator]) {
        latestTurn = [self turnIDForEvent:obj];
        if (latestTurn.length) break;
    }

    if (latestTurn.length) {
        BOOL hasFinal = NO;
        BOOL hasTaskComplete = NO;
        BOOL hasBusySignal = NO;
        NSString *lastKnownReason = @"最新回合无明确事件";
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        NSTimeInterval lastTurnAge = 999999.0;
        for (NSDictionary *obj in events) {
            NSString *turnID = [self turnIDForEvent:obj];
            if (![turnID isEqualToString:latestTurn]) continue;
            lastTurnAge = [self ageOfEvent:obj now:now];

            NSString *type = obj[@"type"];
            NSDictionary *payload = [obj[@"payload"] isKindOfClass:NSDictionary.class] ? obj[@"payload"] : nil;
            NSString *ptype = payload[@"type"];
            NSString *phase = payload[@"phase"];

            if ([type isEqualToString:@"response_item"]) {
                if ([ptype isEqualToString:@"function_call"] || [ptype isEqualToString:@"reasoning"]) {
                    hasBusySignal = YES;
                    lastKnownReason = [NSString stringWithFormat:@"最新回合 %@", ptype];
                }
                if ([ptype isEqualToString:@"message"]) {
                    NSString *role = payload[@"role"];
                    if ([role isEqualToString:@"user"]) {
                        hasBusySignal = YES;
                        lastKnownReason = @"最新回合收到用户消息";
                    }
                    if ([role isEqualToString:@"assistant"] && [self isFinalPhase:phase]) {
                        hasFinal = YES;
                        lastKnownReason = [NSString stringWithFormat:@"最新回合 assistant %@", phase];
                    }
                }
            }

            if ([type isEqualToString:@"event_msg"]) {
                NSString *etype = payload[@"type"];
                if ([etype isEqualToString:@"task_complete"]) {
                    hasTaskComplete = YES;
                    lastKnownReason = @"最新回合 task_complete";
                }
                NSDictionary *item = [payload[@"item"] isKindOfClass:NSDictionary.class] ? payload[@"item"] : nil;
                NSString *itemType = item[@"type"];
                NSString *itemPhase = item[@"phase"];
                if ([itemType isEqualToString:@"UserMessage"] ||
                    [itemType isEqualToString:@"CommandExecution"] ||
                    [itemType isEqualToString:@"Reasoning"]) {
                    hasBusySignal = YES;
                    lastKnownReason = [NSString stringWithFormat:@"最新回合 %@", itemType];
                }
                if ([itemType isEqualToString:@"AgentMessage"] && [self isFinalPhase:itemPhase]) {
                    hasFinal = YES;
                    lastKnownReason = [NSString stringWithFormat:@"最新回合 AgentMessage %@", itemPhase];
                }
            }
        }
        if (hasTaskComplete || hasFinal) {
            self.stateReason = lastKnownReason;
            return @"idle";
        }
        if (hasBusySignal && lastTurnAge > kUnfinishedTurnTimeout) {
            self.stateReason = [NSString stringWithFormat:@"最新回合 %.0f 秒无明确完成，兜底停闪", lastTurnAge];
            return @"idle";
        }
        if (hasBusySignal) {
            self.stateReason = lastKnownReason;
            return @"busy";
        }
    }

    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    for (NSDictionary *obj in [events reverseObjectEnumerator]) {
        NSString *type = obj[@"type"];
        NSDictionary *payload = [obj[@"payload"] isKindOfClass:NSDictionary.class] ? obj[@"payload"] : nil;
        NSString *ptype = payload[@"type"];
        NSString *phase = payload[@"phase"];

        if ([type isEqualToString:@"response_item"]) {
            if ([ptype isEqualToString:@"function_call"] || [ptype isEqualToString:@"reasoning"]) {
                self.stateReason = [NSString stringWithFormat:@"尾部 %@", ptype];
                return @"busy";
            }
            if ([ptype isEqualToString:@"message"]) {
                NSString *role = payload[@"role"];
                if ([role isEqualToString:@"user"]) {
                    self.stateReason = @"尾部 user message";
                    return @"busy";
                }
                if ([role isEqualToString:@"assistant"]) {
                    self.stateReason = [NSString stringWithFormat:@"尾部 assistant %@", phase ?: @""];
                    return [self isFinalPhase:phase] ? @"idle" : @"busy";
                }
            }
        }

        if ([type isEqualToString:@"event_msg"]) {
            NSString *etype = payload[@"type"];
            if ([etype isEqualToString:@"token_count"]) continue;
            if ([etype isEqualToString:@"task_complete"]) {
                self.stateReason = @"尾部 task_complete";
                return @"idle";
            }
            if ([etype isEqualToString:@"item_completed"]) {
                NSDictionary *item = [payload[@"item"] isKindOfClass:NSDictionary.class] ? payload[@"item"] : nil;
                NSString *itemType = item[@"type"];
                NSString *itemPhase = item[@"phase"];
                if ([itemType isEqualToString:@"AgentMessage"]) {
                    self.stateReason = [NSString stringWithFormat:@"尾部 AgentMessage %@", itemPhase ?: @""];
                    return [self isFinalPhase:itemPhase] ? @"idle" : @"busy";
                }
                if ([itemType isEqualToString:@"CommandExecution"] || [itemType isEqualToString:@"Reasoning"]) {
                    NSString *status = item[@"status"];
                    NSTimeInterval age = [self ageOfEvent:obj now:now];
                    self.stateReason = [NSString stringWithFormat:@"尾部 %@ %@ %.0f 秒", itemType, status ?: @"", age];
                    if ([status isEqualToString:@"completed"] && age > 3.0) return @"idle";
                    return @"busy";
                }
            }
        }
    }
    return @"unknown";
}

- (BOOL)isFinalPhase:(NSString *)phase {
    return [phase isEqualToString:@"final"] || [phase isEqualToString:@"final_answer"];
}

- (NSString *)turnIDForEvent:(NSDictionary *)event {
    NSDictionary *payload = [event[@"payload"] isKindOfClass:NSDictionary.class] ? event[@"payload"] : nil;
    NSString *turnID = payload[@"turn_id"];
    if (turnID.length) return turnID;
    NSDictionary *meta = [payload[@"internal_chat_message_metadata_passthrough"] isKindOfClass:NSDictionary.class]
        ? payload[@"internal_chat_message_metadata_passthrough"]
        : nil;
    turnID = meta[@"turn_id"];
    return turnID.length ? turnID : @"";
}

- (NSTimeInterval)ageOfEvent:(NSDictionary *)event now:(NSTimeInterval)now {
    NSString *timestamp = event[@"timestamp"];
    if (!timestamp.length) return 999999.0;
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    NSDate *date = [fmt dateFromString:timestamp];
    if (!date) {
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        date = [fmt dateFromString:timestamp];
    }
    if (!date) return 999999.0;
    return MAX(0, now - date.timeIntervalSince1970);
}

// ================= 完成提示音（绿变红时「叮」一声）=================

- (NSUserDefaults *)soundPrefs {
    // V1.5 真修（2026-10-28 与 WB小灯 V2.6 同源同病）：
    // app 的 Bundle ID 就叫 local.codex.light，再用同名的 initWithSuiteName 会被系统忽略
    // （"own bundle identifier as suite name does not work"）→ 返回的实例不落盘，换完音重启就丢。
    // 改用 standardUserDefaults（写 ~/Library/Preferences/local.codex.light.plist），两个 app 天然隔离。
    return [NSUserDefaults standardUserDefaults];
}

- (void)loadSoundPrefs {
    NSUserDefaults *d = [self soundPrefs];
    self.soundEnabled = ([d objectForKey:@"SoundEnabled"] == nil) ? YES : [d boolForKey:@"SoundEnabled"];
    NSString *p = [d stringForKey:@"SoundPath"];
    self.soundPath = p.length ? p : [self defaultSoundPath];
}

- (void)saveSoundPrefs {
    NSUserDefaults *d = [self soundPrefs];
    [d setBool:self.soundEnabled forKey:@"SoundEnabled"];
    [d setObject:(self.soundPath ?: @"") forKey:@"SoundPath"];
    [d synchronize];   // V1.3：立刻落盘，别等系统的异步 flush
}

- (NSString *)defaultSoundPath {
    // 默认就是那声「叮」；万一系统里没有，退回列表第一个
    NSString *tink = @"/System/Library/Sounds/Tink.aiff";
    if ([[NSFileManager defaultManager] fileExistsAtPath:tink]) return tink;
    NSDictionary<NSString *, NSString *> *first = [self availableSounds].firstObject;
    return first[@"path"] ?: @"";
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)availableSounds {
    NSArray<NSArray<NSString *> *> *dirs = @[
        @[@"系统提示音", @"/System/Library/Sounds"],
        @[@"其他提示音", @"/Library/Sounds"],
        @[@"自定义（~/Library/Sounds）", [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Sounds"]],
    ];
    NSArray<NSString *> *exts = @[@"aiff", @"aif", @"wav", @"caf", @"m4a", @"mp3"];
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSArray<NSString *> *pair in dirs) {
        NSString *group = pair[0];
        NSString *dir = pair[1];
        NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *n in [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
            if ([n hasPrefix:@"."]) continue;
            if (![exts containsObject:n.pathExtension.lowercaseString]) continue;
            NSString *base = n.stringByDeletingPathExtension;
            if ([seen containsObject:base]) continue;      // 同名只留第一个（系统音优先）
            [seen addObject:base];
            [out addObject:@{@"name": base,
                             @"path": [dir stringByAppendingPathComponent:n],
                             @"group": group}];
        }
    }
    return out;
}

- (void)refreshSoundMenuItems {
    self.soundToggleItem.title = self.soundEnabled ? @"提示音：开启（点一下关闭）"
                                                   : @"提示音：关闭（点一下开启）";
    self.soundToggleItem.state = self.soundEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    NSString *cur = self.soundPath ?: @"";
    for (NSMenuItem *it in self.soundChoiceItems) {
        id rep = it.representedObject;
        NSString *p = [rep isKindOfClass:[NSString class]] ? rep : @"";
        it.state = [p isEqualToString:cur] ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)playCompletionSound {
    if (!self.soundEnabled || !self.soundPath.length) return;
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.soundPath]) return;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (self.lastSoundAt > 0 && now - self.lastSoundAt < kMinSoundGap) return;  // 防抖，避免连响
    self.lastSoundAt = now;
    NSSound *s = [[NSSound alloc] initWithContentsOfFile:self.soundPath byReference:YES];
    if (!s) return;
    self.player = s;              // 必须持有，否则声音会被提前释放（只响半声或干脆不响）
    [s play];
}

- (void)toggleSound:(id)sender {
    self.soundEnabled = !self.soundEnabled;
    [self saveSoundPrefs];
    [self refreshSoundMenuItems];
    if (self.soundEnabled) {
        self.lastSoundAt = 0;     // 开启时立刻响一声，马上知道听不听得到
        [self playCompletionSound];
    }
}

- (void)selectSound:(id)sender {
    if (![sender isKindOfClass:[NSMenuItem class]]) return;
    id rep = [(NSMenuItem *)sender representedObject];
    if (![rep isKindOfClass:[NSString class]] || ![(NSString *)rep length]) return;
    self.soundPath = rep;
    self.soundEnabled = YES;       // 选了音就等于要开，符合直觉
    [self saveSoundPrefs];
    [self refreshSoundMenuItems];
    self.lastSoundAt = 0;
    [self playCompletionSound];    // 点一下即试听
}

- (void)previewSound:(id)sender {
    BOOL keep = self.soundEnabled;
    self.soundEnabled = YES;
    self.lastSoundAt = 0;
    [self playCompletionSound];
    self.soundEnabled = keep;
}

// ================= Codex 真实用量（5 小时窗口 / 本周）=================
// 数据源：GET https://chatgpt.com/backend-api/wham/usage
// 凭据：只读 ~/.codex/auth.json（不改写，避免影响 Codex 自身登录态）

- (void)startUsageTimer {
    [self fetchUsage];
    // 60 秒一拉：这个接口是「我主动拉取」不是推送，分钟级变化（14 分 → 13 分）一分钟一次刚好
    self.usageTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
                                                       target:self
                                                     selector:@selector(fetchUsage)
                                                     userInfo:nil
                                                      repeats:YES];
    self.usageTimer.tolerance = 5.0;
    // V1.6：充值卡信息变化很慢（发卡/用掉才变），10 分钟查一次就够，不跟着 60 秒的用量刷新一起刷
    [self fetchResetCredits];
    self.cardTimer = [NSTimer scheduledTimerWithTimeInterval:600.0
                                                      target:self
                                                    selector:@selector(fetchResetCredits)
                                                    userInfo:nil
                                                     repeats:YES];
    self.cardTimer.tolerance = 30.0;
}

// ============ V1.6：充值卡（rate-limit reset credits）============
// 数据源：GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits
// 返回：{ credits:[{status, expires_at, ...}], available_count, ... }
// 只显示「几张 + 最近那张的到期日」，不展开明细（菜单宽度有限）
- (void)fetchResetCredits {
    if (self.cardFetching) return;
    self.cardFetching = YES;

    NSString *authPath = [NSHomeDirectory() stringByAppendingPathComponent:@".codex/auth.json"];
    NSData *data = [NSData dataWithContentsOfFile:authPath];
    NSDictionary *auth = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *tokens = [auth[@"tokens"] isKindOfClass:NSDictionary.class] ? auth[@"tokens"] : nil;
    NSString *token = tokens[@"access_token"];
    NSString *account = tokens[@"account_id"];
    if (!token.length) {
        self.cardFetching = NO;
        [self setCardLine:@"充值卡：未登录"];
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"]];
    req.timeoutInterval = 15.0;
    [req setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    if (account.length) [req setValue:account forHTTPHeaderField:@"chatgpt-account-id"];
    [req setValue:@"codex-cli/0.163.0" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *body, NSURLResponse *resp, NSError *err) {
            NSInteger code = [resp isKindOfClass:NSHTTPURLResponse.class]
                ? [(NSHTTPURLResponse *)resp statusCode] : 0;
            NSDictionary *json = body.length
                ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                self.cardFetching = NO;
                if (code == 200 && [json isKindOfClass:NSDictionary.class]) {
                    [self applyResetCredits:json];
                } else if (!self.lastCardLine) {
                    // 首次失败：如实说拿不到，不编「0 张」吓人
                    [self setCardLine:@"充值卡：暂不可用"];
                }
                // 已有真实数据后网络失败：保留上次结果
            });
        }];
    [task resume];
}

- (void)applyResetCredits:(NSDictionary *)json {
    NSArray *credits = [json[@"credits"] isKindOfClass:NSArray.class] ? json[@"credits"] : nil;
    NSInteger count = [json[@"available_count"] integerValue];
    // 只认手上还有效的（status=available），取最早到期的那张显示日期
    NSDate *soonest = nil;
    NSInteger availableInList = 0;
    for (id obj in credits) {
        if (![obj isKindOfClass:NSDictionary.class]) continue;
        NSString *st = obj[@"status"];
        if ([st isKindOfClass:NSString.class] && st.length && ![st isEqualToString:@"available"]) continue;
        availableInList++;
        NSDate *d = [self dateFromISO:obj[@"expires_at"]];
        if (d && (!soonest || [d compare:soonest] == NSOrderedAscending)) soonest = d;
    }
    NSInteger shown = count > 0 ? count : availableInList;
    if (shown <= 0) { [self setCardLine:@"充值卡 0 张"]; return; }
    if (!soonest) { [self setCardLine:[NSString stringWithFormat:@"充值卡 %ld 张", (long)shown]]; return; }
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.timeZone = [NSTimeZone localTimeZone];   // 到期时间按本机时区显示（接口给的是 UTC）
    fmt.dateFormat = @"M月d日 HH:mm";
    [self setCardLine:[NSString stringWithFormat:@"充值卡 %ld 张 · 到期 %@（北京）",
                       (long)shown, [fmt stringFromDate:soonest]]];
}

// ISO8601（可能带毫秒和 Z）→ NSDate；解析不了返回 nil，绝不硬编日期
- (NSDate *)dateFromISO:(id)value {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *s = (NSString *)value;
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";
    if (s.length > 19) s = [s substringToIndex:19];   // 砍掉 .453783Z
    return [f dateFromString:s];
}

- (void)setCardLine:(NSString *)line {
    self.lastCardLine = line;
    [self renderUsageLines];
    if (getenv("CODEX_LIGHT_DEBUG")) NSLog(@"[credits] %@", line);
}

- (void)fetchUsage {
    if (self.usageFetching) return;
    self.usageFetching = YES;

    NSString *authPath = [NSHomeDirectory() stringByAppendingPathComponent:@".codex/auth.json"];
    NSData *data = [NSData dataWithContentsOfFile:authPath];
    NSDictionary *auth = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *tokens = [auth[@"tokens"] isKindOfClass:NSDictionary.class] ? auth[@"tokens"] : nil;
    NSString *token = tokens[@"access_token"];
    NSString *account = tokens[@"account_id"];
    if (!token.length) {
        self.usageFetching = NO;
        [self setUsageLine:@"用量：未登录 Codex" week:@"登录后自动显示"];
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://chatgpt.com/backend-api/wham/usage"]];
    req.timeoutInterval = 15.0;
    [req setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    if (account.length) [req setValue:account forHTTPHeaderField:@"chatgpt-account-id"];
    [req setValue:@"codex-cli/0.163.0" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *body, NSURLResponse *resp, NSError *err) {
            NSInteger code = [resp isKindOfClass:NSHTTPURLResponse.class]
                ? [(NSHTTPURLResponse *)resp statusCode] : 0;
            NSDictionary *json = body.length
                ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                self.usageFetching = NO;
                if (code == 200 && [json isKindOfClass:NSDictionary.class]) {
                    [self applyUsage:json];
                } else if (code == 401) {
                    [self setUsageLine:@"用量：登录已过期" week:@"打开 Codex 刷新后自动恢复"];
                } else if (self.usageFetchedAt <= 0) {
                    // 首次就失败：如实说不可用，不编数字
                    [self setUsageLine:@"用量：暂不可用" week:@"网络恢复后自动重试"];
                }
                // 已有真实数据时网络失败：保留上次结果，不显示假 0
            });
        }];
    [task resume];
}

- (void)applyUsage:(NSDictionary *)json {
    NSDictionary *rl = [json[@"rate_limit"] isKindOfClass:NSDictionary.class] ? json[@"rate_limit"] : nil;
    NSDictionary *primary = [rl[@"primary_window"] isKindOfClass:NSDictionary.class] ? rl[@"primary_window"] : nil;
    NSDictionary *secondary = [rl[@"secondary_window"] isKindOfClass:NSDictionary.class] ? rl[@"secondary_window"] : nil;

    NSString *five = @"5小时剩余：--";
    NSString *week = @"本周剩余：--";
    if (primary) {
        NSInteger used = [primary[@"used_percent"] integerValue];
        NSInteger left = MAX(0, MIN(100, 100 - used));
        self.fiveHourLeft = left;   // 同步到菜单栏 C 旁边（renderStatusTitle 读取）
        self.fiveHourReset = [self resetClockFrom:primary];   // 重置时间点，如 22:00
        five = [NSString stringWithFormat:@"5小时剩余：%ld%% · %@",
                (long)left, [self formatResetAfter:primary[@"reset_after_seconds"]]];
    }
    if (secondary) {
        NSInteger used = [secondary[@"used_percent"] integerValue];
        NSInteger left = MAX(0, MIN(100, 100 - used));
        self.weekLeft = left;   // 同步到菜单栏 C 旁边
        week = [NSString stringWithFormat:@"本周剩余：%ld%% · %@",
                (long)left, [self formatResetAfter:secondary[@"reset_after_seconds"]]];
    }
    self.usageFetchedAt = [NSDate date].timeIntervalSince1970;
    [self setUsageLine:five week:week];
}

// 5 小时窗口的重置时间点，换算成本地时钟 HH:mm；取不到就退回「当前时间 + 剩余秒数」
- (NSString *)resetClockFrom:(NSDictionary *)window {
    NSNumber *resetAt = [window[@"reset_at"] isKindOfClass:NSNumber.class] ? window[@"reset_at"] : nil;
    NSNumber *after = [window[@"reset_after_seconds"] isKindOfClass:NSNumber.class] ? window[@"reset_after_seconds"] : nil;
    NSDate *date = nil;
    if (resetAt && resetAt.doubleValue > 0) {
        date = [NSDate dateWithTimeIntervalSince1970:resetAt.doubleValue];
    } else if (after) {
        date = [NSDate dateWithTimeIntervalSinceNow:after.doubleValue];
    }
    if (!date) return @"";
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.timeZone = [NSTimeZone localTimeZone];
    fmt.dateFormat = @"HH:mm";
    return [fmt stringFromDate:date];
}

- (NSString *)formatResetAfter:(NSNumber *)secs {
    NSInteger s = [secs isKindOfClass:NSNumber.class] ? secs.integerValue : 0;
    if (s <= 0) return @"即将重置";
    if (s >= 86400) return [NSString stringWithFormat:@"%ld 天 %ld 小时后重置", (long)(s / 86400), (long)((s % 86400) / 3600)];
    if (s >= 3600) return [NSString stringWithFormat:@"%ld 小时 %ld 分后重置", (long)(s / 3600), (long)((s % 3600) / 60)];
    return [NSString stringWithFormat:@"%ld 分钟后重置", (long)MAX(1, (s + 59) / 60)];
}

- (void)setUsageLine:(NSString *)five week:(NSString *)week {
    self.lastFiveLine = five;
    self.lastWeekLine = week;
    [self renderUsageLines];
    if (getenv("CODEX_LIGHT_DEBUG")) NSLog(@"[usage] %@ | %@", five, week);
}

// 菜单用量两行：百分比染色；5 小时行在 0% 时黄色呼吸（与菜单栏 C 同一个呼吸帧）
// 文案还没生成（启动头几秒）时直接跳过，不能拿 nil 建 attributed string
- (void)renderUsageLines {
    // 2026-11-01 刚哥定：非按钮行不用亮白，文字底色统一次级灰（数字仍绿 / 0% 黄呼吸）
    if (self.lastFiveLine) [self renderUsageField:self.usageFiveField text:self.lastFiveLine
                                        baseColor:[NSColor secondaryLabelColor] breathing:(self.fiveHourLeft == 0)];
    if (self.lastWeekLine) [self renderUsageField:self.usageWeekField text:self.lastWeekLine
                                        baseColor:[NSColor secondaryLabelColor] breathing:NO];   // 本周不参与呼吸
    // V1.6：充值卡行（文案里没有 %，走专门的渲染：张数染绿加粗）
    if (self.lastCardLine) [self renderCardLine];
}

// V1.6（2026-11-01 刚哥指定）：充值卡行的张数数字绿色加粗，其余文字次级灰。
// 这行没有「%」，所以不能用按 % 找数字的通用逻辑，改成按「张」字往前找数字。
- (void)renderCardLine {
    NSString *text = self.lastCardLine;
    NSTextField *field = self.usageCardField;
    if (!text || !field || !field.font) return;
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:text
        attributes:@{NSFontAttributeName: field.font, NSForegroundColorAttributeName: [NSColor secondaryLabelColor]}];
    NSRange zhang = [text rangeOfString:@"张"];
    if (zhang.location != NSNotFound) {
        // 文案是「充值卡 1 张」——数字和「张」之间有空格，先跳过空格再往前吃数字
        NSUInteger end = zhang.location;
        while (end > 0 && [text characterAtIndex:end - 1] == ' ') end--;
        NSUInteger start = end;
        while (start > 0) {
            unichar c = [text characterAtIndex:start - 1];
            if (c >= '0' && c <= '9') start--; else break;
        }
        if (start < end) {
            NSRange numberRange = NSMakeRange(start, end - start);
            [a addAttribute:NSForegroundColorAttributeName value:[NSColor systemGreenColor] range:numberRange];
            // 加粗：与行内其余文字同字号（12）但用 Bold，不放大免得撑宽菜单
            [a addAttribute:NSFontAttributeName
                      value:[NSFont systemFontOfSize:field.font.pointSize weight:NSFontWeightBold]
                      range:numberRange];
        }
    }
    field.attributedStringValue = a;
}

// 只把百分比数字（含 %）染色：平时绿色；breathing=YES（5小时=0%）时黄色并按呼吸亮度忽明忽暗，
// 其余文字保持原来的黑白层级（2026-10-26 刚哥指定：菜单里的 0% 也要呼吸）
- (void)renderUsageField:(NSTextField *)field text:(NSString *)text baseColor:(NSColor *)baseColor breathing:(BOOL)breath {
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:text
        attributes:@{NSFontAttributeName: field.font, NSForegroundColorAttributeName: baseColor}];
    NSRange pct = [text rangeOfString:@"%"];
    if (pct.location != NSNotFound) {
        NSUInteger start = pct.location;
        while (start > 0) {
            unichar c = [text characterAtIndex:start - 1];
            if (c >= '0' && c <= '9') start--; else break;
        }
        NSRange numberRange = NSMakeRange(start, pct.location - start + 1);
        NSColor *numColor = [NSColor systemGreenColor];
        if (breath) numColor = [[NSColor systemYellowColor] colorWithAlphaComponent:[self breathAlpha]];
        [a addAttribute:NSForegroundColorAttributeName value:numColor range:numberRange];
    }
    field.attributedStringValue = a;
}

- (void)startBlink {
    if (self.blinkTimer) return;
    self.blinkTimer = [NSTimer timerWithTimeInterval:kBlinkInterval target:self selector:@selector(tickBlink) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.blinkTimer forMode:NSRunLoopCommonModes];
}

- (void)stopBlink {
    [self.blinkTimer invalidate];
    self.blinkTimer = nil;
}

- (void)tickBlink {
    self.blinkOn = !self.blinkOn;
    [self renderStatusTitle];
    // V1.1：状态词不闪了，不用跟着闪烁帧重画这一行
}

// ===== 5小时额度耗尽（0%）→ 黄色呼吸（2026-10-25 刚哥定） =====
// 只作用于菜单栏的「0%」两个字：黄色、alpha 按余弦 0.25↔1.0 缓慢往复（周期 2.6s），
// 与忙闲绿闪（0.55s 硬切）完全独立；重置时间点和 /本周% 不参与。

// 0% 才需要呼吸；有量了就停掉并恢复常亮
- (void)updateBreathTimer {
    BOOL need = (self.fiveHourLeft == 0);
    if (need && !self.breathTimer) {
        self.breathStart = CFAbsoluteTimeGetCurrent();
        self.breathTimer = [NSTimer timerWithTimeInterval:kBreathTick target:self
                                                 selector:@selector(tickBreath) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.breathTimer forMode:NSRunLoopCommonModes];
    } else if (!need && self.breathTimer) {
        [self.breathTimer invalidate];
        self.breathTimer = nil;
        [self renderStatusTitle];   // 停呼吸后立刻按常亮色重画，不留暗帧
    }
}

- (void)tickBreath {
    [self renderStatusTitle];   // renderStatusTitle 内部读 breathAlpha，0% 时每帧重画
    [self renderUsageLines];    // 菜单里「5小时剩余：0%」的黄字同步呼吸（2026-10-26 刚哥指定）
}

// 当前呼吸亮度：cos 从 1 → -1 → 1，映射到 0.25 ~ 1.0，起止都是全亮，明暗过渡平滑
- (CGFloat)breathAlpha {
    if (!self.breathTimer) return 1.0;
    CGFloat t = fmod(CFAbsoluteTimeGetCurrent() - self.breathStart, kBreathPeriod) / kBreathPeriod;
    return 0.25 + 0.75 * (0.5 - 0.5 * cos(2.0 * M_PI * t));
}

// 状态行：V1.3（2026-10-27 刚哥定）——参考 WB小灯 面板：忙时「工作中 · 已忙 X 分 X 秒」
// （文字白、只有时长的两个数字绿），闲时「闲置中」；原「最近活动：…前」整行废弃（前后台都去掉）
- (void)renderDetailLine {
    if (!self.busy) {
        self.detailField.attributedStringValue = [[NSAttributedString alloc]
            initWithString:@"闲置中"
                attributes:@{NSFontAttributeName: self.detailField.font,
                             NSForegroundColorAttributeName: [NSColor secondaryLabelColor]}];
        return;
    }
    NSTimeInterval secs = [NSDate date].timeIntervalSince1970 - self.busySince;
    long mins = (long)floor(secs / 60), ss = (long)fmod(secs, 60);
    NSString *pre = @"工作中 · 已忙 ", *m1 = @" 分 ", *m2 = @" 秒";
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"%@%ld%@%ld%@", pre, mins, m1, ss, m2]
            attributes:@{NSFontAttributeName: self.detailField.font,
                         NSForegroundColorAttributeName: [NSColor secondaryLabelColor]}];
    NSString *ms = [NSString stringWithFormat:@"%ld", mins], *xs = [NSString stringWithFormat:@"%ld", ss];
    [a addAttribute:NSForegroundColorAttributeName value:[NSColor systemGreenColor]
              range:NSMakeRange(pre.length, ms.length)];
    [a addAttribute:NSForegroundColorAttributeName value:[NSColor systemGreenColor]
              range:NSMakeRange(pre.length + ms.length + m1.length, xs.length)];
    self.detailField.attributedStringValue = a;
}

- (void)renderStatusTitle {
    NSColor *base = self.busy ? [NSColor colorWithCalibratedRed:0.24 green:0.95 blue:0.42 alpha:1.0]
                              : [NSColor colorWithCalibratedRed:1.0 green:0.28 blue:0.24 alpha:1.0];
    NSColor *color = (self.busy && !self.blinkOn) ? [base colorWithAlphaComponent:0.22] : base;
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:@"C"];
    NSRange all = NSMakeRange(0, title.length);
    [title addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:15 weight:NSFontWeightHeavy] range:all];
    [title addAttribute:NSForegroundColorAttributeName value:color range:all];
    // C 旁边挂剩余额度：`C 46% 22:00 / 80%` ——
    // 5小时剩余 + 它的重置时间点（本地时钟），斜杠后=本周剩余；
    // 各自独立染色：≥10% 绿、<10% 红；0% 黄色呼吸；百分比本身不随忙闲闪（2026-10-22/25 刚哥定）
    NSFont *pctFont = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    if (self.fiveHourLeft >= 0) {
        NSColor *fiveColor = self.fiveHourLeft < 10
            ? [NSColor colorWithCalibratedRed:1.0 green:0.30 blue:0.28 alpha:1.0]
            : [NSColor colorWithCalibratedRed:0.30 green:0.95 blue:0.45 alpha:1.0];
        // 5小时额度耗尽（0%）特例：百分比染成黄色并按呼吸亮度忽明忽暗（updateBreathTimer 驱动）；
        // 重置时间点仍保持红色常亮，不受呼吸影响（2026-10-25 刚哥定）
        NSColor *pctColor = fiveColor;
        if (self.fiveHourLeft == 0)
            pctColor = [[NSColor systemYellowColor] colorWithAlphaComponent:[self breathAlpha]];
        NSString *pct = [NSString stringWithFormat:@" %ld%%", (long)self.fiveHourLeft];
        NSRange r1 = NSMakeRange(title.length, pct.length);
        [title appendAttributedString:[[NSAttributedString alloc] initWithString:pct]];
        [title addAttribute:NSFontAttributeName value:pctFont range:r1];
        [title addAttribute:NSForegroundColorAttributeName value:pctColor range:r1];

        if (self.fiveHourReset.length) {
            NSString *reset = [NSString stringWithFormat:@" %@", self.fiveHourReset];
            NSRange r2 = NSMakeRange(title.length, reset.length);
            [title appendAttributedString:[[NSAttributedString alloc] initWithString:reset]];
            [title addAttribute:NSFontAttributeName value:pctFont range:r2];
            [title addAttribute:NSForegroundColorAttributeName value:fiveColor range:r2];
        }
    }
    if (self.weekLeft >= 0) {
        NSColor *weekColor = self.weekLeft < 10
            ? [NSColor colorWithCalibratedRed:1.0 green:0.30 blue:0.28 alpha:1.0]
            : [NSColor colorWithCalibratedRed:0.30 green:0.95 blue:0.45 alpha:1.0];
        NSString *weekPiece = [NSString stringWithFormat:@" / %ld%%", (long)self.weekLeft];
        NSRange r3 = NSMakeRange(title.length, weekPiece.length);
        [title appendAttributedString:[[NSAttributedString alloc] initWithString:weekPiece]];
        [title addAttribute:NSFontAttributeName value:pctFont range:r3];
        [title addAttribute:NSForegroundColorAttributeName value:weekColor range:r3];
    }
    self.item.button.image = nil;
    self.item.button.attributedTitle = title;
    self.item.button.toolTip = self.busy ? @"Codex 正在干活" : @"Codex 闲置";
}

- (NSString *)sessionIDFromPath:(NSString *)path {
    NSString *name = path.lastPathComponent.stringByDeletingPathExtension;
    NSRange r = [name rangeOfString:@"rollout-" options:0];
    if (r.location != NSNotFound && name.length > 44) {
        NSString *tail = [name substringFromIndex:MAX((NSUInteger)0, name.length - 36)];
        if ([tail containsString:@"-"]) return tail;
    }
    return @"";
}

- (NSArray<NSDictionary *> *)sessionIndexEntries {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".codex/session_index.jsonl"];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text.length) return @[];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSInteger start = MAX(0, (NSInteger)lines.count - 300);
    for (NSInteger i = start; i < (NSInteger)lines.count; i++) {
        NSString *line = lines[i];
        if (!line.length) continue;
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([obj isKindOfClass:NSDictionary.class]) [entries addObject:obj];
    }
    return entries;
}

- (void)updateCurrentTitleAndAction {
    NSString *sid = [self sessionIDFromPath:self.lastSessionPath ?: @""];
    self.currentTitle = sid.length ? sid : @"未检测";
    for (NSDictionary *entry in [self.sessionIndexEntries reverseObjectEnumerator]) {
        if ([entry[@"id"] isEqualToString:sid]) {
            NSString *title = entry[@"thread_name"];
            if (title.length) self.currentTitle = title;
            break;
        }
    }
    self.lastActionText = [self latestActionTextFrom:self.lastSessionPath];
}

- (NSString *)latestActionTextFrom:(NSString *)path {
    if (!path.length) return @"等待中";
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return @"等待中";
    unsigned long long size = [fh seekToEndOfFile];
    unsigned long long offset = size > 65536 ? size - 65536 : 0;
    [fh seekToFileOffset:offset];
    NSData *data = [fh readDataToEndOfFile];
    NSString *tail = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [tail componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSInteger i = (NSInteger)lines.count - 1; i >= 0; i--) {
        NSString *line = lines[i];
        if (!line.length || ![line hasPrefix:@"{"]) continue;
        NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if (![obj isKindOfClass:NSDictionary.class]) continue;
        NSString *type = obj[@"type"];
        NSDictionary *payload = [obj[@"payload"] isKindOfClass:NSDictionary.class] ? obj[@"payload"] : nil;
        NSString *ptype = payload[@"type"];
        NSString *name = payload[@"name"];
        if ([ptype isEqualToString:@"function_call"] || [type isEqualToString:@"function_call"]) {
            return name.length ? [NSString stringWithFormat:@"调用工具 %@", name] : @"调用工具";
        }
        if ([ptype isEqualToString:@"message"]) return @"正在回复 / 已回复";
        if ([type isEqualToString:@"event_msg"]) return @"状态更新";
        if ([type isEqualToString:@"response_item"]) return @"生成内容";
    }
    return @"等待中";
}

- (NSArray<NSDictionary *> *)tailEventObjectsFrom:(NSString *)path bytes:(unsigned long long)bytes {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return @[];
    unsigned long long size = [fh seekToEndOfFile];
    unsigned long long offset = size > bytes ? size - bytes : 0;
    [fh seekToFileOffset:offset];
    NSData *data = [fh readDataToEndOfFile];
    NSString *tail = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!tail.length) return @[];
    NSMutableArray<NSDictionary *> *events = [NSMutableArray array];
    NSArray<NSString *> *lines = [tail componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        if (!line.length || ![line hasPrefix:@"{"]) continue;
        NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if ([obj isKindOfClass:NSDictionary.class]) [events addObject:obj];
    }
    return events;
}

- (void)openFastCom:(id)sender {
    // fast.com：Netflix 的测速页，交给默认浏览器打开
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://fast.com"]];
}

- (void)openCodex:(id)sender {
    [[NSWorkspace sharedWorkspace] launchApplication:@"Codex"];
}

// V1.6：跳 X 上 Tibo（@thsottiaux）——Codex 额度重置消息的第一现场
- (void)openResetLink:(id)sender {
    id obj = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : nil;
    NSString *u = [obj isKindOfClass:NSString.class] ? (NSString *)obj : nil;
    if (!u.length) u = @"https://x.com/thsottiaux";   // 兜底：菜单项忘了带 URL 也跳对地方
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:u]];
}

// V1.6（交接单 JJ-2026-1101-01）：「关于」里的两个外链，系统默认浏览器打开
- (void)openAboutLink:(id)sender {
    id obj = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : nil;
    NSString *u = [obj isKindOfClass:NSString.class] ? (NSString *)obj : nil;
    if (!u.length) return;   // 没带 URL 就什么都不做，不瞎跳
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:u]];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

// 重启自己：先以「新实例」方式把本 app 再拉起一份，等它真起来了再退出当前实例
// 两个关键点：
// 1) createsNewApplicationInstance 必须设 YES —— 否则系统看到"已在运行"就不会开新的，等效于退出
// 2) 不能在发起启动后立刻 terminate —— 启动请求是异步的，进程一死请求被掐掉，表现就是"点了没反应"。
//    必须在 completionHandler 里确认新实例已拉起，再延迟一点点退出（2026-10-25 修）
- (void)restartApp:(id)sender {
    NSURL *selfURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
    NSWorkspaceOpenConfiguration *conf = [NSWorkspaceOpenConfiguration configuration];
    conf.createsNewApplicationInstance = YES;
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:selfURL
                                          configuration:conf
                                      completionHandler:^(NSRunningApplication *app, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !app) {
                // 兜底：走 open -n 拉新实例
                NSTask *task = [[NSTask alloc] init];
                task.launchPath = @"/usr/bin/open";
                task.arguments = @[@"-n", selfURL.path];
                [task launch];
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [NSApp terminate:nil];
            });
        });
    }];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
