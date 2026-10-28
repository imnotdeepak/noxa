import SwiftUI

@main
enum NoxaLauncher {
    static func main() {
        #if DEBUG
        if CommandLine.arguments.contains("-NoxaUIPreview") {
            NoxaUIPreviewApp.main()
            return
        }
        #endif
        NoxaApp.main()
    }
}
