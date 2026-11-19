import Foundation

/// The link to a new GitHub issue with one of the repository's issue forms,
/// its title and fields filled from the query: a field's id is its parameter.
/// The app only opens it in the browser (D15).
public enum IssueFormLink {
    public static func url(template: String, title: String, fields: [(id: String, value: String)]) -> URL {
        var components = URLComponents(url: GitHubRepository.issues.appending(path: "new"), resolvingAgainstBaseURL: false)!
        let items = [("template", template), ("title", title)] + fields.map { ($0.id, $0.value) }
        // URLComponents leaves & = + # unencoded in values; the form needs them encoded.
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))
        components.percentEncodedQuery = items.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
        return components.url!
    }
}
