# Getting Davis AI to open a Problem from `/error`

> **About this guide:** Dynatrace menus differ between the classic web UI and the newer platform (Dynatrace SaaS with Grail and the **Settings** app). Each step below gives the classic path. On the newer UI you can search for the same setting name with **Ctrl/Cmd + K** or in the Settings app. Default threshold values also change between releases, so check them in your own tenant.

## Does Davis create Problems automatically?

**Yes, but not for each individual error.** Davis is built to alert on *abnormal service behaviour*, not on single exceptions, so that teams don't get flooded with alerts. For every service that OneAgent detects, Davis:

1. Learns a **baseline** of the service's failure rate, response time and load.
2. Opens a Problem when the failure rate rises **significantly above that baseline** and stays high for a while.
3. Applies **over-alerting protection**: it only alerts when the service has enough traffic, a minimum number of requests per minute (around 10 by default), so a few requests on a quiet service don't cause a problem.

So if you run `curl /error` a handful of times on an idle demo VM, you'll see:

| What you do | What Dynatrace shows |
|---|---|
| A few `curl /error` calls | ✅ Failed requests in **Services → dynatrace-demo → Failures**<br>✅ PurePath/trace with `ArithmeticException: / by zero`<br>✅ ERROR lines in **Logs**<br>❌ **No Problem**: too little traffic and too short |
| A sustained failure storm on a service with a learned baseline | ✅ Everything above, plus a **"Failure rate increase"** Problem opened automatically by Davis |

The `/error` HTTP 500s already count as failures. Dynatrace treats server-side HTTP 5xx responses and unhandled exceptions as failed requests by default, so you don't need any code changes.

There are three ways to get a Problem card. Pick based on how predictable the demo needs to be:

| Option | Davis-native? | Setup | Time to Problem | Best for |
|---|---|---|---|---|
| **A. Automatic baseline**, no config | Fully automatic | None, but needs a learned baseline and real traffic | Minutes, once the baseline exists | Showing "Davis works out of the box" |
| **B. Fixed failure-rate threshold** on the service | Yes, service anomaly detection | ~2 min in the UI | ~1–5 min | **Recommended for live demos** |
| **C. Metric event** or **log event** | Yes, a custom Davis event | ~5 min in the UI | ~1–3 min, even for a single error | "Every `/error` must alert" |

---

## Prerequisites (all options)

1. OneAgent is installed on the VM in **Full-Stack** mode and the app was restarted after the install:

   ```bash
   sudo systemctl restart dynatrace-demo
   ```

2. Generate a little traffic, for example `bash scripts/trigger.sh both 5`. Within a couple of minutes the service shows up under **Services**. It is usually named after the Spring app or controller, such as `dynatrace-demo` or `DynatraceDemoApplication`.
3. Open the service and confirm that `/error` requests appear under **Failures** with the `ArithmeticException`. If they don't, fix that first; none of the options below work without it.
4. Make sure you can receive the alert. Problems always show up under **Problems** in the UI. Email or Slack notifications also need an **alerting profile** and a **problem notification**: classic path **Settings → Alerting → Problem alerting profiles** and **Settings → Integration → Problem notifications**.

---

## Option A: Let Davis do it automatically (no configuration)

This is the "out of the box" story. It only works when the service has a baseline and enough traffic.

1. **Build a baseline with healthy traffic.** Davis needs to learn what "normal" looks like for a new service. Give it as much clean traffic as you can before the demo; a few hours is good and longer is better. Run it in the background on the VM or another machine:

   ```bash
   nohup bash scripts/trigger.sh baseline 240 > /tmp/baseline.log 2>&1 &
   ```

   That's about 60 req/min with 0% errors, for 4 hours.
2. **Start the failure storm** at demo time:

   ```bash
   bash scripts/trigger.sh storm 15
   ```

   That's about 120 req/min with about 50% errors, for 15 minutes. It clears the over-alerting minimum by a wide margin, and a jump from 0% to about 50% failures is well past the default relative threshold.
3. Watch **Problems**. A **"Failure rate increase"** problem on the `dynatrace-demo` service should open within a few minutes. Click it to show the root-cause analysis down to the PurePath and the `ArithmeticException`.
4. Stop the storm (Ctrl+C or let it finish). Davis closes the Problem automatically once the failure rate is back to normal.

If nothing appears after about 10 minutes of storm, the baseline probably isn't ready yet (the service is too new) or the traffic is too low. Use Option B.

---

## Option B: Fixed failure-rate threshold (recommended for demos)

