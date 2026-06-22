import json
import logging
import os
import urllib.request
import urllib.error

import apprise
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

CONFIG_PATH = os.environ.get(
    "NOTIFICATION_DAEMON_CONFIG",
    "/etc/notification-daemon/config.json",
)
HOST = os.environ.get("NOTIFICATION_DAEMON_HOST", "127.0.0.1")
PORT = int(os.environ.get("NOTIFICATION_DAEMON_PORT", "5555"))
NTFY_PRIORITY_MAP = {
    "info": 1,
    "success": 2,
    "warning": 3,
    "failure": 4,
    "critical": 5,
    "music": 2,
    "system": 3,
}

TOPIC_FALLBACK = {
    "info": "system",
    "success": "system",
    "warning": "system",
    "failure": "services",
    "critical": "services",
    "music": "music",
    "system": "system",
}
app = FastAPI(title="notification-daemon")
logger = logging.getLogger("notification-daemon")

TYPE_MAP = {
    "info": apprise.NotifyType.INFO,
    "success": apprise.NotifyType.SUCCESS,
    "warning": apprise.NotifyType.WARNING,
    "failure": apprise.NotifyType.FAILURE,
    "critical": apprise.NotifyType.FAILURE,
}


def load_config():
    try:
        with open(CONFIG_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as exc:
        logger.error("failed to load config: %s", exc)
        return None


def build_notify_url(bot_token: str, chat_id: str, topic_id: str) -> str:
    return "tgram://%s/%s:%s" % (bot_token, chat_id, topic_id)


def _self_notify(config, title, message):
    """Log to stderr and push via ntfy direct. Never recurses."""
    logger.error("self-notify: %s - %s", title, message)
    if not config:
        return
    ntfy_cfg = config.get("ntfy")
    ntfy_url = (ntfy_cfg or {}).get("server_url")
    if not ntfy_url:
        return
    token = None
    ntf_path = (ntfy_cfg or {}).get("token_file")
    if ntf_path:
        try:
            token = open(ntf_path).read().strip()
        except Exception:
            pass
    headers = {"Title": title, "Priority": "5", "Tags": "warning"}
    if token:
        headers["Authorization"] = "Bearer %s" % token
    url = "%s/daemon-errors" % ntfy_url.rstrip("/")
    try:
        urllib.request.urlopen(
            urllib.request.Request(url, data=message.encode(), headers=headers),
            timeout=10,
        )
    except Exception:
        pass


def _send_apprise(config, labelled_title, message, notify_type, tier):
    topics = config.get("topics", {})
    topic_id = topics.get(tier)
    if not topic_id:
        return False, "unknown tier '%s'" % tier
    chat_id = config.get("chat_id")
    token_file = config.get("token_file")
    if not chat_id or not token_file:
        return True, None
    try:
        with open(token_file) as f:
            bot_token = f.read().strip()
    except (FileNotFoundError, PermissionError) as exc:
        return False, "cannot read token file: %s" % exc
    url = build_notify_url(bot_token, chat_id, topic_id)
    apobj = apprise.Apprise()
    apobj.add(url)
    apprise_type = TYPE_MAP.get(notify_type, apprise.NotifyType.INFO)
    if not apobj.notify(
        title=labelled_title, body=message or "(no body)", notify_type=apprise_type
    ):
        return False, "apprise dispatch returned False"
    return True, None


def _send_ntfy(
    server_url, topics, token, tier, title, message, notify_type, topic=None
):
    topic_name = topic or TOPIC_FALLBACK.get(tier, "system")
    ntfy_topic = topics.get(topic_name)
    if not ntfy_topic:
        logger.warning(
            "ntfy: unknown topic '%s' (known: %s)", topic_name, ", ".join(topics.keys())
        )
        return False, "unknown ntfy topic '%s'" % topic_name
    url = "%s/%s" % (server_url.rstrip("/"), ntfy_topic)
    priority = NTFY_PRIORITY_MAP.get(notify_type, 3)
    headers = {
        "Title": title,
        "Priority": str(priority),
        "Tags": notify_type,
    }
    if token:
        headers["Authorization"] = "Bearer %s" % token
    data = (message or "(no body)").encode()
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        resp = urllib.request.urlopen(req, timeout=10)
        logger.info(
            "ntfy sent: topic=%s ntfy_topic=%s tier=%s priority=%d status=%d",
            topic_name,
            ntfy_topic,
            tier,
            priority,
            resp.status,
        )
        return True, None
    except urllib.error.HTTPError as exc:
        body = exc.read().decode()
        logger.error("ntfy HTTP %d: %s", exc.code, body)
        return False, "ntfy HTTP %d: %s" % (exc.code, body)
    except urllib.error.URLError as exc:
        logger.error("ntfy unreachable: %s", exc.reason)
        return False, "ntfy unreachable: %s" % exc.reason


def _dispatch_notification(config, tier, title, message, notify_type, topic):
    labelled_title = "[%s] %s" % (topic or TOPIC_FALLBACK.get(tier, "general"), title)

    apprise_ok = apprise_err = None
    ntfy_ok = ntfy_err = None

    apprise_ok, apprise_err = _send_apprise(
        config, labelled_title, message, notify_type, tier
    )
    if apprise_err:
        logger.error("apprise: %s", apprise_err)

    ntfy_cfg = config.get("ntfy")
    if ntfy_cfg and ntfy_cfg.get("server_url") and ntfy_cfg.get("topics"):
        ntfy_token = None
        ntf = ntfy_cfg.get("token_file")
        if ntf:
            try:
                ntfy_token = open(ntf).read().strip()
            except (FileNotFoundError, PermissionError) as exc:
                logger.warning("cannot read ntfy token: %s", exc)
        ntfy_ok, ntfy_err = _send_ntfy(
            server_url=ntfy_cfg["server_url"],
            topics=ntfy_cfg["topics"],
            token=ntfy_token,
            tier=tier,
            title=labelled_title,
            message=message,
            notify_type=notify_type,
            topic=topic,
        )
        if ntfy_err:
            logger.error("ntfy: %s", ntfy_err)

    errors = []
    if apprise_err:
        errors.append("apprise: %s" % apprise_err)
    if ntfy_err:
        errors.append("ntfy: %s" % ntfy_err)

    if errors:
        _self_notify(config, "dispatch failure: %s" % title, "; ".join(errors))

    return errors


@app.get("/health")
async def health():
    config = load_config()
    if config is None:
        return JSONResponse(
            {"status": "error", "detail": "config not found"}, status_code=503
        )
    return {"status": "ok"}


@app.post("/notify")
async def notify(request: Request):
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "invalid JSON body"}, status_code=400)

    tier = body.get("tier", "info")
    title = body.get("title", "Notification")
    message = body.get("message", "")
    notify_type = body.get("type", "info")
    topic = body.get("topic")

    config = load_config()
    if config is None:
        return JSONResponse({"error": "notification config not found"}, status_code=503)

    errors = _dispatch_notification(config, tier, title, message, notify_type, topic)

    if errors:
        return JSONResponse({"status": "partial", "errors": errors}, status_code=500)

    return {"status": "ok"}


@app.post("/debug/test-notify")
async def test_notify():
    config = load_config()
    if config is None:
        return JSONResponse({"error": "notification config not found"}, status_code=503)

    errors = _dispatch_notification(
        config,
        tier="info",
        title="[test] notification pipeline",
        message="Daemon debug test notification",
        notify_type="info",
        topic="system",
    )

    if errors:
        return JSONResponse({"test_result": "fail", "errors": errors}, status_code=500)
    return JSONResponse({"test_result": "ok"})
