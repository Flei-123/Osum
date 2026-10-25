#!/usr/bin/env python3
import json
import sys
import urllib.request

KEY = open("/srv/bruecke/admin.key").read().strip()
query = ("?device=" + sys.argv[1]) if len(sys.argv) > 1 else ""
request = urllib.request.Request("http://127.0.0.1:8090/bridge/why" + query, headers={"X-Bridge-Admin": KEY})
for item in json.loads(urllib.request.urlopen(request, timeout=10).read())["devices"]:
    print("%s  [%s]\n  %s" % (item["device_id"], item["state"], item["summary"]))
    print("  last contact: %s  (%s)  %s s ago" % (item["last_contact_utc"], item["last_contact_vienna"], item["ago_s"]))
    if item.get("mac"):
        print("  MAC:", item["mac"])
    for stamp, text in item["events"][-6:]:
        print("   ", stamp, text[:200])
