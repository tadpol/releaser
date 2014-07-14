#!/bin/bash

# releaser [options]
#
# Options:
#  -h       Help Text
#  -n       Dry run.
#  -t       Just run tests
#  -U       No upload
#  -X       Do not delete temp dir

set -e
#set -x

dry=no
onlytest=no
upload=yes
cleanup=yes

while getopts ":ntUXh" opt; do
  case "$opt" in
    n)
      dry=yes
      ;;
    t)
      onlytest=yes
      ;;
    U)
      upload=no
      ;;
    X)
      cleanup=no
      ;;
    h)
      cat <<EOF
releaser [options]

Options:
 -h       Help Text
 -n       Dry run.
 -t       Just run tests
 -U       No upload
 -X       Do not delete temp dir
EOF
      exit 2
      ;;

    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))

echo ""

dryrunp() {
	echo -e "\033[1m=>\033[0m $@"
	if [ "n$dry" != "nyes" ]; then
		"$@"
	fi
}

td=$(mktemp -d ${TMPDIR}releaser.XXXXXX)
echo -e "\033[1m=:\033[0m $td"

cleanupdir() {
  if [ "n$cleanup" = "nyes" ]; then
    echo -e "\033[1m=>\033[0m Cleaning up."
    rm -rf $td
  else
    echo -e "\033[1m=>\033[0m No clean; Dir: $td"
  fi
}

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
if [ "n$upload" = "nno" ];then
  uploadto=skip
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
dryrunp xctool -workspace "$workspace" -scheme "$scheme" -sdk iphonesimulator7.1 test

if [ "n$onlytest" = "nyes" ]; then
  cleanupdir
  exit
fi

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
gitSHA=$(git show-ref heads/master | head -1 | awk '{print $1}')

# For Jira Kanban for this project, Release
# In Jira, create and release this version.
# Attaching all resolved, but unversioned issues to this version
project=EXOIOS
# FIXME: Won't set fixVersions on issues, but creates and releases Version just fine.
cat >>$td/jira.cli <<EOF
--action runFromIssueList --search "project = '$project' and status = 'Resolved' and fixVersion = EMPTY" --common "--action updateIssue --issue @issue@ --fixVersions ""$version"" --autoVersion --append" 
--action releaseVersion --project "$project" --name "$version"
EOF
# jira --server "" --user "" --password "" --action run --file "$td/jira.cli"


### Build up the .ipa and dSYM.zip
#archivePath=$(find ~/Library/Developer/Xcode/Archives -type d -Btime -60m -name '*.xcarchive' | head -1)
archivePath=$(find ~/Library/Developer/Xcode/Archives -type d -name "$target*.xcarchive" | tail -1)
#echo -e "\033[1m=:\033[0m archivePath=$archivePath"
appPath=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:ApplicationPath" "$archivePath/Info.plist" )
#appName=$(/usr/libexec/PlistBuddy -c "Print :Name" "$archivePath/Info.plist" )
appName=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$archivePath/Products/$appPath/Info.plist")
echo -e "\033[1m=:\033[0m appName=$appName  appPath=$appPath"

ipa=$td/${appName}.ipa
dryrunp xcrun -sdk iphoneos PackageApplication "$archivePath/Products/$appPath" -o "$ipa"

dsymPath=$archivePath/dSYMs/${appName}.app.dSYM
dsymZipped=$td/${appName}.app.dSYM.zip
dryrunp zip -q -r -9 "$dsymZipped" "$dsymPath"

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

  hockeyToken=$(security 2>&1 >/dev/null find-internet-password -gs HOCKEYAPP_TOKEN -a "$appName" | cut -d '"' -f 2)
  if [ "n$hockeyToken" = "n" ]; then
    echo "Missing token for upload!!!"
    exit 1
  fi
  
  # FIXME: Release notes are not getting uploaded.
  # I think I need to read teh file and URL encode it and inline it. (ew)
  dryrunp curl -v -H "X-HockeyAppToken: $hockeyToken" \
    -F status=2 \
    -F notify=1 \
    -F "notes=@$releasedNote" \
    -F notes_type=1 \
    -F repository_url=$gitRepo \
    -F commit_sha=$gitSHA \
    -F "ipa=@$ipa" \
    -F "dsym=@$dsymZipped" \
    -o $td/uploadResults.json \
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
    -F notify=True \
    -o $td/uploadResults.json
  
fi

# just copy to Downloads
if [ "n$uploadto" = "nnone" ]; then
  mv "$dsymZipped" "$ipa" ~/Downloads/
fi

### Cleanup
cleanupdir

# vim: set sw=2 ts=2 et :
