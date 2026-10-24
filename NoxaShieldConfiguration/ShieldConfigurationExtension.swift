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
    private let backgroundColor = UIColor(
        red: 7.0 / 255.0,
        green: 21.0 / 255.0,
        blue: 15.0 / 255.0,
        alpha: 1
    )
    private let accentColor = UIColor(
        red: 138.0 / 255.0,
        green: 206.0 / 255.0,
        blue: 0,
        alpha: 1
    )

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
        makeShield(
            title: "This app is blocked",
            subtitle: ShieldRuleExplanation.app(application, category: category)
                ?? "You chose this time for yourself. Take a breath and return to what matters."
        )
    }

    private func websiteShield(for webDomain: WebDomain, category: ActivityCategory?) -> ShieldConfiguration {
        makeShield(
            title: "This website is blocked",
            subtitle: ShieldRuleExplanation.website(webDomain, category: category)
                ?? "Pause before continuing. Protect the time you set aside for yourself."
        )
    }

    private func makeShield(title: String, subtitle: String) -> ShieldConfiguration {
        let icon = UIImage(systemName: "hourglass.circle.fill")?.withTintColor(
            accentColor,
            renderingMode: .alwaysOriginal
        )

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: backgroundColor,
            icon: icon,
            title: ShieldConfiguration.Label(text: title, color: .white),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: UIColor.white.withAlphaComponent(0.72)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Stay Focused",
                color: backgroundColor
            ),
            primaryButtonBackgroundColor: accentColor,
            secondaryButtonLabel: nil
        )
    }
}
