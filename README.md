# Dynatrace Demo

Author: **Sam JD**

> Intended for demos and testing, not for production use.

A small Spring Boot 3 (Java 17) web app for demonstrating **Dynatrace** monitoring. It exposes two endpoints:

| Endpoint      | Behaviour                                                                 | HTTP |
|---------------|---------------------------------------------------------------------------|------|
| `GET /normal` | Successful transaction, returns JSON                                      | 200  |
| `GET /error`  | Divides by zero, logs an `ERROR` with stack trace, and fails the request with `ArithmeticException` | 500  |

Dynatrace OneAgent picks up the failed `/error` requests as service failures, records the exception in the PurePath, and Log Monitoring sees the `ERROR` lines in `/var/log/dynatrace-demo/application.log`.

A built-in **load generator** runs as its own service and keeps steady traffic flowing: 60 requests/min with about 2% errors by default. Use the `dtdemo-load` command to **spike the error rate** on demand:

```bash
dtdemo-load spike          # 10-minute error spike: 50% errors at 180 req/min
dtdemo-load calm           # back to normal
```

```
.
├── pom.xml
├── setup.sh                         # one-shot install on a VM (build + systemd service)
├── uninstall.sh                     # removes the services
├── DYNATRACE.md                     # how to get Davis to open Problem cards from /error
├── deploy/
│   ├── dynatrace-demo.service       # systemd unit for the app (auto-start on boot)
│   ├── dynatrace-demo.env           # -> /etc/default/dynatrace-demo (JAVA_OPTS, SERVER_PORT)
│   ├── dynatrace-demo-loadgen.service  # systemd unit for the load generator (auto-start on boot)
│   └── dynatrace-demo-loadgen.env      # -> /etc/default/dynatrace-demo-loadgen (baseline load)
├── scripts/
│   ├── loadgen.sh                   # load generator loop (run by the loadgen service)
│   ├── dtdemo-load                  # CLI: status / spike / calm / baseline ... (installed to /usr/local/bin)
│   └── trigger.sh                   # ad-hoc calls to /normal and /error
└── src/main/
    ├── java/com/demo/DynatraceDemoApplication.java
    └── resources/
        ├── application.properties
        └── logback-spring.xml       # console + /var/log/dynatrace-demo/application.log
```

---

## 1. Deploy to a VM

### Requirements
- A Linux VM with systemd: Ubuntu 20.04+/Debian 11+, or RHEL/CentOS Stream/Rocky/Alma 8+/Amazon Linux 2023
- `sudo` access and outbound internet access to install packages
- Inbound TCP **8080** open if you want to reach the app from outside the VM

### Steps

**a) Get the code onto the VM.** You can clone it:

```bash
git clone https://github.com/yahrghrr/dynatrace-demo.git
cd dynatrace-demo
```

Or copy it from your workstation:

```bash
scp -r dynatrace-demo <user>@<vm-ip>:~/
ssh <user>@<vm-ip>
cd ~/dynatrace-demo
```

**b) (Recommended) Install Dynatrace OneAgent first.** If OneAgent is already on the host when the JVM starts, it instruments the app straight away. In Dynatrace, go to **Deploy Dynatrace → Start installation → Linux**, then copy and run the generated `wget … && sudo /bin/sh Dynatrace-OneAgent-Linux.sh …` command on the VM.
If you install OneAgent *after* the app, restart the app so it gets instrumented: `sudo systemctl restart dynatrace-demo`.

**c) Run the setup script:**

```bash
sudo bash setup.sh
```

The script does the following:
1. Installs OpenJDK 17, Maven and curl (apt or dnf/yum).
2. Builds the jar with `mvn clean package`.
3. Creates a system user `dynatrace-demo` and copies the jar to `/opt/dynatrace-demo/dynatrace-demo.jar`.
4. Creates `/var/log/dynatrace-demo/` for the application log.
5. Installs `/etc/systemd/system/dynatrace-demo.service`, **enables it at boot** and starts it.
6. Waits until `/normal` responds.
7. Installs and starts the **load generator** service `dynatrace-demo-loadgen` (also enabled at boot) and the `dtdemo-load` command.

To install without starting the load generator, run `sudo LOADGEN=0 bash setup.sh`. You can start it later with `dtdemo-load start && dtdemo-load enable`.

The script is safe to re-run. To redeploy after a code change, `git pull` and run `sudo bash setup.sh` again.

