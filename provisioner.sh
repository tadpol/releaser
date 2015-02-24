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
	HockeyAppToken=`yaml2json < $configFile | jq .hockey.token`
	bundleID=`yaml2json < $configFile | jq .bundleID`
	team=`yaml2json < $configFile | jq .ios.team`
	baseURL=`yaml2json < $configFile | jq .hockey.baseURL`
fi

[ "n" = "n$HockeyAppToken" ] && echo "Missing HockeyAppToken" && exit 1
[ "n" = "n$bundleID" ] && echo "Missing bundleID" && exit 1
[ "n" = "n$team" ] && echo "Missing team" && exit 1

####
###
profileName="RP: $bundleID"

#HappIDfromBundle() {
	header="X-HockeyAppToken: $HockeyAppToken"
	url=${baseURL}apps
	filter=".apps | map(select(.bundle_identifier == '${bundleID}')) | .[0].public_identifier"

	appID=`curl -H $header $url | jq -r $filter`
#}

#devicesToAdd() {
	header="X-HockeyAppToken: $HockeyAppToken"
	url="${baseURL}apps/${appID}/devices?unprovisioned=1"
	filter='.devices | map(.name + "=" + .udid) | .[]'

	udids=`curl -H $header $url | jq -r $filter`
#}

# TODO: look for profileName, error if doesn't exist.
#ios profiles --team "$team" --format csv | awk ''

echo $udids | while read line
do
	ios devices:add "$line"
	ios profiles:manage:devices:add "$profileName" "$line"
done


#  vim: set sw=4 ts=4 :
