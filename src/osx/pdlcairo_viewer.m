/* pdlcairo_viewer.m
 * PDL::Graphics::Cairo用 軽量Cocoaビューア
 *
 * 複数画像を1ウィンドウのタブで表示。
 * letterbox（白背景）方式でアスペクト比を維持。
 *
 * 使い方:
 *   pdlcairo_viewer img1.png "Title1" img2.png "Title2" ...
 *
 * キー操作:
 *   q / ESC / Return → 終了
 */

#import <Cocoa/Cocoa.h>

/* ------------------------------------------------------------------ */
/* 1タブ分のデータ                                                       */
/* ------------------------------------------------------------------ */
@interface PDLCairoTab : NSObject
@property (copy) NSString *imagePath;
@property (copy) NSString *title;
@end
@implementation PDLCairoTab
@end

/* ------------------------------------------------------------------ */
/* PDLCairoImageView                                                    */
/* ------------------------------------------------------------------ */
@interface PDLCairoImageView : NSView {
    NSImage *_image;
}
- (instancetype)initWithFile:(NSString *)path;
@end

@implementation PDLCairoImageView

- (instancetype)initWithFile:(NSString *)path {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _image = [[NSImage alloc] initWithContentsOfFile:path];
        /* viewがウィンドウのコンテンツ領域全体に追従する */
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor whiteColor] setFill];
    NSRectFill(self.bounds);
    if (!_image) return;

    /* letterbox: アスペクト比を維持して中央に表示 */
    NSSize imgSize  = _image.size;
    NSSize viewSize = self.bounds.size;
    if (imgSize.width <= 0 || imgSize.height <= 0) return;

    CGFloat sx = viewSize.width  / imgSize.width;
    CGFloat sy = viewSize.height / imgSize.height;
    CGFloat s  = (sx < sy) ? sx : sy;
    CGFloat dw = imgSize.width  * s;
    CGFloat dh = imgSize.height * s;
    NSRect dst = NSMakeRect(
        (viewSize.width  - dw) * 0.5,
        (viewSize.height - dh) * 0.5,
        dw, dh);

    [_image drawInRect:dst
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:1.0];
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event charactersIgnoringModifiers];
    if (chars.length == 0) return;
    unichar c = [chars characterAtIndex:0];
    if (c == 'q' || c == 'Q' || c == 27 || c == 13) {
        [NSApp terminate:nil];
    }
}

@end

/* ------------------------------------------------------------------ */
/* AppDelegate                                                          */
/* ------------------------------------------------------------------ */
@interface PDLCairoViewerDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSArray<PDLCairoTab *> *tabs;
@end

@implementation PDLCairoViewerDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    NSScreen *screen = [NSScreen mainScreen];
    NSRect sr = screen ? screen.visibleFrame : NSMakeRect(0, 0, 1440, 900);

    /* 全タブ中の最大PNGサイズを求めてウィンドウサイズを決定 */
    CGFloat maxW = 0, maxH = 0;
    for (PDLCairoTab *tab in self.tabs) {
        NSImage *img = [[NSImage alloc] initWithContentsOfFile:tab.imagePath];
        if (!img) continue;
        maxW = MAX(maxW, img.size.width);
        maxH = MAX(maxH, img.size.height);
    }
    if (maxW <= 0 || maxH <= 0) { [NSApp terminate:nil]; return; }

    /* スクリーンに収まるようにスケール */
    CGFloat limW = sr.size.width  * 0.85;
    CGFloat limH = sr.size.height * 0.85;
    CGFloat s = MIN(limW / maxW, limH / maxH);
    if (s > 1.0) s = 1.0;
    CGFloat winW = maxW * s;
    CGFloat winH = maxH * s;

    NSRect contentRect = NSMakeRect(
        sr.origin.x + (sr.size.width  - winW) * 0.5,
        sr.origin.y + (sr.size.height - winH) * 0.5,
        winW, winH);

    NSWindow *firstWindow = nil;

    for (PDLCairoTab *tab in self.tabs) {
        NSWindow *window = [[NSWindow alloc]
            initWithContentRect:contentRect
            styleMask:NSWindowStyleMaskTitled
                      | NSWindowStyleMaskClosable
                      | NSWindowStyleMaskResizable
                      | NSWindowStyleMaskMiniaturizable
            backing:NSBackingStoreBuffered
            defer:NO];
        [window setTitle:tab.title];

        if (@available(macOS 10.12, *)) {
            window.tabbingIdentifier = @"PDLCairoViewer";
            window.tabbingMode       = NSWindowTabbingModePreferred;
        }

        PDLCairoImageView *view = [[PDLCairoImageView alloc]
            initWithFile:tab.imagePath];
        [window setContentView:view];
        [window makeFirstResponder:view];

        if (firstWindow == nil) {
            firstWindow = window;
            [window makeKeyAndOrderFront:nil];
        } else {
            if (@available(macOS 10.12, *)) {
                [firstWindow addTabbedWindow:window ordered:NSWindowAbove];
            } else {
                [window makeKeyAndOrderFront:nil];
            }
        }
    }

    [firstWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

/* 全ウィンドウが閉じたら終了 */
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

@end

/* ------------------------------------------------------------------ */
/* main                                                                 */
/* ------------------------------------------------------------------ */
int main(int argc, const char *argv[]) {
    if (argc < 2) {
        fprintf(stderr,
            "Usage: pdlcairo_viewer img1.png Title1 [img2.png Title2 ...]\n");
        return 1;
    }

    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        NSMutableArray<PDLCairoTab *> *tabs = [NSMutableArray array];
        int i = 1;
        while (i < argc) {
            PDLCairoTab *tab  = [[PDLCairoTab alloc] init];
            tab.imagePath = [NSString stringWithUTF8String:argv[i++]];
            tab.title     = (i < argc)
                ? [NSString stringWithUTF8String:argv[i++]]
                : @"PDL::Graphics::Cairo";
            [tabs addObject:tab];
        }

        PDLCairoViewerDelegate *delegate = [[PDLCairoViewerDelegate alloc] init];
        delegate.tabs = tabs;
        [NSApp setDelegate:delegate];
        [NSApp run];
    }
    return 0;
}
