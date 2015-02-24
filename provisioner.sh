#!/bin/sh
#
# For an App, this takes UDIDs from HockeyApp and puts them into Apple Developer account.
# Updating a profile for testing.
#
# Both the HockeyApp entry and the AppleDev Profile must be created first.

# Depends on:
# - yaml2json: npm install -g yaml2json
# - jq: brew install jq
# - ios: gem install nomad-cli
# - curl: 

set -e

HockeyAppToken=''
bundleID=''
team=''

baseURL='https://rink.hockeyapp.net/api/2/'
configFile=.rpjProject

######
# Load project overrides of the above configs 
if [ -f "$configFile" ]; then
	HockeyAppToken=`yaml2json < $configFile | jq -r .hockey.token`
	bundleID=`yaml2json < $configFile | jq -r .bundleID`
	team=`yaml2json < $configFile | jq -r .ios.team`
fi

[ "n" = "n$HockeyAppToken" ] && echo "Missing HockeyAppToken" && exit 1
[ "n" = "n$bundleID" ] && echo "Missing bundleID" && exit 1
[ "n" = "n$team" ] && echo "Missing team" && exit 1

####
###
profileName="RP: $bundleID"

# TODO: look for profileName, error if doesn't exist.
#ios profiles --team "$team" --format csv | awk ''

#HappIDfromBundle() {
	header="X-HockeyAppToken: $HockeyAppToken"
	url=${baseURL}apps
	filter='.apps | map(select(.bundle_identifier == "'${bundleID}'")) | .[0].public_identifier'

	appID=`curl -s -H "$header" "$url" | jq -r "$filter"`
#}

#devicesToAdd() {
	header="X-HockeyAppToken: $HockeyAppToken"
	url="${baseURL}apps/${appID}/devices?unprovisioned=0"
	filter='.devices | map(.name + "=" + .udid) | .[]'

	#udids=`curl -s -H "$header" "$url" | jq -r "$filter"`
curl -s -H "$header" "$url" | jq -r "$filter" | while read line
do
	echo ::$line::
	ios devices:add --team "$team" "$line"
	ios profiles:manage:devices:add --team "$team" "$profileName" "$line"
done

# TODO: ok, looks like we pretty much need to work by diffing the two. 
# So grab devices from Hockey, grab devices from ios, and compare.
# Then back feed to the new ones.

#  vim: set sw=4 ts=4 :
