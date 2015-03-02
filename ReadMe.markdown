# Releaser

An attempt to gather all of the common steps I do every time I push an iOS app release.

It is a little haphazard at the moment.

When ever possible, information is gathered from the environment.

This *must* be run from the top directory of the project.

## Requirements
- Using [CocoaPods](http://cocoapods.org)
- [Nomad-cli](http://nomad-cli.com)
- Have a ReleaseNotes.markdown file in same directory as .xcworkspace
- Format the ReleaseNotes.markdown the same way I do.
- A `.rpjProject` file at the top level of the project.

## The list of things this is trying to automate
- Update (short) version string and build number
- Archive application
- Update ReleaseNotes.markdown with build date and version number.
- Commit and tag to git
- Package up .ipa and .dSYM.zip for upload to beta service
- Trim out just the latest notes from ReleaseNotes.markdown
- Upload to HockeyApp

