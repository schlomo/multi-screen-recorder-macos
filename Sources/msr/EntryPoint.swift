import RecorderCore

/// With arguments msr is the command line; without, it is the app. Started
/// through a symbolic link, it first re-executes itself at its real path.
@main
enum EntryPoint {
    static func main() async {
        reexecuteAtRealPathIfLinked()
        if CommandLine.arguments.count > 1 {
            await CommandLineInterface.main(nil)
        } else {
            RecorderApp.run()
        }
    }
}
