# Releaser

An attempt to gather all of the common steps I do every time I push an iOS app release.

It is a little haphazard at the moment.

When ever possible, information is gathered from the environment.

This *must* be run from the top directory of the project.

## Requirements
- Using an .xcworkspace
- Using CocoaPods
- xctool is installed
- Have a ReleaseNotes.markdown file in same directory as .xcworkspace
- Specify either the HockeySDK or TestFlightSDK in Podfile
- Build target is the rootname of the xcworkspace
- Build scheme is the same name as the target
- For TestFlight and HockeyApp, API tokens are in the keychain as internet passwords.
  - service `http://TF_API_TOKEN`, Account name is target name
  - service `http://TF_TEAM_TOKEN`, Account name is target name
	- service `http://HOCKEYAPP_TOKEN`, Account name is target name

## The list of things this is trying to automate
- Update (short) version string
- Run Tests
- Archive application
- Update ReleaseNotes.markdown with build date and version number.
- Commit, tag, and push to git
- Package up .ipa and .dSYM.zip for upload to beta service
- Trim out just the latest notes from ReleaseNotes.markdown
- Upload to HockeyApp or TestFlight

