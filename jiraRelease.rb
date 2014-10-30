#!/usr/bin/ruby
#
require 'uri'
require 'net/http'
require 'json'
require 'date'
require 'yaml'

project=''
userpass=''
jiraURLBase=''
if File.exist?('.jiraProject') 
	File.open('.jiraProject', 'r') do |file|
		$cfg = YAML.load(file)
		project = $cfg['project']
		userpass = $cfg['userpass']
		jiraURLBase = $cfg['jira']
	end
else
	puts 'Missing config file.'
	exit 1
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
		   :jira=>jiraURLBase})

# If password is empty, ask for it.
if userpass.include? ':'
	@username, @password = userpass.split(':')
else
	@username = userpass
	# if darwin
	@password = `security 2>&1 >/dev/null find-internet-password -gs "#{jiraURLBase}" -a "#{@username}"`
	@password.strip!
    @password.sub!(/^password: "(.*)"$/, '\1')
end

@rest2 = URI(jiraURLBase + '/rest/api/2/')

Net::HTTP.start(@rest2.host, @rest2.port, :use_ssl=>true) do |http|
	### Create new version
	request = Net::HTTP::Post.new(@rest2 + 'version')
	request.content_type = 'application/json'
	request.basic_auth(@username, @password)
	request.body = JSON.generate({
		'name' => version,
		'archived' => false,
		'released' => true,
		'releaseDate' => DateTime.now.strftime('%Y-%m-%d'),
		'project' => project,
	})

	response = http.request(request)
	case response
	when Net::HTTPSuccess
		vers = JSON.parse(response.body)
		if !vers['released']
			# Sometimes setting released on create doesn't work.
			# So modify it.
			request = Net::HTTP::Put.new(@rest2 + ('version/' + vers['id'])) 
			request.content_type = 'application/json'
			request.basic_auth(@username, @password)
			request.body = JSON.generate({ 'released' => true })
			response = http.request(request)

		end
	else
		puts "failed on version creation because #{response}"
		exit 1
	end

	def getIssueKeys(http, query)
		request = Net::HTTP::Post.new(@rest2 + 'search')
		request.content_type = 'application/json'
		request.basic_auth(@username, @password)
		request.body = JSON.generate({
			'jql' => query,
			'fields' => [ "key" ]
		})

		response = http.request(request)
		case response
		when Net::HTTPSuccess
			issues = JSON.parse(response.body)
			keys = issues['issues'].map {|item| item['key'] }
			return keys
		else
			return []
		end
	end

	### Find all unreleased issues
	query ="assignee = #{@username} AND project = #{project} AND (status = Resolved OR status = Closed) AND fixVersion = EMPTY" 
	keys = getIssueKeys(http, query)
	printVars({:keys=>keys})

	### Mark issues as fixed by version
	update = JSON.generate({ 'update' => { 'fixVersions'=>[{'add'=>{'name'=>version}}]} })
	keys.each do |key|
		request = Net::HTTP::Put.new(@rest2 + ('issue/' + key))
		request.content_type = 'application/json'
		request.basic_auth(@username, @password)
		request.body = update

		response = http.request(request)
		case response
		when Net::HTTPSuccess
		else
			puts "failed on #{key} because #{response}"
		end
	end

	### Transition to Closed
	# We don't currently use the difference between Resolved and Closed.  So make all Closed.
	query = "project = #{project} AND status = Resolved AND fixVersion != EMPTY" 
	keys = getIssueKeys(http, query)
	printVars({:Rkeys=>keys})

	if !keys.empty?

		# *sigh* Need to transition by ID, buts what's the ID? So look that up
		request = Net::HTTP::Get.new(@rest2 + ('issue/' + keys.first + '/transitions'))
		request.content_type = 'application/json'
		request.basic_auth(@username, @password)
		response = http.request(request)
		case response
		when Net::HTTPSuccess
			trans = JSON.parse(response.body)
			closed = trans['transitions'].select {|item| item['name'] == 'Closed' }
		else
			puts "failed because"
			exit 1
		end

		if closed.empty?
			puts "Cannot find Transition to Closed!!!!"
			exit 2
		end

		printVars({:closedID=>closed[0]['id']})
		
		update = JSON.generate({'transition'=>{'id'=> closed[0]['id'] }})
		keys.each do |key|
			request = Net::HTTP::Post.new(@rest2 + ('issue/' + key + '/transitions'))
			request.content_type = 'application/json'
			request.basic_auth(@username, @password)
			request.body = update

			response = http.request(request)
			case response
			when Net::HTTPSuccess
			else
				puts "failed on #{key} because #{response}"
			end
		end
	end
end

#  vim: set sw=4 ts=4 :
