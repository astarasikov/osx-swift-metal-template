import Foundation
import Cocoa

func main() -> Int32 {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    //app.run()
    return NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}
main()
