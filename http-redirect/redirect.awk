#!/bin/awk -f

# strip trailing CR(\r) before LF(\n)  RFC2616 19.3
/\r$/ { sub(/\r/, "") }

# The first line is the HTTP request type
method == "" {
	method = $1
	request_uri = $2
	version = $3

	next
}

 # a header continuation RFC2616 4.2
/^[ \t]+/ {
	headers[header] = headers[header] $0
}

match($0, /: */) {
  # Sanitize the header name by converting to uppercase and stripping chars
  header = toupper(substr($0, 1, RSTART - 1))

  # not compilant: strip chars we don't like
  # gsub(/[^-_a-zA-Z0-9]/, "", header)
  # RFC2615 2.2: CTL = /[\000-\017\177]/ separators = /[][)(><{} \t@,;:\\"/?=]/
  # header name = token , can have any octet not in separators or control

  # RFC2616 4.2 multiple instances of a header only for comma separated lists
  prior = ""
  if (header in headers)
    prior = headers[header] ", "
  headers[header] = prior substr($0, RSTART + RLENGTH)

   # print "found header >"header"< with content >"headers[header]"<"
}

# end of headers
/^$/ {
	# would read request body here but we don't care

	with_path["GET"] = 1
	with_path["HEAD"] = 1

	CRLF = "\r\n"

	response = "308 Permanent Redirect"
	content = response CRLF CRLF "Access with a https URL" CRLF

	# if the request is absoulute, then parse off host  RFC2616 5.2
	if (match(tolower(request_uri), /http:\/\/[^\/]*/)) {
		host = substr(request_uri, RSTART + 7, RLENGTH - 7)
		# Strip the port if any
		sub(/:.*/,"", host)
		abs_path = substr(request_uri, RSTART + RLENGTH)
		if (abs_path == "")
			abs_path = "/"
	} else if ("HOST" in headers) {
		# If they sent us a Host: header, use it, 
		host = headers["HOST"]
		gsub(/[ \t]/, "", host)
		# Strip the port if any
		sub(/:.*/,"", host)
		abs_path = request_uri
	} else {
		host = ""
		response = "400 Bad Request"
		content = response CRLF CRLF "No Host header given." CRLF
	}
	location = "Location: https://" host

	# RFC 2616 5.1.1 methods are case-sensitive
        if (method in with_path) {
		location = location abs_path
	}

	# Separate output fields (lines) with CRLF but after body add nothing
	OFS = CRLF
	ORS = ""

	content_length = sprintf("Content-Length: %d", length(content))

	print( "HTTP/1.1 " response,
		location,
		content_length,
		"Content-Type: text/plain; charset=UTF-8",
		"X_Frame_Options: DENY",
		"Pragma: no-cache",
		"Cache_Control: no-Store,no-Cache",
		"X-XSS-Protection: 1; mode=block",
		"X-Content-Type-Options: nosniff",
		"Connection: close",
		"",
		content)
	exit 0
}
