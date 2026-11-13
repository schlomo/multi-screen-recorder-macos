import RecorderLogic
import SwiftUI

struct AboutView: View {
    let version: AppVersion

    private static let issues = URL(string: "https://github.com/schlomo/multi-screen-recorder-macos/issues")!

    var body: some View {
        VStack(spacing: 12) {
            Text("Multi Screen Recorder").font(.title2.bold())
            Text(version.description).textSelection(.enabled)
            Text("Licence: GNU General Public License version 3")
            Text(ProductText.purpose)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Link("Report problems and ideas as GitHub issues", destination: Self.issues)
        }
        .padding(24)
        .frame(width: 420)
    }
}
