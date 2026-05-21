{ python3, writeScriptBin }:

writeScriptBin "notify" ''
  #!${python3}/bin/python3
  import json, os, sys, urllib.request

  tier = sys.argv[1] if len(sys.argv) > 1 else sys.exit("Usage: notify <tier> [title] [type] [topic]")
  title = sys.argv[2] if len(sys.argv) > 2 else "Notification"
  ntype = sys.argv[3] if len(sys.argv) > 3 else "info"
  topic = sys.argv[4] if len(sys.argv) > 4 else None
  body = sys.stdin.read()

  url = os.environ.get("NOTIFY_URL", "http://127.0.0.1:5555/notify")
  payload = json.dumps({"tier": tier, "title": title, "type": ntype, "topic": topic, "message": body}).encode()
  req = urllib.request.Request(
      url,
      data=payload,
      headers={"Content-Type": "application/json"},
  )
  try:
      urllib.request.urlopen(req, timeout=10)
  except urllib.error.HTTPError as e:
      sys.exit("notification daemon error: %d %s" % (e.code, e.read().decode()))
  except (urllib.error.URLError, OSError) as e:
      sys.exit("notification daemon connection failed: %s" % e)
''
