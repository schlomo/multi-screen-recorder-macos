/// With arguments msr is the command line; without, it is the app.
@main
enum EntryPoint {
    static func main() async {
        if CommandLine.arguments.count > 1 {
            await CommandLineInterface.main(nil)
        } else {
            RecorderApp.run()
        }
    }
}
