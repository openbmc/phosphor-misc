# Add this fragment to populate the https_resources array when urlfile is set
# To use: awk -f $thisfile -v urlfile=
# url contains  lookup redirect
BEGIN {
if (urlfile)
	while ((getline < urlfile) > 0)
		https_resources[$1] = $2
}
