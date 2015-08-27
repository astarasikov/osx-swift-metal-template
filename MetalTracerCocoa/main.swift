import Foundation
import Cocoa

func main() {
    let app = NSApplication.sharedApplication()
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
main()