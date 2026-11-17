/// Breaks `text` at spaces into lines of at most `width` characters; a word longer than that stays whole.
func wrappedLines(_ text: String, width: Int) -> [String] {
    var lines: [String] = []
    var line = ""
    for word in text.split(separator: " ") {
        if line.isEmpty {
            line = String(word)
        } else if line.count + 1 + word.count <= width {
            line += " \(word)"
        } else {
            lines.append(line)
            line = String(word)
        }
    }
    if !line.isEmpty { lines.append(line) }
    return lines
}
