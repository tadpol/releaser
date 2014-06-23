#!/bin/bash

# releaser [?]
set -e
#set -x

echo ""

dry=no
dryrunp() {
	echo -e "\033[1m=>\033[0m $@"
	if [ "n$dry" != "n" ]; then
		"$@"
	fi
}

td=$(mktemp -d ${TMPDIR}releaser.XXXXXX)
echo -e "\033[1m=:\033[0m $td"

# get project info.
workspace=$(find . -depth 1 -name '*.xcworkspace')
target=$(basename -s .xcworkspace "$workspace")
infoFile=$(find . -name "$target-Info.plist")
uploadto=none
if (grep -q HockeySDK Podfile); then
	uploadto=HockeyApp
elif (grep -q TestFlightSDK Podfile); then
	uploadto=TestFlight
fi
releaseNotes=$(dirname "$workspace")/ReleaseNotes.markdown

# For now, assume the scheme is the workspace.
scheme=$target

echo -e "\033[1m=:\033[0m \033[1mWorkspace:\033[0m $workspace  \033[1mTarget:\033[0m $target  \033[1mScheme:\033[0m $scheme"
echo -e "\033[1m=:\033[0m \033[1mBetaDist:\033[0m $uploadto  \033[1mInfofile:\033[0m $infoFile"

### Get the version for the release.
shortVersion=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$infoFile")
# Ask if this is the right version, if not let them change it.
echo -ne "\033[1m=)\033[0m Enter the version you want to release ($shortVersion) "
read preferredVersion
if [ "n$preferredVersion" != "n" ]; then
	shortVersion=$preferredVersion
	dryrunp /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $preferredVersion" "$infoFile"
fi
echo -e "\033[1m=]\033[0m Will release version $shortVersion"

### Run Unit Tests
#dryrunp xctool -workspace "$workspace" -scheme "$scheme" -sdk iphonesimulator7.1 test

### Build the Archive
dryrunp xctool -workspace "$workspace" -scheme "$scheme" archive

# Cannot get build number until after we do the build.
buildnumber=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$infoFile")
version=v${shortVersion}-$buildnumber

relnTmp=$td/releasenotes.markdown
datestamp=$(date '+%d %b %Y')
cat "$releaseNotes" | sed -e "s/^##\$/## $datestamp/" -e "s/^###\$/### $version/" > "$relnTmp"
mv "$relnTmp" "$releaseNotes"

### Commit this all and Tag the release.
dryrunp git commit -a -m "Release $version"
dryrunp git tag $version -m "Release $version"
dryrunp git push

#### Grab some stuff for hockey app.
gitRepo=$(git remote -v | head -1 | awk '{print $2}')
gitSHA=$(git show-ref | awk '{print $1}')

# For Jira Kanban for this project, Release
# TODO: how to script this?


### Build up the .ipa and dSYM.zip
#archivePath=$(find ~/Library/Developer/Xcode/Archives -type d -Btime -60m -name '*.xcarchive' | head -1)
archivePath=$(find ~/Library/Developer/Xcode/Archives -type d -name "$target*.xcarchive" | tail -1)
#echo -e "\033[1m=:\033[0m archivePath=$archivePath"
appPath=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:ApplicationPath" "$archivePath/Info.plist" )
appName=$(/usr/libexec/PlistBuddy -c "Print :Name" "$archivePath/Info.plist" )
echo -e "\033[1m=:\033[0m appName=$appName  appPath=$appPath"

ipa=$td/${appName}.ipa
dryrunp xcrun -sdk iphoneos PackageApplication "$archivePath/Products/$appPath" -o "$ipa"

dsymPath=$archivePath/dSYMs/${appName}.app.dSYM
dsymZipped=$td/${appName}.app.dSYM.zip
dryrunp zip -r -9 "$dsymZipped" "$dsymPath"

releasedNote=$td/ReleasedNote.markdown
awk '
BEGIN { off=0 }
off==0 {}
off==0 && /^## / {
	off=1
	print
	next
}
off==1 && /^## / { exit }
off==1 { print }
' "$releaseNotes" > "$releasedNote"

# HockeyApp upload
if [ "n$uploadto" = "nHockeyApp" ]; then
	exit 2

	tfteamtoken=$(security 2>&1 >/dev/null find-internet-password -gs HOCKEYAPP_TOKEN -a "$appName" | cut -d '"' -f 2)
	if [ "n$hockeyToken" = "n" ]; then
		echo "Missing token for upload!!!"
		exit 1
	fi

	dryrunp curl -H "X-HockeyAppToken: $hockeyToken" \
		-F status=2 \
		-F notify=1 \
		-F "notes=@$releasedNote" \
		-F notes_type=1 \
		-F repository_url=$gitRepo \
		-F commit_sha=$gitSHA \
		-F "ipa=@$ipa" \
		-F "dsym=@$dsymZipped" \
		https://rink.hockeyapp.net/api/2/apps/upload

fi

# TestFlight upload
if [ "n$uploadto" = "nTestFlight" ]; then
	tfapitoken=$(security 2>&1 >/dev/null find-internet-password -gs TF_API_TOKEN -a "$appName" | cut -d '"' -f 2)
	tfteamtoken=$(security 2>&1 >/dev/null find-internet-password -gs TF_TEAM_TOKEN -a "$appName" | cut -d '"' -f 2)

	if [ "n$tfapitoken" = "n" -o "n$tfteamtoken" = "n" ]; then
		echo "Missing tokens for upload!!!"
		exit 1
	fi

	dryrunp curl http://testflightapp.com/api/builds.json \
		-F "file=@$ipa" \
		-F "dsym=@$dsymZipped" \
		-F api_token=$tfapitoken \
		-F team_token=$tfteamtoken \
		-F "notes=@$releasedNote" \
		-F notify=True 
	
fi


### Cleanup
rm -rf $td

# vim: set sw=4 ts=4 :