This tells Davis to use a fixed threshold for this service instead of waiting for a learned baseline.

1. Go to **Services**, open the **dynatrace-demo** service, then **⋯ (More) → Settings → Anomaly detection**.
   The global equivalent is **Settings → Anomaly detection → Services**. It applies to *all* services, so prefer the per-service setting.
2. Under **Failure rate**:
   - Turn on detection and switch the mode from **Automatic** to **Using fixed thresholds**.
   - **Threshold:** `5` %. Alert when more than 5% of requests fail.
   - **Sensitivity:** `High`.
   - **Over-alerting protection:** lower the minimum requests per minute to `1` and the abnormal-state duration to `1` minute. This step matters on a low-traffic demo VM.
3. Save.
4. Trigger it:

   ```bash
   bash scripts/trigger.sh storm 5
   ```

5. Within about 1–5 minutes, **Problems** shows a **failure rate** problem on `dynatrace-demo`, with the `ArithmeticException` as the root cause.

Change the settings back to **Automatic** after the demo if this is a shared tenant.

---

## Option C: Alert on every error (custom Davis events)

Use this when even a single `/error` call should open a Problem. You can use either C1 or C2, or both.

### C1. Metric event on server-side errors

1. Go to **Settings → Anomaly detection → Metric events → Add metric event**.
   On newer tenants you can also use the **Anomaly Detection** app with a DQL-based detector; the idea is the same.
2. Configure:
   - **Summary:** `dynatrace-demo /error failures`
   - **Type:** Metric key `builtin:service.errors.server.count`
   - **Aggregation:** `Count` or `Sum`
   - **Entity filter:** service name equals `dynatrace-demo` (use the name shown in Services)
   - **Model type:** **Static threshold**
   - **Threshold:** `0`, with the alert condition **Above**
   - **Violating samples:** `1`, **Sliding window:** `3`, **Dealerting samples:** `3`
3. **Event template:**
   - **Title:** `Divide-by-zero errors on dynatrace-demo`
   - **Event type:** **Error**. Error, Availability, Slowdown and Resource events open Problems; Info and Custom annotation events do not.
4. Save, then run:

   ```bash
   bash scripts/trigger.sh error 3
   ```

   A Problem appears within about 1–3 minutes.

### C2. Log event on the ERROR log line

Instead of the request failure, this alerts on the log line the app writes to `/var/log/dynatrace-demo/application.log`.

1. Make sure the log is ingested. Check under **Logs** for `Divide by zero exception caught`. If it isn't there, add `/var/log/dynatrace-demo/application.log` as a log source under **Settings → Log Monitoring → Log ingest rules** (or **Custom log sources**).
2. Create the event:
   - **Classic:** **Settings → Log Monitoring → Events extraction → Add log event**
   - **Newer platform:** **OpenPipeline → Logs → Data extraction → Davis event**
3. Configure:
   - **Matcher:** `matchesPhrase(content, "Divide by zero exception caught")`
   - **Title:** `Divide-by-zero exception in dynatrace-demo`
   - **Event type:** **Error**
4. Run `bash scripts/trigger.sh error 1`. A Problem appears once the log line is ingested and processed, usually within 1–3 minutes.

---

## Suggested demo flow

1. **Healthy state:** `bash scripts/trigger.sh loop` with 20% errors, or `baseline`. Show the service, its requests, and a couple of failed traces. Point out that there is **no Problem**: Davis doesn't alert on background noise.
2. **Incident:** `bash scripts/trigger.sh storm 10`. Show the **Problem card** opening with its impact (the affected service and endpoint), the root cause (`ArithmeticException` in `DynatraceDemoApplication.errorTransaction`), and the linked logs.
3. **Recovery:** stop the storm and show the Problem closing on its own.

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| The service isn't listed | OneAgent was installed after the app started. Restart the app with `sudo systemctl restart dynatrace-demo`. Also check that OneAgent is in Full-Stack mode, not Infrastructure-only. |
| `/error` requests aren't shown as failures | Check **Settings → Server-side service monitoring → Failure detection** in case someone changed the defaults so 5xx is ignored. |
| Failures show but no Problem opens (Option A) | The baseline isn't learned yet, or traffic is under the over-alerting minimum. Use Option B or C. |
| A Problem opens but no email or Slack arrives | The alerting profile filters it out, for example by severity or delay. Check the alerting profile and the problem notification integration. |
| A log event doesn't fire | The log isn't ingested. Search **Logs** for the phrase first, then check the matcher. |
