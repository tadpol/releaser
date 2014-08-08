#!/bin/bash

set -e
set -x

version="${1:?Version Missing}"
project="${2:?Project Missing}"
userpass="${3:?User missing}"
jiraURLBase="${4:?URL Missing}"

cookieJar=$(mktemp -t cookies) || exit 1
jiraURL1="${jiraURLBase}/rest/api/1"
jiraURL="${jiraURLBase}/rest/api/2"

# TODO: Fetch User:pass from KeyChain

# Log in
curl -c $cookieJar -H "Content-Type: application/json" -X POST \
	--user "$userpass" \
	${jiraURL1}/session

# Create New Version
dateShort=$(date +%Y-%m-%d)
verReq=$(jq -n -c -M --arg dateShort "$dateShort" \
	--arg version "$version" --arg project "$project" \
	'{
	"name": $version,
	"archived": false,
	"released": true,
	"releaseDate": $dateShort,
	"project": $project,
}')
curl -b $cookieJar -s -H "Content-Type: application/json" -X POST \
	${jiraURL}/version -d "$verReq"

# Find all unreleased issues.
query="project = $project AND status = Resolved AND fixVersion = EMPTY"
issueReq=$(jq -n -c -M --arg query "$query" '{"jql": $query, "fields": ["key"]}')
issues=$(curl -b $cookieJar -s -X POST -H "Content-Type: application/json" \
	${jiraURL}/search \
	-d "$issueReq" \
	| jq -r '.issues | .[].key')


# Mark issues as fixed by $version
update=$(jq -n -c -M --arg version "$version" \
	'{"update":{"fixVersions":[{"add":{"name":$version}}]}}')

for issue in $issues; do
	curl -b $cookieJar -s -H "Content-Type: application/json" -X PUT \
		${jiraURL}/issue/$issue \
		-d "$update"
done

# Log out
curl -b $cookieJar -H "Content-Type: application/json" -X DELETE ${jiraURL1}/session
rm -f $cookieJar

#  vim: set sw=4 ts=4 :
