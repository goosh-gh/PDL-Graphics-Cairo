/* pdlcairo_viewer.m
 * PDL::Graphics::Cairo用 軽量Cocoaビューア
 *
 * 使い方:
 *   pdlcairo_viewer /tmp/plot.png
 *   pdlcairo_viewer /tmp/plot.png "ウィンドウタイトル"
 *
 * 動作:
 *   - 指定されたPNGファイルをNSWindowで表示
 *   - ウィンドウを閉じるかQキーで終了
 *   - リサイズ時はアスペクト比を維持（gizaと同じletterbox）
 *
 * ビルド:
 *   clang -fobjc-arc -framework Cocoa \
 *         -o pdlcairo_viewer pdlcairo_viewer.m
 */

#import <Cocoa/Cocoa.h>

/* ------------------------------------------------------------------ */
/* PDLCairoView: PNG画像を表示するNSView                               */
/* ------------------------------------------------------------------ */
@interface PDLCairoImageView : NSView {
    NSImage *_image;
}
- (instancetype)initWithFile:(NSString *)path frame:(NSRect)frame;
@end

@implementation PDLCairoImageView

- (instancetype)initWithFile:(NSString *)path frame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _image = [[NSImage alloc] initWithContentsOfFile:path];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    /* 背景 */
    [[NSColor colorWithCalibratedWhite:0.15 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    if (!_image) return;

    /* アスペクト比維持スケーリング（letterbox/pillarbox） */
    NSSize imgSize = _image.size;
    NSSize viewSize = self.bounds.size;
    CGFloat sx = viewSize.width  / imgSize.width;
    CGFloat sy = viewSize.height / imgSize.height;
    CGFloat s  = (sx < sy) ? sx : sy;
    CGFloat dw = imgSize.width  * s;
    CGFloat dh = imgSize.height * s;
    CGFloat ox = (viewSize.width  - dw) * 0.5;
    CGFloat oy = (viewSize.height - dh) * 0.5;

    NSRect dst = NSMakeRect(ox, oy, dw, dh);
    [_image drawInRect:dst
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:1.0];
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event charactersIgnoringModifiers];
    if (chars.length > 0) {
        unichar c = [chars characterAtIndex:0];
        /* q/Q/ESC/Return で終了 */
        if (c == 'q' || c == 'Q' || c == 27 || c == 13) {
            [NSApp terminate:nil];
        }
    }
}

@end

/* ------------------------------------------------------------------ */
/* AppDelegate                                                          */
/* ------------------------------------------------------------------ */
@interface PDLCairoViewerDelegate : NSObject <NSApplicationDelegate>
@property (copy) NSString *imagePath;
@property (copy) NSString *windowTitle;
@end

@implementation PDLCairoViewerDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    /* 画像サイズを取得してウィンドウサイズを決定 */
    NSImage *img = [[NSImage alloc] initWithContentsOfFile:self.imagePath];
    if (!img) {
        NSLog(@"pdlcairo_viewer: cannot load image: %@", self.imagePath);
        [NSApp terminate:nil];
        return;
    }

    NSSize imgSize = img.size;
    /* 最大表示サイズ（スクリーンに収まるように） */
    NSScreen *screen = [NSScreen mainScreen];
    NSRect screenRect = screen ? screen.visibleFrame : NSMakeRect(0,0,1440,900);
    CGFloat maxW = screenRect.size.width  * 0.85;
    CGFloat maxH = screenRect.size.height * 0.85;
    CGFloat sx = (imgSize.width  > maxW) ? maxW / imgSize.width  : 1.0;
    CGFloat sy = (imgSize.height > maxH) ? maxH / imgSize.height : 1.0;
    CGFloat s  = (sx < sy) ? sx : sy;
    CGFloat winW = imgSize.width  * s;
    CGFloat winH = imgSize.height * s;

    NSRect frame = NSMakeRect(
        screenRect.origin.x + (screenRect.size.width  - winW) * 0.5,
        screenRect.origin.y + (screenRect.size.height - winH) * 0.5,
        winW, winH);

    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:frame
        styleMask:NSWindowStyleMaskTitled
                  |NSWindowStyleMaskClosable
                  |NSWindowStyleMaskResizable
                  |NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered
        defer:NO];

    [window setTitle:self.windowTitle ?: @"PDL::Graphics::Cairo"];

    PDLCairoImageView *view = [[PDLCairoImageView alloc]
        initWithFile:self.imagePath
               frame:NSMakeRect(0, 0, winW, winH)];
    [window setContentView:view];
    [window makeFirstResponder:view];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;  /* ウィンドウを閉じたらアプリ終了 */
}

@end

/* ------------------------------------------------------------------ */
/* main                                                                 */
/* ------------------------------------------------------------------ */
int main(int argc, const char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: pdlcairo_viewer <image.png> [title]\n");
        return 1;
    }

    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        PDLCairoViewerDelegate *delegate = [[PDLCairoViewerDelegate alloc] init];
        delegate.imagePath   = [NSString stringWithUTF8String:argv[1]];
        delegate.windowTitle = argc >= 3
            ? [NSString stringWithUTF8String:argv[2]]
            : @"PDL::Graphics::Cairo";
        [NSApp setDelegate:delegate];
        [NSApp run];
    }
    return 0;
}
