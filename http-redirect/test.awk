BEGIN {
	if (!resultfile)
		resultfile="testfile"
	if (!script)
		script = "http-redirect.awk"
	invoke="awk -f " script
	cmd = invoke " > " resultfile
	if (tracefile)
		invoke = invoke " -v tracefile=" tracefile
}

function reportfail(resultfile, expect, request, headers)
{
	print("Testcase FAIL")
	print("Expected to find :" expect)
	print("actual:")
	system("cat " resultfile)
	print("expect:" expect)
	print("input:")
	print("reuest: " request)
	for (h in headers)
		print("headers:" headers[h])
	print("")
	print("FAIL")
	exit(1)
}

function test(code, expect, request, headers)
{
	runtest(cmd, request, headers)
	result = check(resultfile, code, expect, request, headers)
	results[result] = results[result] + 1
	if (result == "FAIL")
		reportfail(resultfile, expect, request, headers)
}

function check(resultfile, code, expect, request, headers)
{
	line = ""
	getline result < resultfile

	while ((getline line < resultfile) > 0)
		if (line ~ /^Location/)
			found = line

	close(resultfile)

	if (code in locations)
	if ((line == expect) && (location ~ " " code " "))
		rc = "PASS"
	else
		rc = fail
	return rc
}

function runtest(cmd, request, headers,	h, OORS)
{
	if (!cmd)
		return
	OORS = ORS
	ORS = "\r\n"

	print(request) | cmd
	for (h in headers)
		print(headers[h]) | cmd
	print("") | cmd
	close(cmd)

	ORS = OORS
}

function add(array, value) {
	counter = counter + 1
	array[counter] = value
}

function mkrequest(method, path, version)
{
	return method " " path " " version
}

BEGIN {
	failingtests()
	passingtests()
	exit(0)
}

function failingtests(headers) {
	host1 = "somewhere.example.com"

	headers[0] = "Host: " host1 ports[port]
	version="HTTP/1.1"
	path="/"
	method="GET"

	othermethods(path, version, headers)
	test(505, "", mkrequest(method, path, "HTTP/1"), headers)
	test(505, "", mkrequest(method, path, "HTTP/2.0"), headers)
	test(505, "", mkrequest(method, path, "http/1.1"), headers)
	junk[0] = "Host: abc_def.example.com"
	test(400, "", mkrequest(method, path, "HTTP/1.1"), junk)
	test(400, "", mkrequest(method, path, "HTTP/1.1"), headers)
	test(404, "", mkrequest(method, "/abc", "HTTP/1.1"), junk)
}

function othermethods(path, version, headers, methods, m)
{
	add(methods, "PUT")
	add(methods, "POST")
	add(methods, "TRACE")
	add(methods, "CONNECT")
	add(methods, "get")
	add(methods, "head")

	for (m in methods)
		test(501, "", mkrequest(methods[m], path, version), headers)
}

function passingtests(headers) {
	method="GET"
	path="/"
	version="HTTP/1.1"

	host1 = "somewhere.example.com"
	host2 = "elsewhere.example.com"
	mkports(ports)

	expect="Location: https://" host1 "/\r"

	request = mkrequest(method, path, version)
	for (port in ports) {
		headers[0] = "Host: " host1 ports[port]
		test(308, expect, request, headers)
	}
	test(308, expect, mkrequest("HEAD", path, version), headers)
	headers[0] = "Host: " host2
	testabsuris(expect, headers, host1, ports)
}

function testabsuris(expect, headers, host, ports)
{
	mkabsuris(uris, host, ports)

	# test with and without path
	for (uri in uris) {
		u = uris[uri]
		test(308, expect, mkrequest(method, u, version), headers)
		test(308, expect, mkrequest(method, u "/", version), headers)
	}
}

function mkports(ports) {
	add(ports, "")
	add(ports, ":")
	add(ports, ":8080")
}

function mkabsuris(uris, host, ports,	schemes, scheme, port)
{
	mkschemes(schemes)

	for (scheme in schemes)
		for (port in ports)
			add(uris, schemes[scheme] "://" host ports[port] )
}

function mkschemes(schemes,	h, t1, t2, p, hs, ts, ps) {
	mkletters(hs, 4, 8)
	mkletters(ts, 5, 4)
	mkletters(ps, 5, 0)

	for (h in hs)
		for (t1 in ts)
			for (t2 in ts)
				for (p in ps)
					add(schemes, hs[h] ts[t1] ts[t2] ps[p])
}

function mkletters(ns, h1, h2)
{
	add(ns, "%" h1 h2)
	add(ns, "%" (h1 + 2) h2)
	add(ns, sprintf("%c", h1 * 16 + h2))
	add(ns, sprintf("%c", (h1 + 2) * 16 + h2))

}

