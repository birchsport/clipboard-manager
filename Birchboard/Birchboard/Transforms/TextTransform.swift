import Foundation

/// A one-shot transform over the plain-text projection of a clip entry. Invoked
/// from the panel's transform picker (⌘T). Transforms are pure — given the same
/// input they return the same output — and self-describe whether they make sense
/// for a given input via `isApplicable(to:)`.
protocol TextTransform {
    /// Stable, namespaced identifier (e.g., `"json.pretty"`). Used for logs and
    /// will later anchor preferences like favourites or hidden transforms.
    var id: String { get }

    /// Human-facing label in the picker. Keep terse.
    var displayName: String { get }

    /// True if running this transform against `text` has a meaningful result.
    /// Inapplicable transforms are filtered out of the picker upfront so the user
    /// never sees "Pretty JSON" on a non-JSON string.
    func isApplicable(to text: String) -> Bool

    /// Apply the transform. Returning `nil` signals a failure we couldn't predict
    /// from `isApplicable` alone (e.g., the string parsed as JSON but serialising
    /// back produced nothing useful). The caller surfaces an error.
    func apply(to text: String) -> String?
}

extension TextTransform {
    /// Default applicability: any non-empty input. Transforms with stricter needs
    /// override this.
    func isApplicable(to text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
