#!/bin/bash

set -e

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

project=
userpass=
jiraURLBase=
if [ -e ".jiraProject" ];then
	#TODO Fix the format of this.
	read project userpass jiraURLBase < .jiraProject
fi

while getopts ":p:u:U:" opt; do
  case "$opt" in
    p)
	  project=$OPTARG
      ;;
    u)
	  userpass=$OPTARG
      ;;
    U)
	  jiraURLBase=$OPTARG
      ;;
    h)
      cat <<EOF
jiraRelease [options] <version>

Options:
 -h              Help Text
 -p <project>    Set project
 -u <username>   Set Username
 -U <url>        Set Jira URL

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
version="${1:?Version Missing}"

if [ "u$project" = "u" ]; then
	echo Missing project
	exit 1
fi
if [ "u$userpass" = "u" ]; then
	echo Missing Username
	exit 1
fi
if [ "u$jiraURLBase" = "u" ]; then
	echo Missing Jira URL
	exit 1
fi

printVariables project $project userpass $userpass url $jiraURLBase

cookieJar=$(mktemp -t cookies) || exit 1
jiraURL1="${jiraURLBase}/rest/api/1"
jiraURL="${jiraURLBase}/rest/api/2"

# TODO: Fetch User:pass from KeyChain

set -x
# Log in
curl -c $cookieJar -H "Content-Type: application/json" -X POST \
	--user "$userpass" \
	${jiraURL1}/session >/dev/null
# FIXME If login fails, STOP script.

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

# TODO: Transition Issues in Resolved status to Closed.

# Find all unreleased issues.
query="project = $project AND (status = Resolved OR status = Closed) AND fixVersion = EMPTY"
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
curl -b $cookieJar -H "Content-Type: application/json" -X DELETE ${jiraURL1}/session >/dev/null
rm -f $cookieJar

#  vim: set sw=4 ts=4 :
