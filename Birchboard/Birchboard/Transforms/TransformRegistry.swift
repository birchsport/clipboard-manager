import Foundation

/// The list of transforms shown in the ⌘T picker. Ordered roughly by expected
/// frequency — the picker is searchable so order only matters for the no-query
/// default view.
enum TransformRegistry {
    static let all: [TextTransform] = [
        PrettyJSONTransform(),
        MinifyJSONTransform(),
        DecodeJWTTransform(),
        Base64EncodeTransform(),
        Base64DecodeTransform(),
        URLEncodeTransform(),
        URLDecodeTransform(),
        UpperCaseTransform(),
        LowerCaseTransform(),
        TitleCaseTransform(),
        CamelCaseTransform(),
        SnakeCaseTransform(),
        KebabCaseTransform(),
        StripANSITransform(),
        StripHTMLTransform(),
        ExtractURLsTransform(),
        ExtractEmailsTransform(),
    ]

    /// Filter the registry down to transforms that make sense for `text`.
    static func applicable(to text: String) -> [TextTransform] {
        all.filter { $0.isApplicable(to: text) }
    }
}
