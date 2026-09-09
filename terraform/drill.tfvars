# Same rules, shortened so a drill finishes while you are watching. Production
# values live in variables.tf; this file exists so nobody has to wait 26 hours
# to find out whether an alert works.
stale_after_seconds      = 120
data_stale_after_seconds = 180
alert_for                = "15s"
scrape_interval          = "10s"
failure_window           = "5m"
