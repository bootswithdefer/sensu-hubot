# Description:
#   Sensu events
#
# Dependencies:
#   None
#
# Configuration:
#   SENSU_API_HOST
#   SENSU_API_PORT
#   SENSU_API_USER
#   SENSU_API_PASSWORD
#
# Commands:
#   sensu events summarize - returns a summary of the current events
#   sensu events filter severity <severities> - returns current events with <severities>
#   sensu events filter subscription <subscriptions> - returns current events for clients with <subscriptions>
#
# Author:
#   portertech

query_sensu_api = (msg, uri, callback) ->
  host = process.env.SENSU_API_HOST
  port = process.env.SENSU_API_PORT
  user = process.env.SENSU_API_USER
  pass = process.env.SENSU_API_PASSWORD

  auth = 'Basic ' + new Buffer(user + ':' + pass).toString('base64')
  msg.http("http://#{host}:#{port}/#{uri}")
    .headers(Authorization: auth, Accept: 'application/json')
    .get() (err, res, body) ->
      switch res.statusCode
        when 200
          data = JSON.parse(body)
          callback(data)
        when 401
          msg.send 'Incorrect API credentials!'
        when 404
          msg.send 'The resource you are looking for does not exist.'
        else
          msg.send 'Something went wrong, you should check on the Sensu API!'

summarize_events = (events) ->
  flapping = 0
  unknown = 0
  critical = 0
  warning = 0
  for event in events
    flapping += 1 if event.flapping
    switch event.status
      when 2
        critical += 1
      when 1
        warning += 1
      when 0
      else
        unknown += 1
  "unknown: #{unknown} - critical: #{critical} - warning: #{warning} - #{flapping} are flapping"

event_severity = (event) ->
  ['ok', 'warning', 'critical'][event.status] || 'unknown'

format_event = (event) ->
  severity = event_severity(event)
  output_lines = event.output.split("\n")
  output = output_lines[0]
  output += ' ...' if output_lines.length > 1 and not not output_lines[1]
  "#{severity} #{event.client}/#{event.check} #{output}"

formatted_event_list = (events) ->
  list = ''
  if events.length > 0
    for event in events
      list += format_event(event)
      list += "\n"
  else
    list += 'no matching events'
  list

client_dictionary = (msg, callback) ->
  query_sensu_api msg, 'clients', (clients) ->
    dictionary = clients.reduce (result, client) ->
      result[client.name] = client
      result
    , {}
    callback(dictionary)

filter_events = (msg, events, type, filters, callback) ->
  selected = []
  switch type
    when 'severity'
      for event in events
        severity = event_severity(event)
        selected.push(event) if severity in filters
      callback(selected)
    when 'subscription'
      client_dictionary msg, (clients) ->
        for event in events
          select = true
          for subscription in filters
            if subscription not in clients[event.client].subscriptions
              select = false
              break
          selected.push(event) if select
        callback(selected)

module.exports = (robot) ->
  robot.hear /sensu events summarize/i, (msg) ->
    query_sensu_api msg, 'events', (events) ->
      msg.send summarize_events(events)
  robot.hear /sensu events filter (\S+) (\S+)/i, (msg) ->
    type = msg.match[1]
    filters = msg.match[2].split(',')
    query_sensu_api msg, 'events', (events) ->
      filter_events msg, events, type, filters, (selected) ->
        msg.send formatted_event_list(selected)
