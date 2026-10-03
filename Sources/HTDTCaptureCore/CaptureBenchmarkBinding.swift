import Foundation

/// Deterministic compatibility predicates for binding a benchmark
/// reference to a capture (legacy bolph71656-ai/HTDT-Capture#285). Every non-nil predicate must match;
/// nil fields are wildcards. Predicates never decide per-capture
/// accuracy — a bound ref only states that immutable benchmark evidence
/// exists for a compatible configuration.
public struct BenchmarkCompatibilityRule: Sendable, Equatable {
    /// Immutable, versioned evidence reference the rule may bind, e.g.
    /// `htdt.benchmark.iphone15pro-lidar@1.0.0`.
    public let reference: String
    public let appVersion: String?
    public let deviceClass: String?
    /// Inclusive OS major-version range the evidence covers.
    public let osMajorMinimum: Int?
    public let osMajorMaximum: Int?
    public let captureMode: String?
    public let rulesetVersion: String?
    public let bundleSchemaVersion: String?

    public init(
        reference: String,
        appVersion: String? = nil,
        deviceClass: String? = nil,
        osMajorMinimum: Int? = nil,
        osMajorMaximum: Int? = nil,
        captureMode: String? = nil,
        rulesetVersion: String? = nil,
        bundleSchemaVersion: String? = nil
    ) {
        self.reference = reference
        self.appVersion = appVersion
        self.deviceClass = deviceClass
        self.osMajorMinimum = osMajorMinimum
        self.osMajorMaximum = osMajorMaximum
        self.captureMode = captureMode
        self.rulesetVersion = rulesetVersion
        self.bundleSchemaVersion = bundleSchemaVersion
    }

    func matches(_ context: BenchmarkBindingContext) -> Bool {
        if let appVersion, appVersion != context.appVersion {
            return false
        }
        if let deviceClass, deviceClass != context.deviceClass {
            return false
        }
        if let osMajorMinimum,
           context.osMajorVersion < osMajorMinimum
        {
            return false
        }
        if let osMajorMaximum,
           context.osMajorVersion > osMajorMaximum
        {
            return false
        }
        if let captureMode, captureMode != context.captureMode {
            return false
        }
        if let rulesetVersion,
           rulesetVersion != context.rulesetVersion
        {
            return false
        }
        if let bundleSchemaVersion,
           bundleSchemaVersion != context.bundleSchemaVersion
        {
            return false
        }
        return true
    }
}

public struct BenchmarkBindingContext: Sendable, Equatable {
    public let appVersion: String
    public let deviceClass: String
    public let osMajorVersion: Int
    public let captureMode: String
    public let rulesetVersion: String
    public let bundleSchemaVersion: String

    public init(
        appVersion: String,
        deviceClass: String,
        osMajorVersion: Int,
        captureMode: String,
        rulesetVersion: String,
        bundleSchemaVersion: String
    ) {
        self.appVersion = appVersion
        self.deviceClass = deviceClass
        self.osMajorVersion = osMajorVersion
        self.captureMode = captureMode
        self.rulesetVersion = rulesetVersion
        self.bundleSchemaVersion = bundleSchemaVersion
    }
}

/// A benchmark reference must name an immutable, versioned evidence
/// artifact: `<slug>@<semver>`. Anything else cannot be bound.
public enum BenchmarkReferenceValidator {
    public static func isValid(_ reference: String) -> Bool {
        let parts = reference.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let slug = parts[0]
        let version = parts[1]
        guard !slug.isEmpty,
              slug.allSatisfy({
                  $0.isASCII
                      && ($0.isLetter || $0.isNumber
                              || $0 == "-" || $0 == "_" || $0 == ".")
              })
        else { return false }
        let components = version.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard components.count == 3 else { return false }
        return components.allSatisfy {
            !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber)
        }
    }
}

/// Registry of benchmark evidence whose compatibility with production
/// capture configurations has been established. Empty until the physical
/// benchmark program (legacy bolph71656-ai/HTDT-Capture#9) publishes rules; production therefore records
/// an explicit empty ref list rather than guessing.
public enum BenchmarkReferenceAuthority {
    public static let publishedRules: [BenchmarkCompatibilityRule] = []

    public static func compatibleReferences(
        context: BenchmarkBindingContext,
        rules: [BenchmarkCompatibilityRule] = publishedRules
    ) -> [String] {
        var refs: [String] = []
        for rule in rules where rule.matches(context) {
            if BenchmarkReferenceValidator.isValid(rule.reference) {
                refs.append(rule.reference)
            }
        }
        return CaptureQualityEvaluator.canonicalBenchmarkRefs(refs)
    }
}
