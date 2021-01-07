import Cocoa

//@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    let mWindowDelegate : NSWindowDelegate!
    let mWindow : NSWindow!
    let mMetalView: NSView!

    override init() {
        mWindowDelegate = WindowDelegate()
        mWindow = NSWindow(
            contentRect: NSMakeRect(0, 0, 1024, 1024),
            styleMask:
                NSWindow.StyleMask.resizable.union(NSWindow.StyleMask.closable.union(NSWindow.StyleMask.titled)),
            backing: NSWindow.BackingStoreType.buffered,
            defer: false)
        mMetalView = MetalView(frame: (mWindow?.contentView?.frame)!)
        print("Init Done")
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("applicationDidFinishLaunching")
        mWindow.title = "Metal Test"
        mWindow.delegate = mWindowDelegate
        mWindow.backgroundColor = NSColor.red

        //mWindow.contentView.addSubview(mMetalView)
        mWindow.contentView = mMetalView
        mWindow.center()
        mWindow.makeKeyAndOrderFront(nil)
    }
}

