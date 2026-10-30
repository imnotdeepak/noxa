//
//  ShieldConfigurationExtension.swift
//  NoxaShieldConfiguration
//
//  Created by Deepak on 9/29/26.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    // Noxa's near-black canvas and lime accent.
    private let backgroundColor = UIColor(red: 3.0 / 255.0, green: 5.0 / 255.0, blue: 3.0 / 255.0, alpha: 1)
    private let accentColor = UIColor(red: 168.0 / 255.0, green: 240.0 / 255.0, blue: 0, alpha: 1)

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        appShield(for: application, category: nil)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        appShield(for: application, category: category)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        websiteShield(for: webDomain, category: nil)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        websiteShield(for: webDomain, category: category)
    }

    private func appShield(for application: Application, category: ActivityCategory?) -> ShieldConfiguration {
        makeShield(title: ShieldRuleExplanation.app(application, category: category))
    }

    private func websiteShield(for webDomain: WebDomain, category: ActivityCategory?) -> ShieldConfiguration {
        makeShield(title: ShieldRuleExplanation.website(webDomain, category: category))
    }

    /// One sentence and nothing else: what blocked it, by kind.
    private func makeShield(title: String) -> ShieldConfiguration {
        let icon = UIImage(systemName: "hourglass.circle.fill")?.withTintColor(
            accentColor,
            renderingMode: .alwaysOriginal
        )

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: backgroundColor,
            icon: icon,
            title: ShieldConfiguration.Label(text: title, color: .white),
            subtitle: nil,
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Stay Focused",
                color: backgroundColor
            ),
            primaryButtonBackgroundColor: accentColor,
            secondaryButtonLabel: nil
        )
    }
}
