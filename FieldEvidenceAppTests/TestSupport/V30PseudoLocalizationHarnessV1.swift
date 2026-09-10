import Foundation
@testable import FieldEvidenceApp

#if DEBUG && targetEnvironment(simulator)
enum V30PseudoLocalizationHarnessTestSupportV1 {
    static func configuration(
        profile: V30PseudoLocalizationLaunchConfigurationV1.Profile = .enXA,
        dynamicType: V30PseudoLocalizationLaunchConfigurationV1.DynamicType = .large,
        appearance: V30PseudoLocalizationLaunchConfigurationV1.Appearance = .light,
        contrast: V30PseudoLocalizationLaunchConfigurationV1.Contrast = .normal
    ) -> V30PseudoLocalizationLaunchConfigurationV1 {
        V30PseudoLocalizationLaunchConfigurationV1(
            profile: profile,
            dynamicType: dynamicType,
            appearance: appearance,
            contrast: contrast
        )
    }

    static func arguments(
        profile: V30PseudoLocalizationLaunchConfigurationV1.Profile = .enXA,
        dynamicType: V30PseudoLocalizationLaunchConfigurationV1.DynamicType = .large,
        appearance: V30PseudoLocalizationLaunchConfigurationV1.Appearance = .light,
        contrast: V30PseudoLocalizationLaunchConfigurationV1.Contrast = .normal
    ) -> [String] {
        [
            V30PseudoLocalizationLaunchConfigurationV1.harnessArgument,
            V30PseudoLocalizationLaunchConfigurationV1.uiTestingArgument,
            V30PseudoLocalizationLaunchConfigurationV1.profileArgument, profile.rawValue,
            V30PseudoLocalizationLaunchConfigurationV1.dynamicTypeArgument, dynamicType.rawValue,
            V30PseudoLocalizationLaunchConfigurationV1.appearanceArgument, appearance.rawValue,
            V30PseudoLocalizationLaunchConfigurationV1.contrastArgument, contrast.rawValue,
        ]
    }

    static let orderedProtectedTokens = ["%@", "%1$@", "%lld", "%2$lld", "%%", "{assetID}"]
    static let fixedSource = "Sample"
    static let expectedAccented = "⟦Sámplë ··⟧"
    static let expectedLong = "⟦Sample · Sample⟧"
    static let longExpansionMinimumMultiplier = 2
}
#endif