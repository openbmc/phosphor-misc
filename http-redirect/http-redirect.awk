#!/usr/bin/awk -f
#
# A Minimal HTTP/1.1 server to redirect http URIs to https

BEGIN {
	CRLF = "\r\n"
	dquote = "\""

	methods["GET"] = 1
	methods["HEAD"] = 1

	errors[400] = "400 Bad Request"
	errors[404] = "404 Not Found"
	errors[500] = "500 Internal Server Error"
	errors[501] = "501 Not Implemented"
	errors[505] = "505 HTTP Version Not Supported"
	msgtxt[505] = "HTTP/1.1 only"

	# Only forward these resources to the designated paths over https
	https_resources["/"] = "/"
}

# Strip trailing CR(\r) before LF(\n)  RFC2616 19.3
/\r$/ { sub(/\r$/, "") }

# The first line is the HTTP request.
method == "" {
	if ($0 == "")
		next

	method = $1
	request_uri = $2
	version = $3

	validate_request()

	# headers start on the next line
	next
}

# a header continuation line RFC2616 4.2
/^[ \t]+/ {
	# Replace leading, trailing whitespace with space below
	sub(/[ \t]*$/, "")
	sub(/^[ \t]*/, "")
	trace("extend header >"header"< with content >"$0"<")

	headers[header] = headers[header] " " $0
	next
}

# Header lines start with a token and have a : seperator.  Implied LWS is
# allowed around the : seperator.  LWS at the beginning and end can be removed.
match($0, /[ \t]*:[ \t]*/) {
	header = substr($0, 1, RSTART - 1)
	content = substr($0, RSTART + RLENGTH)
	sub(/[ \t]*$/, "", content)

	# Field names are a single token.  LWS is impled allowed at the
	# : seperator.  Any beginning or trailing LWS is not significant.
	if (!is_token(header))
		respond_error(400)

	# Headers are case insensitive, so normalize token to upper case.
	header = toupper(header)

	# RFC2616 4.2 multiple instances of a headers is only valid for for
	# comma separated lists.  Remove any trailing LWS, add ", " seperator.
	prior = ""
	if (header in headers)
		prior = headers[header] ", "
	headers[header] = prior content

	trace("found header >"header"< with content >"headers[header]"<")

	next
}

# A blank line marks the end of the headers.
/^$/ {
	# Could read request body here but we don't care.
	trace("end of request headers")
	validate_request()

	validate_uri(request_uri, split_uri)
	host = find_host()
	path = split_uri["path"]
	validate_path_and_respond(host, path)

	next
}

# Should never get here: in headers a line without an indent nor a : is invalid.
{
	trace("Unparsed header line : >" $0 "<")

	header = $0
	headers[header] = ""

	# check HTTP version before bad request error response
	validate_request()
	respond_error(400)
	next
}

############################################################

function validate_request()
{
	trace("version >"version"<")
	trace("uri >"request_uri"<")
	trace("method >"method"<")
	if (version !~ /HTTP\/0*1[.][0-9]+$/)	# Support leading 0s, two halves
		respond_error(505)		# Version Not Supported
	if (bad_uric(request_uri))
		respond_error(400)		# Bad Request (bogus encoding)
	if (!method in methods)
		respond_error(501)		# Not Implemented
}

function validate_uri(request_uri, split_uri)
{
	split_url_components(request_uri, split_uri)
	trace(dump_split_url(split_uri))

	if (!is_http_request_uri(split_uri))
		respond_error(400)		# Bad Request (didn't parse)
}

function find_host()
{
	# RFC2616 5.2
	if (!("HOST" in headers))
		respond_error(400)

	host = headers["HOST"]
	trace("initial host is >" host "<")
	if ("host" in split_uri)
		host = split_uri["host"]
	else if (match(host, /:[0-9]*$/))
		# RFC 2616 14.23  Host header is host:port of URI
		# RFC 2616 3.2.2 port may be not given or empty
		host = substr(host, 1, RSTART - 1)
	trace("prioritized host is >" host "<")

	# A very relaxed check for domainlabel or IPv4.
	if (host !~ /^[\[\]:0-9a-zA-Z.-]+$/)
		respond_error(400)
	trace("host passed regex")

	return host
}

