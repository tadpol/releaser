#!/bin/bash

# releaser [options]
#
# Options:
#  -h       Help Text
#  -n       Dry run.
#  -X       Do not delete temp dir

set -e
#set -x

########################################
# Set the default stages to run.
stages="Setup AskVersion UpdateBuildNumber UpdateReleaseNotes Provisioning Archive TrimReleaseNotes Upload"


dry=no
cleanup=yes

while getopts ":ntXhS:s:" opt; do
  case "$opt" in
    n)
      dry=yes
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

removeStage() {
  stages=$(echo "$stages" | sed -e "s/$1//")
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
fi
releaseNotes=$(dirname "$workspace")/ReleaseNotes.markdown
if [ ! -f "$releaseNotes" ]; then
  releaseNotes=''
  removeStage TrimReleaseNotes
fi
team='Exosite LLC'

if [ -z "$profileName" ]; then 
  pn=$(echo "$target"| tr ' ' -)
  profileName=$(ios profiles --team "$team" --format csv | grep ".$pn" | awk -F, '{print $1}')
fi

printVariables Workspace "$workspace" Target "$target"
printVariables Team "$team" Profile "$profileName"
printVariables BetaDist "$uploadto" 
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

###################################################################################################
### Update build number with number of git commits
# Needs: infoFile shortVersion
# Returns: version
if checkStage UpdateBuildNumber; then
  buildNumber=$(git rev-list HEAD | wc -l | tr -d ' ')
  dryrunp /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "$infoFile"
else
  buildNumber=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$infoFile")
fi
version=v${shortVersion}-$buildNumber
printVariables "Will release version" "$version"

###################################################################################################
### Update Release Notes with date and version
# Needs: td, releaseNotes
if checkStage UpdateReleaseNotes; then
  relnTmp=$td/releasenotes.markdown
  datestamp=$(date '+%d %b %Y')
  cat "$releaseNotes" | sed -e "s/^##\$/## $datestamp/" -e "s/^###\$/### $version/" > "$relnTmp"
  mv "$relnTmp" "$releaseNotes"
fi

###################################################################################################
### Check git for tag
# Needs: version
# Returns: gitRepo, gitSHA

if ! ( git tag -l | grep -q "$version" ); then
  # Not there, add it
  dryrunp git commit -a -m "Release $version"
  dryrunp git tag $version -m "Release $version"

fi
gitRepo=$(git remote -v | head -1 | awk '{print $2}')
gitSHA=$(git show-ref heads/master | head -1 | awk '{print $1}')
printVariables Repo "$gitRepo" SHA "$gitSHA"

###################################################################################################
###

# Check and update devices in provisioning profile?
# - list all devices on team
# - filter by 'group'
#  then what?
# Still cannot modify the 'Xcode managed' profiles.

###################################################################################################
### Get provisioning profile
# Needs: team profileName
# Returns: profileFile
if checkStage Provisioning; then
  ( cd "$td"; ios profiles:download --team "$team" "$profileName" )
  profileFile=$(find "$td" -name '*.mobileprovision' |head -1)
  printVariables ProfileFile "$profileFile"
fi

###################################################################################################
### Build the Archive
# Needs: infoFile
# Returns: 
if checkStage Archive; then
  dryrunp ipa build --clean --archive --embed "${profileFile}" --destination "$td"
  ipaFile=$(find "$td" -name '*.ipa' | head -1)
  dsymFile=$(find "$td" -name '*.dSYM.zip' | head -1)
fi

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
    # consider ipa distribute:hockeyapp

    if [ "n$usePuck" == "nno" ]; then
      hockeyToken=$(security 2>&1 >/dev/null find-internet-password -gs HOCKEYAPP_TOKEN | cut -d '"' -f 2)
      if [ "n$hockeyToken" = "n" ]; then
        echo "Missing token for upload!!!"
        exit 1
      fi
      notes=$(cat "$releasedNote")

      export "HOCKEYAPP_API_TOKEN=$hockeyToken"
      dryrunp ipa distribute:hockeyapp \
        --file "$ipaFile" \
        --dsym "$dsymFile" \
        --markdown \
        --notes "$notes" \
        --tags exosite \
        --downloadOff \
        --commit-sha "$gitSHA" \
        --repository-url "$gitRepo"
      unset HOCKEYAPP_API_TOKEN

    else
      dryrunp puck "-repository_url=$gitRepo" \
        -commit_sha=$gitSHA \
        -notes_type=markdown \
        "-notes_path=$releasedNote" \
        -upload=all \
        -submit=manual \
        -download=true \
        -tags=exosite \
        -open=nothing \
        "-dsym_path=$dsymFile" \
        "$ipaFile"

      # gotta wait a little otherwise we clean up before everything gets loaded.
      # puck still launches the full HockeyApp UI.  So we might want to consider moving
      # back to the curl method. Actually finding that I like the UI coming up.
      sleep 10
    fi

  fi

fi

###################################################################################################
### Cleanup
cleanupdir

# vim: set sw=2 ts=2 et :