**d) Open the firewall** (only needed to reach the app from outside the VM).

On Ubuntu with ufw:

```bash
sudo ufw allow 8080/tcp
```

On RHEL-family systems with firewalld:

```bash
sudo firewall-cmd --permanent --add-port=8080/tcp && sudo firewall-cmd --reload
```

On a cloud VM you also need to allow TCP 8080 in the cloud provider's firewall: the Security Group on AWS, the NSG on Azure, or a VPC firewall rule on GCP.

---

## 2. Trigger `/normal` and `/error`

### With curl

From the VM itself:

```bash
curl http://localhost:8080/normal
```

```bash
curl http://localhost:8080/error
```

From your workstation (replace `<vm-ip>`):

```bash
curl http://<vm-ip>:8080/normal
```

```bash
curl http://<vm-ip>:8080/error
```

Expected results:
- `/normal` returns `HTTP 200` with `{"status":"success","message":"Normal transaction completed successfully","result":4200,...}`.
- `/error` returns `HTTP 500` with `{"status":500,"error":"Internal Server Error","exception":"java.lang.ArithmeticException","message":"/ by zero","trace":"..."}`.

To see only the status code, add `-w '%{http_code}\n' -o /dev/null -s`.

You can also open both URLs in a browser.

### With the traffic script

`scripts/trigger.sh` generates repeated traffic, so the requests show up clearly in Dynatrace charts:

```bash
bash scripts/trigger.sh                # 1x /normal + 1x /error
bash scripts/trigger.sh normal 20      # 20x /normal
bash scripts/trigger.sh error 5        # 5x /error
bash scripts/trigger.sh mix 100        # 100 requests, ~20% errors
bash scripts/trigger.sh loop           # one request every 2s until Ctrl+C, ~20% errors
bash scripts/trigger.sh baseline 60    # 60 min of healthy traffic (no errors)
bash scripts/trigger.sh storm 10       # 10 min failure storm (~120 req/min, ~50% errors)
```

To target a remote VM or change the loop speed:

```bash
BASE_URL=http://<vm-ip>:8080 bash scripts/trigger.sh mix 50
```

```bash
DELAY=0.5 bash scripts/trigger.sh loop
```

### With the load generator (continuous traffic + error spikes)

After `setup.sh`, the `dynatrace-demo-loadgen` service is always running and starts at boot. Every second it sends requests to the app, so Dynatrace always has a steady stream of `/normal` plus a little `/error` background noise. This steady traffic gives Davis a baseline to learn from.

Control it with `dtdemo-load`. Commands that change state use `sudo` automatically.

| Command | What it does |
|---|---|
| `dtdemo-load status` | Shows the mode (baseline or spike), the current load, and how many requests succeeded, failed or couldn't reach the app in the last minute |
| `dtdemo-load watch` | Live status that refreshes every 2 s |
| `dtdemo-load spike` | **Error spike** for 10 min: 50% errors at 180 req/min |
| `dtdemo-load spike 15 80 300` | Spike for 15 min with 80% errors at 300 req/min (`spike [MINUTES] [ERROR%] [REQ/MIN]`) |
| `dtdemo-load spike 5 100 120` | 5 minutes of *nothing but* errors |
| `dtdemo-load calm` | Ends the spike now and goes back to baseline |
| `dtdemo-load baseline 120 5` | Changes the steady-state load to 120 req/min with 5% errors (applies within 1 s, no restart needed) |
| `dtdemo-load stop` / `start` / `restart` | Stops or starts the generator |
| `dtdemo-load disable` / `enable` | Turns auto-start at boot off or on |
| `dtdemo-load logs` | Follows the generator's log. It logs a line when the mode changes, and once a minute with the counts |

Notes:
- A spike ends on its own when its time is up. Spikes don't survive a reboot; after a reboot the generator comes back in baseline mode. The baseline settings live in `/etc/default/dynatrace-demo-loadgen`, so changes you make there do survive.
- Example output:

  ```
  $ dtdemo-load status
  service            : active (enabled at boot)
  mode               : SPIKE (8m12s left)
  target             : http://localhost:8080
  load               : 180 req/min, 50% errors
  last full minute   : 91 ok, 89 errors, 0 unreachable
  current minute     : 24 ok, 22 errors, 0 unreachable
  ```