function validate_path_and_respond(host, path)
{
	lookup = unescape(path)

	# URIs must be unescaped before compare, but forwarded unmodified
	trace("lookup path is >" lookup "<")

	# Translate our whitelisted URI
	if (lookup in https_resources) {
		newpath = "https://" host https_resources[lookup]
		trace("Redirecting to >" newpath "<\n")
		response = "308 Permanent Redirect"
		reason = "Access with a https:// URL"
		content = response CRLF newpath CRLF CRLF reason CRLF
		respond_and_exit(response, content, newpath)
	}

	# Rather than be an open redirector, return Not Found
	respond_error(404)			# Not Found

	# get noisy response if we didn't exit above
	trace("Failed to exit after response!")
	exit 3
}

function is_token(token)
{
	# US ASCII (0-127) excluding CTL (000-037, 177, SP (040), seperators
	if (match(token, /[^\041-\176]/) ||
		match(token, /[()<>@,;:\/[]?=\{\}" \t/))
		return 0

	return 1
}

# unreserved, reserved, or encoded.
function bad_uric(URI)
{
	# hide encoded
	gsub(/%[0-9a-fA-F][0-9a-fA-F]/, "", URI)

	# fail if remaining characters are not in (mark alpha numeric reserved)
	if (URI ~ /[^-_.!~*'()a-zA-Z0-9";\/?:@&=+$,\[\]]/)
		return 1
	return 0
}

# We only expect a few chars so call index vs building table hex2int[chr]
function hex2dec(chr)
{
	v = index("0123456789abcdef", tolower(chr))
	if (v)
		return v - 1

	trace("bad hex2dec character >" chr "<")
	# bad_uric should have caught input
	respond_error(500)			# Internal Server Error
}

# Do % hex hex -> code replacement
function unescape(input,  out)
{
	i = index(input, "%")

	if (i == 0)
		return input

	out = ""
	while (i) {
		code = (hex2dec(substr(input, i + 1, 1)) * 16 + \
			hex2dec(substr(input, i + 2, 1)))
		out = out substr(input, 1, i - 1) sprintf("%c", code)
		input = substr(input, i + 3)
		i = index(input, "%")
	}
	return out input
}

# With cues from RFC2396 appendix B etal
function split_url_components(url, components)
{
	if (match(url, /#/)) {
		components["frag"] = substr(url, RSTART + 1)
		url = substr(url, 1, RSTART - 1)
	}

	if (match(url, /\?/)) {
		components["query"] = substr(url, RSTART + 1)
		url = substr(url, 1, RSTART - 1)
	}

	if (match(url, /^[^:\/?#]+:/)) {
		components["scheme"] = substr(url, 1, RLENGTH - 1) ;
		url = substr(url, RLENGTH + 1)
	}

	# Maybe return early:  Separate the path from the authority.
	if (substr(url, 1, 2) != "//") {
		components["path"] = url;
		return
	} else if (match(substr(url, 3), "/")) {
		components["path"] = substr(url, 3 + RSTART - 1) # include the /
		url = substr(url, 3, RSTART - 1)
	} else {
		url = substr(url, 3)
	}

	# Parse userinfo@host:port
	if (match(url, /@/)) {
		userinfo = substr(url, 1, RSTART - 1)
		url = substr(url, RSTART + 1)

		components["userinfo"] = userinfo
		if (match(userinfo, ":")) {
			# NOT RECOMMENDED
			components["password"] = substr(userinfo, RSTART + 1)
			userinfo = substr(userinfo, RSTART - 1)
		}
		components["user"] = userinfo;
	}
	if (match(url, ":") && !match(url, "^[][]")) {
		# port is numeric or empty
		components["port"] = substr(url, RSTART + 1)
		url = substr(url, 1, RSTART - 1)
	}
	if (url)
		components["host"] = url
}

function dump_field_if_present(key, array)
{
	r=""
	if (key in array)
		r=sprintf(dquote key dquote": "dquote"%s"dquote"\n", array[key])
	return r
}

function dump_split_url(components)
{
	r= "split_url = {\n"
	r=r dump_field_if_present("scheme", components)
	r=r dump_field_if_present("userinfo", components)
	r=r dump_field_if_present("host", components)
	r=r dump_field_if_present("port", components)
	r=r dump_field_if_present("path", components)
	r=r dump_field_if_present("query", components)
	r=r dump_field_if_present("frag", components)
	r=r "}\n"

	return r
}

# RFC2616 3.2.2
function is_http_request_uri(split_url)
{
	# Fragments are handled by the client, user info is not on the wire.
	if (("frag" in split_url) || ("userinfo" in split_url))
		return 0
	trace("not frag, no user")

	# If absoluteURI, it will have both, if abs_path neither
	if (("scheme" in split_url) != ("host" in split_url))
		return 0
	trace("scheme host ok")

	if ("scheme" in split_url) {
		trace("original scheme is:  >" split_url["scheme"] "<")
		scheme = unescape(split_url["scheme"])
		trace("unescaped scheme is: >" scheme "<")
		# HTTP 2616 3.2.3 scheme MUST be case insensitive
		if (tolower(scheme) != "http")
			return 0
		trace("scheme is http")

		# 3.2.2 http always has a net_url host authority, host not empty
		if (!("host" in split_url))
			return 0
		trace("host present >" split_url["host"] "<")

		# Authority name not empty
		if (split_url["host"] == "")
			return 0

		# 2616 3.2.3 empty path is /    sole fixup: scheme://hostport
		if (split_url["path"] == "")
			split_url["path"] = "/"
	}

	trace("path is now >" split_url["path"] "<")
	trace("first path char is >" substr(split_url["path"], 1, 1) "<")

	# The path must be absolute.
	return substr(split_url["path"], 1, 1) == "/"
}

function location_header_ok(URI)
{
	# policy: all response URLs shall be https
	if (substr(URI, 1, 8) != "https://")
		return 0

	# The URL shall have been encoded
	if (bad_uric(URI))
		return 0

	return 1
}

function response_needs_location(response)
{
	return (response ~ /^3/) || (response ~ /^201/)
}

function respond_and_exit(response, content, URI)
{
	# If the URI is given validate it should be sent and prepare header
	if (location_header_ok(URI) && response_needs_location(response))
		location = CRLF "Location: " URI
	else
		location = ""

	if (response !~ /^[1-5][0-9][0-9] /) {
		trace( "DEBUG: response '" response "'\n" )
		trace( "DEBUG: content: '" content"'\n" )
		response = "500 Internal Server Error"
		content = response CRLF
	}

	content_length = sprintf("Content-Length: %d", length(content))

	# RFC 2616 9.4 HEAD MUST NOT return message body.
	if (method == "HEAD") {
		content = ""
	}

	# Final trace before changing line endings visual seperation
	trace("")

	# Respond with protocol and response, prepared location from above,
	# and then the fixed response headers.

	# Separate header lines with CRLF but add nothing after the body
	OFS = CRLF
	ORS = ""

	print( "HTTP/1.1 " response location,
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

	# We told client to close the connection; also close this end.
	exit 0
}

# Respond with an error and close the connection to avoid synchronization.
function respond_error(num)
{
	if (num in errors)
		if (num in msgtxt)
			respond_and_exit(errors[num], msgtxt[num] CRLF)
		else
			respond_and_exit(errors[num], errors[num] CRLF)
	else
		respond_and_exit(errors[500], "unknown error number " num CRLF)
}

# To generate a trace, set the tracefile or tracecmd variable with awk -v
function trace(string)
{
	if (tracefile)
		print(string) > tracefile
	if (tracecmd)
		print(string) | tracecmd
}



###########################################################

# BEGIN {
# # The character classes as defined in rfc 2396
# reserved = ";/?:@&=+$,"
# mark = "-_.!~*'()"
# digit = "0123456789"
# lower = "abcdefghijklmnopqrstuvwxyz"
# upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
# unreserved = lower upper digit mark
#
# control = 00-1F, 7F
# space = " "
# delims = "<>#%" dquote
# unwise = "{}|\^[]`"
# }

################################################################

# Build a table to convert a hex character to an integer
function make_hex2int(hex2int) {
	for(i =0; i < 10; i++)
		hex2int[i] = i
	for (i=10 ; i < 16; i++) {
		hex2int[substr("ABCDEF", i - 10 + 1, 1)] = i
		hex2int[substr("abcdef", i - 10 + 1, 1)] = i
	}
}
