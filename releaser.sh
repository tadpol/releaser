#!/bin/bash

# releaser [options]
#
# Options:
#  -h       Help Text
#  -n       Dry run.
#  -t       Just run tests
#  -X       Do not delete temp dir

set -e
#set -x

########################################
# Set the default stages to run.
#stages="Setup AskVersion Test Archive UpdateReleaseNotes Commit Jira IPAandDSYM TrimReleaseNotes HockeyApp TestFlight CopyToDownloads"
#stages="Setup AskVersion Test Archive UpdateReleaseNotes Commit IPAandDSYM TrimReleaseNotes Upload"
stages="Setup AskVersion Archive UpdateReleaseNotes Commit TrimReleaseNotes Upload"


dry=no
cleanup=yes

while getopts ":ntXhS:s:" opt; do
  case "$opt" in
    n)
      dry=yes
      ;;
    t)
      stages="Setup AskVersion Test"
      ;;
    X)
      cleanup=no
      ;;
    S)
      # remove stage.
      ;;
    s)
      # add stage
      stages="$stages $OPTARG"
      ;;
    h)
      cat <<EOF
releaser [options]

Options:
 -h       Help Text
 -n       Dry run.
 -t       Just run tests
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

#################################################
dryrunp() {
	echo -e "\033[1m=>\033[0m $@"
	if [ "n$dry" != "nyes" ]; then
		"$@"
	fi
}

#################################################
checkStage() {
  echo -en "\033[1m=) Stage:\033[0m $1 "
  if [[ $stages =~ (^|[[:space:]])"$1"($|[[:space:]]) ]]; then
    echo -e "\033[1mRUN\033[0m"
    return 0
  else
    echo -e "\033[1mSKIP\033[0m"
    return 1
  fi
}

