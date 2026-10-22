# Privacy policy update required before the push-enabled build ships

Add this disclosure to the published Noxa privacy policy at `noxaapp.com/privacy`
before releasing the push-enabled Live Activity build:

> If you enable Live Activities, Noxa sends a temporary Apple Live Activity push
> token and your focus timer's start and planned end times to our service. We
> use this information only to remove the Lock Screen timer after the session
> ends while Noxa is closed. We do not send the apps, categories, websites, or
> intention selected for the session with this token. The record is normally
> removed about 24 hours after the planned end, or when you delete your account. Apple
> receives the push needed to end the Live Activity. If the service or network
> is unavailable, Noxa removes the timer when you next open the app.

The app already links to the published policy from onboarding and Settings.
The website is outside this repository, so this file is the exact copy to
publish alongside backend configuration, before public release.