- If the app is down, requests are counted as `unreachable` and the generator keeps trying.
- Don't turn the baseline load too low. Davis's over-alerting protection skips services below a configurable number of requests per minute (see [DYNATRACE.md](DYNATRACE.md), Option B). The default of 60 req/min is plenty.
- Davis only starts baseline-based failure-rate alerting after a service has run for about **34 hours** (20% of a week). Deploy early, or use the fixed threshold in DYNATRACE.md, Option B.

### What you should see in Dynatrace
- **Services →** `dynatrace-demo` (or `DynatraceDemoApplication`): requests to `/normal` and `/error`, and the failure rate going up as `/error` is hit.
- **Distributed traces / PurePaths** for `/error`: an `ArithmeticException: / by zero` thrown in `DynatraceDemoApplication.errorTransaction`.
- **Logs:** `ERROR … [ERROR] Divide by zero exception caught!` from `/var/log/dynatrace-demo/application.log`. If the log isn't ingested automatically, add that path as a custom log source or ingest rule under Log Monitoring in Settings.
- **Problems:** a few `/error` calls do **not** open a Problem by themselves. Davis alerts on a sustained, significant rise in the failure rate with enough traffic, not on single errors. To get a **Problem card**, see **[DYNATRACE.md](DYNATRACE.md)**. It covers relying on the automatic baseline, setting a fixed failure-rate threshold (recommended for demos), and creating a metric or log event that fires on every error.

---

## 3. Auto-start on VM boot

`setup.sh` runs `systemctl enable` for both `dynatrace-demo` (the app) and `dynatrace-demo-loadgen` (the load generator); the load generator starts after the app. `systemctl enable dynatrace-demo` hooks the service into `multi-user.target`, so the app starts automatically every time the VM boots. The unit also:
- waits for `network-online.target`
- restarts the app 10 s after it exits (`Restart=always`)
- runs as the unprivileged `dynatrace-demo` user rather than root

To verify that it's enabled:

```bash
systemctl is-enabled dynatrace-demo
```

That prints `enabled`. Check the load generator the same way with `systemctl is-enabled dynatrace-demo-loadgen`. Then reboot the VM:

```bash
sudo reboot
```

After the VM is back, reconnect and check:

```bash
systemctl status dynatrace-demo
```

```bash
curl http://localhost:8080/normal
```

```bash
dtdemo-load status
```

### Managing the service

| Action | Command |
|---|---|
| Status | `systemctl status dynatrace-demo` |
| Stop / start / restart | `sudo systemctl stop\|start\|restart dynatrace-demo` |
| Disable auto-start | `sudo systemctl disable dynatrace-demo` |
| App log file | `tail -f /var/log/dynatrace-demo/application.log` |
| systemd journal | `journalctl -u dynatrace-demo -f` |
| Change JVM opts / port | edit `/etc/default/dynatrace-demo`, then `sudo systemctl restart dynatrace-demo` |
| Load generator | `dtdemo-load status\|spike\|calm\|stop\|start` (see section 2) |
| Load generator journal | `dtdemo-load logs` or `journalctl -u dynatrace-demo-loadgen -f` |
| Remove everything | `sudo bash uninstall.sh` |

The app log rotates daily and keeps 7 days.

---

## 4. Run locally (without installing)

You need Java 17+ and Maven:

```bash
sudo mkdir -p /var/log/dynatrace-demo && sudo chown $USER /var/log/dynatrace-demo
```

```bash
mvn spring-boot:run
```

Then open http://localhost:8080/normal or http://localhost:8080/error.

---

## Troubleshooting

- **`setup.sh` says the app didn't respond within 60s:** run `journalctl -u dynatrace-demo -n 100 --no-pager`. The most common cause is that something else is already using port 8080 (`sudo ss -ltnp | grep 8080`). To fix it, set `SERVER_PORT=9090` in `/etc/default/dynatrace-demo` and restart the service.
- **The app works on the VM but not from outside it:** check the OS firewall and the cloud firewall or security group (section 1d).
- **The service doesn't appear in Dynatrace:** confirm OneAgent is running (`systemctl status oneagent`), then restart the app with `sudo systemctl restart dynatrace-demo`. OneAgent only instruments Java processes that start *after* it is installed.
- **Why the app's internal error page is at `/internal-error`:** Spring Boot's built-in error page defaults to `/error`, which clashes with the demo's own `GET /error` endpoint. With the default, the handler ran twice per request and returned a Tomcat HTML page. `server.error.path=/internal-error` in `application.properties` moves Spring's page out of the way.

## Author

Created and maintained by **Sam JD**.