#################################################
printVariables() {
  echo -en "\033[1m=:\033[0m "
  while [ $# -gt 1 ]; do
    echo -en "\033[1m$1:\033[0m $2  "
    shift 2
  done
  if [ $# -gt 0 ]; then
    echo -en "\033[1m$1:\033[0m"
  fi
  echo ""
}


#################################################
td=$(mktemp -d ${TMPDIR}releaser.XXXXXX)
printVariables TmpDir "$td"

#################################################
cleanupdir() {
  if [ "n$cleanup" = "nyes" ]; then
    echo -e "\033[1m=>\033[0m Cleaning up."
    rm -rf $td
  else
    echo -e "\033[1m=>\033[0m No clean; Dir: $td"
  fi
}

###################################################################################################
### Get project info.
# Needs:
# Returns: workspace, target, scheme, uploadto, infoFile, releaseNotes

checkStage Setup
workspace=$(find . -depth 1 -name '*.xcworkspace')
target=$(basename -s .xcworkspace "$workspace")
infoFile=$(find . -name "$target-Info.plist")
if [ -z "$infoFile" -a -f "$target/Info.plist" ]; then
infoFile="$target/Info.plist"
fi
uploadto=copy
if (grep -q HockeySDK Podfile); then
  uploadto=HockeyApp
elif (grep -q TestFlightSDK Podfile); then
  uploadto=TestFlight
  stages="$stages IPAandDSYM"
fi
releaseNotes=$(dirname "$workspace")/ReleaseNotes.markdown

# For now, assume the scheme is the workspace.
scheme=$target

printVariables Workspace "$workspace" Target "$target" Scheme "$scheme"
printVariables BetaDist "$uploadto" "Jira Project" "$project"
printVariables InfoFile "$infoFile" "Release Notes" "$releaseNotes"
printVariables Stages "$stages"

###################################################################################################
### Get the version for the release.
# Needs: infoFile
# Returns: shortVersion

shortVersion=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$infoFile")
if checkStage AskVersion; then
  # Ask if this is the right version, if not let them change it.
  echo -ne "\033[1m=?\033[0m Enter the version you want to release ($shortVersion) "
  read preferredVersion
  if [ "n$preferredVersion" != "n" ]; then
    shortVersion=$preferredVersion
    dryrunp /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $preferredVersion" "$infoFile"
  fi
fi
printVariables "Will release version" "$shortVersion"

###################################################################################################
### Run Unit Tests
# Needs: workspace, scheme
if checkStage Test; then
  dryrunp xctool -workspace "$workspace" -scheme "$scheme" -sdk iphonesimulator7.1 test
fi

###################################################################################################
### Build the Archive
# Needs: workspace, scheme, infoFile
# Returns: version
if checkStage Archive; then
  dryrunp xctool -workspace "$workspace" -scheme "$scheme" archive
fi

# Cannot get the correct build number until after we do the build.
buildnumber=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$infoFile")
version=v${shortVersion}-$buildnumber

printVariables Version "$version"

###################################################################################################
### Update Release Notes
# Needs: td, releaseNotes
if checkStage UpdateReleaseNotes; then
  relnTmp=$td/releasenotes.markdown
  datestamp=$(date '+%d %b %Y')
  cat "$releaseNotes" | sed -e "s/^##\$/## $datestamp/" -e "s/^###\$/### $version/" > "$relnTmp"
  mv "$relnTmp" "$releaseNotes"
fi

###################################################################################################
### Commit this all and Tag the release.
# Needs: version
# Returns: gitRepo, gitSHA
if checkStage Commit; then
  dryrunp git commit -a -m "Release $version"
  dryrunp git tag $version -m "Release $version"
  dryrunp git push

  # Grab some stuff for hockey app.
  gitRepo=$(git remote -v | head -1 | awk '{print $2}')
  gitSHA=$(git show-ref heads/master | head -1 | awk '{print $1}')
else
  gitRepo=
  gitSHA=
fi
printVariables Repo "$gitRepo" SHA "$gitSHA"

###################################################################################################
### In Jira, create and release this version.
### Attaching all resolved, but unversioned issues to this version
# Needs: project, version
if checkStage Jira; then
  echo nothing yet.
fi


###################################################################################################
### Build up the .ipa and dSYM.zip
# Needs: td, target
# Returns: archivePath, appName, ipa, dsymZipped

#archivePath=$(find ~/Library/Developer/Xcode/Archives -type d -Btime -60m -name '*.xcarchive' | head -1)
archivePath=$(find ~/Library/Developer/Xcode/Archives -type d -name "$target*.xcarchive" | tail -1)
printVariables archivePath "$archivePath"

if checkStage IPAandDSYM; then
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
else
  appName=
  ipa=
  dsymZipped=
fi
printVariables AppName "$appName"
printVariables IPA "$ipa"
printVariables DSYM "$dsymZipped"

###################################################################################################
### Trim to just the current release note section
# Needs: td, releaseNotes
# Returns: releasedNote
if checkStage TrimReleaseNotes; then
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
else
  releasedNote="$releaseNotes"
fi
printVariables "Release Snippet" "$releasedNote"

###################################################################################################
if checkStage Upload; then
  ##################################################################################################
  ### HockeyApp Upload
  # Needs: archivePath, releaseNote, td, gitRepo, gitSHA
  if [ "n$uploadto" = "nHockeyApp" ]; then

    hockeyToken=$(security 2>&1 >/dev/null find-internet-password -gs HOCKEYAPP_TOKEN | cut -d '"' -f 2)
    if [ "n$hockeyToken" = "n" ]; then
      echo "Missing token for upload!!!"
      exit 1
    fi

    dryrunp puck "-repository_url=$gitRepo" \
      -commit_sha=$gitSHA \
      -notes_type=markdown \
      "-notes_path=$releasedNote" \
      -upload=all \
      -submit=manual \
      -download=true \
      -open=notify \
      -api_token=$hockeyToken \
      "$archivePath"

    # gotta wait a little otherwise we clean up before everything gets loaded.
    # puck still launches the full HockeyApp UI.  So we might want to consider moving
    # back to the curl method.
    sleep 10
  fi

  ##################################################################################################
  ### TestFlight Upload
  # Needs: appName, ipa, dsymZipped, releaseNote, td
  if [ "n$uploadto" = "nTestFlight" ]; then
    # FIXME: If security cannot fins the key, this does not fail the script.
    tfapitoken=$(security 2>&1 >/dev/null find-internet-password -gs TF_API_TOKEN -a "$appName" | cut -d '"' -f 2)
    tfteamtoken=$(security 2>&1 >/dev/null find-internet-password -gs TF_TEAM_TOKEN -a "$appName" | cut -d '"' -f 2)

    if [ "n$tfapitoken" = "n" -o "n$tfteamtoken" = "n" ]; then
      echo "Missing tokens for upload!!!"
      exit 1
    fi

    dryrunp curl http://testflightapp.com/api/builds.json \
      -F "file=@$ipa" \
      -F "dsym=@$dsymZipped" \
      -F "api_token=$tfapitoken" \
      -F "team_token=$tfteamtoken" \
      -F "notes=@$releasedNote" \
      -F notify=True \
      -o $td/uploadResults.json
    
  fi

  ##################################################################################################
  ### Just copy to Downloads
  # Needs: ipa, dsymZipped
  if [ "n$uploadto" = "ncopy" ]; then
    mv "$dsymZipped" "$ipa" ~/Downloads/
  fi

fi

###################################################################################################
### Cleanup
cleanupdir

# vim: set sw=2 ts=2 et :
