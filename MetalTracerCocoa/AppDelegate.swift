import Cocoa

//@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    let mWindowDelegate : NSWindowDelegate!
    let mWindow : NSWindow!
    let mMetalView: NSView!

    override init() {
        mWindowDelegate = WindowDelegate()
        mWindow = NSWindow(
            contentRect: NSMakeRect(0, 0, 640, 480),
            styleMask: NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask,
            backing: NSBackingStoreType.Buffered,
            `defer`: false)
        mMetalView = MetalView(frame: mWindow.contentView.frame)
    }

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        mWindow.title = "Metal Test"
        mWindow.delegate = mWindowDelegate
        mWindow.backgroundColor = NSColor.redColor()

        //mWindow.contentView.addSubview(mMetalView)
        mWindow.contentView = mMetalView
        mWindow.center()
        mWindow.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(aNotification: NSNotification) {
    }
}

