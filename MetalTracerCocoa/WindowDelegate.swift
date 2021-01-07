import Cocoa

class WindowDelegate : NSObject, NSWindowDelegate
{
    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.terminate(self)
    }
}
