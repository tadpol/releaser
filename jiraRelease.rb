#!/usr/bin/ruby
#
require 'uri'
require 'net/http'
require 'json'

project=''
userpass=''
jiraURLBase=''
if File.exist?('.jiraProject') 
	File.open('.jiraProject', 'r') { |file|
		lines = file.readlines
		opts = lines[0].split(' ')
		project = opts[0]
		userpass = opts[1]
		jiraURLBase = opts[2]
	}
end


def printVars(map)
	$stdout.print("\033[1m=:\033[0m ")
	map.each {|k,v|
		$stdout.print("\033[1m#{k}:\033[0m #{v}  ")
	}
	$stdout.print("\n")
end

version = ARGV[0]

printVars({:project=>project,
		   :userpass=>userpass,
		   :version=>version,
		   :jiraURLBase=>jiraURLBase})

username, password = userpass.split(':')
# TODO If password is empty, ask for it.

rest2 = URI(jiraURLBase + '/rest/api/2/')

Net::HTTP.start(rest2.host, rest2.port, :use_ssl=>true) do |http|
	### Create new version
#	request = Net::HTTP::Post.new(rest2 + 'version')
#	request.content_type = 'application/json'
#	request.basic_auth(username, password)
#	request.body = JSON.generate({
#		'name' => version,
#		'archived' => false,
#		'released' => true,
#		'releaseDate' => DateTime.now.strftime('%Y-%m-%d'),
#		'project' => project,
#	})
#
#	response = http.request(request)


	### Find all unreleased issues
	query ="project = #{project} AND (status = Resolved OR status = Closed) AND fixVersion = EMPTY" 
	#query ="project = #{project} AND (status = Resolved OR status = Closed)" 
	request = Net::HTTP::Post.new(rest2 + 'search')
	#puts request.uri
	request.content_type = 'application/json'
	request.basic_auth(username, password)
	request.body = JSON.generate({
		'jql' => query,
		'fields' => [ "key" ]
	})

	response = http.request(request)
	case response
	when Net::HTTPSuccess
		issues = JSON.parse(response.body)
		keys = issues['issues'].map {|item| item['key'] }
		puts keys
	end

	### Mark issues as fixed by version
#	update = JSON.generate({ "update" => { "fixVersions"=>[{"add"=>{"name"=>version}}]} })
#	keys.each do |key|
#		request = Net::HTTP::Put.new(rest2 + ('issue/' + key))
#		request.content_type = 'application/json'
#		request.basic_auth(username, password)
#		request.body = update
#
#		response = http.request(request)
#	end

end

#  vim: set sw=4 ts=4 :
