"""
Stands in for PagerDuty. Appends every alert Alertmanager delivers to a file so
a drill leaves evidence that the page actually arrived, not just that the rule
evaluated true in the Prometheus UI.
"""
import datetime as dt
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = "/var/log/alerts/alerts.jsonl"


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        try:
            payload = json.loads(body)
        except ValueError:
            payload = {"raw": body.decode("utf8", "replace")}
        stamp = dt.datetime.now(dt.timezone.utc).isoformat()
        with open(LOG, "a") as fh:
            for a in payload.get("alerts", [payload]):
                fh.write(json.dumps({
                    "received_at": stamp,
                    "status": a.get("status"),
                    "alertname": a.get("labels", {}).get("alertname"),
                    "severity": a.get("labels", {}).get("severity"),
                    "summary": a.get("annotations", {}).get("summary"),
                }) + "\n")
                print(stamp, a.get("status"), a.get("labels", {}).get("alertname"), flush=True)
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    import os
    os.makedirs("/var/log/alerts", exist_ok=True)
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
