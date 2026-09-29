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
        appShield
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        appShield
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        websiteShield
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        websiteShield
    }

    private var appShield: ShieldConfiguration {
        makeShield(
            title: "This app is blocked",
            subtitle: "You chose this time for yourself. Take a breath and return to what matters."
        )
    }

    private var websiteShield: ShieldConfiguration {
        makeShield(
            title: "This website is blocked",
            subtitle: "Pause before continuing. Protect the time you set aside for yourself."
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
