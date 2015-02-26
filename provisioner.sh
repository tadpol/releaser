#!/bin/bash
#
# For an App, this takes UDIDs from HockeyApp and puts them into Apple Developer account.
# Updating a profile for testing.
#
# Both the HockeyApp entry and the AppleDev Profile must be created first.

# Depends on:
# - yaml2json: ruby -rYAML -rJSON -e 'puts JSON.generate(YAML.load(ARGF))'
# - jq: brew install jq
# - ios: gem install nomad-cli
# - csvfix: brew install csv-fix
# - curl: 

set -e

HockeyAppToken=''
bundleID=''
team=''

baseURL='https://rink.hockeyapp.net/api/2/'

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

#############
# Load a config key from either the project local, or user local config file
loadKey() {
	key=$1
	ret=''
	configFile=.rpjProject
	if [ -f "$configFile" ] && ret=`yaml2json < "$configFile" | jq -e -r "$key"`; then
		echo "$ret"
		return
	elif [ -f "$HOME/$configFile" ] && ret=`yaml2json < "$HOME/$configFile" | jq -e -r "$key"`; then
		echo "$ret"
		return
	fi
	echo ""
}

#################################################
td=$(mktemp -d ${TMPDIR}provisioner.XXXXXX)
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

###############################################################################

HockeyAppToken=`loadKey .hockey.token`
bundleID=`loadKey .bundleID`
team=`loadKey .ios.team`

[ "n" = "n$HockeyAppToken" ] && echo "Missing HockeyAppToken" && exit 1
[ "n" = "n$bundleID" ] && echo "Missing bundleID" && exit 1
[ "n" = "n$team" ] && echo "Missing team" && exit 1

####
###
profileName="RP: $bundleID"

set -x

# TODO: look for profileName, error if doesn't exist.
#ios profiles --team "$team" --format csv | awk ''

# Figure out the Hockey AppID from the bundleID
{
	header="X-HockeyAppToken: $HockeyAppToken"
	url=${baseURL}apps
	filter='.apps | map(select(.bundle_identifier == "'${bundleID}'")) | .[0].public_identifier'

	appID=`curl -s -H "$header" "$url" | jq -r "$filter"`
}
# Fetch the unprovisioned devices for this app from Hockey
{
	header="X-HockeyAppToken: $HockeyAppToken"
	url="${baseURL}apps/${appID}/devices?unprovisioned=1"
	filter='.devices | map(.udid + "," + .name) | .[]'

	curl -s -H "$header" "$url" | jq -r "$filter" > $td/hockey-unprovisioned.csv
}

# Get all of the UDIDs at AppleDev
ios profiles:manage:devices:list --team "$team" --format csv "$profileName" > $td/ios-devices.csv
# TODO remove header line

# Which UDIDs are new?
csvfix join -f 1:2 -inv $td/hockey-unprovisioned.csv $td/ios-devices.csv > $td/to-add-devices.csv

# Which UDIDs are active?
csvfix find -f 3 -s Y $td/ios-devices.csv > $td/ios-profile-devices.csv

# Which UDIDs are not active in profile?
csvfix join -f 1:2 -inv $td/hockey-unprovisioned.csv $td/ios-profile-devices.csv > $td/to-add-profile-devices.csv


# Add UDIDs not there
csvfix exec -r -c "ios devices:add --team \"$team\" \"%1=%2\"" $td/to-add-devices.csv

# Activate UDIDs not active
csvfix exec -r -c "ios profiles:manage:devices:add --team \"$team\" \"$profileName\" \"%1=%2\"" $td/to-add-profile-devices.csv


exit 0
cleanupdir

#  vim: set sw=4 ts=4 :
