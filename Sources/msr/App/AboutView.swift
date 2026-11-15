import RecorderLogic
import SwiftUI

struct AboutView: View {
    let version: AppVersion

    var body: some View {
        VStack(spacing: 12) {
            Text("Multi Screen Recorder").font(.title2.bold())
            Text(version.description).textSelection(.enabled)
            Text("Licence: GNU General Public License version 3")
            Text(ProductText.purpose)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Link("Report problems and ideas as GitHub issues", destination: GitHubRepository.issues)
        }
        .padding(24)
        .frame(width: 420)
    }
}
