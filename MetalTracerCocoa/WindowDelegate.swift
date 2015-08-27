import Cocoa

class WindowDelegate : NSObject, NSWindowDelegate
{
    func windowWillClose(notification: NSNotification) {
        NSApplication.sharedApplication().terminate(self)
    }
}
