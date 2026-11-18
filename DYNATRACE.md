# Getting Davis AI to open a Problem from `/error`

> **About this guide:** checked against the Dynatrace documentation at docs.dynatrace.com in November 2026. Each step gives the **latest Dynatrace** path (the Settings app with *Process and contextualize* and *Analyze and alert* in the left panel) first, and the **Dynatrace Classic** path second. Menu names change between releases; if a label differs in your tenant, use **Search settings**.

## Does Davis create Problems automatically?

**Yes, but not for each individual error.** Davis alerts on *abnormal service behaviour*, not on single exceptions. For every service OneAgent detects, Dynatrace watches for four anomaly types: response time degradation, **failure rate increase**, load drops and load spikes. Each one raises its own problem.

For the failure rate, the default mode is **automated baselining**. According to the docs:

1. **Learning takes time.** Dynatrace calculates a first baseline about **2 hours** after it first detects a service. Failure-rate alerting only starts once the service has also been running for **at least 20% of a week, about 34 hours**. A brand-new demo service therefore can't raise a baseline-based failure-rate problem for roughly its first day and a half.
2. **The increase must be significant.** An alert needs the failure rate to exceed **both** a relative and an absolute threshold above the baseline.
3. **The increase must last.** Baselines are evaluated in 5-minute and 15-minute sliding windows, and a baseline event lasts at least 5 minutes, so short blips don't alert.
4. **The service needs enough traffic.** Over-alerting protection excludes services below a configurable minimum number of actions (requests) per minute.

So if you run `curl /error` a handful of times on a new, idle demo VM, you'll see:

| What you do | What Dynatrace shows |
|---|---|
| A few `curl /error` calls | ✅ Failed requests on the service<br>✅ A trace with `ArithmeticException: / by zero`<br>✅ ERROR lines in **Logs**<br>❌ **No Problem**: not enough traffic, too short, and no baseline yet |
| A sustained failure storm (`dtdemo-load spike`) on a service that has run for 34 hours or more | ✅ Everything above, plus a **failure rate increase** Problem opened automatically by Davis |

> **The load generator does most of the work.** `setup.sh` installs a load generator service that runs all the time and starts at boot. It sends 60 req/min with about 2% errors, which gives Davis steady traffic to learn from. `dtdemo-load spike` then raises the error rate (50% errors at 180 req/min for 10 minutes by default) to cause the incident. See the README, section 2, for all the commands.

The `/error` HTTP 500s already count as failures. By default Dynatrace treats HTTP 500–599 responses and exceptions that abort a service call as server-side failures, so you don't need any code changes.

There are three ways to get a Problem card. Pick based on how soon you need it and how predictable it must be:

| Option | How it works | Setup | Ready to alert | Best for |
|---|---|---|---|---|
| **A. Automatic baseline**, no config | Davis's built-in failure-rate detection | None | After ~34 h of traffic | Showing "Davis works out of the box" |
| **B. Fixed failure-rate threshold** | Same built-in detection, with a fixed % instead of a baseline | ~2 min in the UI | Immediately | **Live demos on a fresh VM** |
| **C. Custom alert** or **log event** | Your own Davis event on a metric or a log line | ~5 min in the UI | Immediately | A threshold you control, or alerting on every single error |

---

## Prerequisites (all options)

1. OneAgent is installed on the VM in **Full-Stack** mode and the app was restarted after the install:

   ```bash
   sudo systemctl restart dynatrace-demo
   ```

2. Check that the load generator is sending traffic with `dtdemo-load status`. Within a couple of minutes the service shows up under **Services**. It is usually named after the Spring app or controller, such as `dynatrace-demo` or `DynatraceDemoApplication`. Use the name you see there everywhere this guide says `dynatrace-demo`.
3. Open the service and confirm that `/error` requests show as failures with the `ArithmeticException`. If they don't, fix that first; none of the options below work without it.
4. Make sure you can receive the alert. Problems always show up under **Problems**. Email or Slack notifications also need an **alerting profile** and a **problem notification** integration; search for them in Settings.

---

## Option A: Let Davis do it automatically (no configuration)

This is the "out of the box" story. It only works once the service has learned a baseline.

1. **Let the baseline build.** Deploy the VM **at least 1½ days before the demo**; failure-rate alerting with automated baselining starts only after the service has run for 20% of a week, about 34 hours. A full week is better, because 7 days is the default reference period. The load generator keeps traffic flowing the whole time. Check it with:

   ```bash
   dtdemo-load status
   ```

2. **Start the spike** at demo time:

   ```bash
   dtdemo-load spike 15
   ```

   That's 180 req/min with 50% errors for 15 minutes. A jump from about 2% to about 50% failures clears both the relative and absolute thresholds, and lasts well beyond the 5-minute evaluation window.
3. Watch **Problems**. A **failure rate increase** problem on the `dynatrace-demo` service should open within about 5–15 minutes. Open it to show the root-cause analysis down to the trace and the `ArithmeticException`.
4. End the spike with `dtdemo-load calm`, or let it time out. Davis closes the Problem automatically once the failure rate is back to normal.

If nothing appears after 15 minutes of spike, the service is probably still too new. Use Option B.

> **Note:** if you redeploy with big changes and get unwanted alerts, the services alert settings have a **Reset** button that throws away the old reference period and starts learning again.

---

## Option B: Fixed failure-rate threshold (recommended for demos)

This switches failure-rate detection from *automatically* (baseline) to *using fixed thresholds*. That alerts when the failure rate goes above a set percentage, so you don't have to wait ~34 hours for a baseline.

1. Open the failure-rate settings. You can change them **for this service only**, which is recommended, or for **all services**:
   - **Only this service:** go to **Services Classic**, select the `dynatrace-demo` service, open the **browse menu (…) → Settings → Anomaly detection**, and turn off **Use global anomaly detection settings**. This is the route the docs give.
     The service-level Settings page in your screenshot, with **Analyze and alert → Alerts**, may offer the same **Services** settings for just this service. If it does, you can use it instead.
   - **All services** (affects everything in the environment):
     - Latest: **Settings → Analyze and alert → Alerts → Services**
     - Classic: **Settings → Anomaly detection → Services**
2. Under **Failure rate increase**:
   - Turn on **Detect increase in failure rate** and choose **using fixed thresholds**.
   - **Threshold:** `10` %. That's well above the generator's ~2% background errors and well below a spike's 50%. Dynatrace alerts if this rate is exceeded during any 5-minute period.
   - **Sensitivity:** **High**. The docs describe this as "no statistical confidence is used; each violation triggers an alert". Medium and Low wait for more evidence.
   - **Optional, to avoid over-alerting:** set the actions/min below which a service counts as low-load and is skipped to `1`, so the low-traffic demo service is always evaluated. Set how long the service must stay abnormal to `1` minute.
3. Save.
4. Trigger it:

   ```bash
   dtdemo-load spike 10
   ```

5. Within about 5–10 minutes, **Problems** shows a **failure rate increase** problem on `dynatrace-demo`, with the `ArithmeticException` as the root cause.

After the demo, switch back to the global settings (or to **automatically**) if this is a shared tenant.

---

## Option C: Custom alerts and log events

Use this when you want a custom alert with a threshold you control. You can use either C1 or C2, or both.

> **The background errors matter here.** With the load generator's default ~2% errors (about 1 error per minute), a threshold of "more than 0 errors" would keep a Problem open permanently. You have two choices:
> - **Alert on a spike (recommended):** use a threshold of **more than 10 failures per minute**, as below. The baseline gives about 1 per minute and `dtdemo-load spike` gives about 90 per minute.
> - **Alert on every single error:** first turn off the background errors with `dtdemo-load baseline 60 0`, then use a threshold of `0`, and trigger with `bash scripts/trigger.sh error 1`.

Only some event types open a Problem: **Availability, Error, Slowdown, Resource and Custom alert** events do. **Info** and **Warning** events never do.

### C1. Custom alert on failed requests

**Latest Dynatrace: custom alert in Settings**

The **Anomaly Detection** app is deprecated; the docs recommend creating custom alerts in Settings instead.

1. Test this query in a **Notebook** first. With the load generator running it should return a small series of about 1 per minute, and a large one of about 90 per minute during `dtdemo-load spike`:

   ```
   timeseries failures = sum(dt.service.request.failure_count), by:{dt.service.name}, interval:1m
   | filter dt.service.name == "dynatrace-demo"
   ```

   `dt.service.request.failure_count` is the built-in Grail metric for failed requests. If the query returns nothing, check that the name matches what **Services** shows. Or drop the `filter` line to list every service name. The docs recommend `interval:1m` for alerting.
2. Go to **Settings → Analyze and alert → Alerts → All alerts → Custom alerts**, then **New alert → Create your own custom alert**.
3. On the **Simple** tab:
   - **Set scope → Query:** paste the query.
   - **Define alert condition:** choose the **Static threshold** analyzer. Set **Threshold** to `10` and **Alert condition** to **Alert if metric is above**. Use `0` only if you turned off the background errors.
   - **Sliding window** (advanced properties): the default is 3 violating one-minute samples out of 5, with 5 de-alerting samples. That's fine for a 10-minute spike. For a faster alert, use `1` violating sample out of `3`.
   - **Add details:** set **Title** to `dynatrace-demo failures` and **Event name** to `Divide-by-zero errors on dynatrace-demo`. Set the event type to **Error** or **Custom alert**; both open a Problem.
4. Select **Create**. Shortly afterwards, check the alert's **Status** to make sure it runs without errors.
5. Run `dtdemo-load spike 10`. With the default sliding window, a Problem appears after about 3–5 minutes.

**Dynatrace Classic: metric event**

1. Go to **Settings → Anomaly detection → Metric events** and select **Add metric event**.
2. Configure:
   - **Summary:** `dynatrace-demo /error failures`
   - **Query type:** **Metric key** `builtin:service.errors.server.count`
   - **Aggregation:** **Count** or **Sum**
   - **Entity filter:** service name equals `dynatrace-demo`
   - **Monitoring strategy:** **Static threshold** (the only option for metric key events). Set **Threshold** to `10` and **Alert condition** to **Above**. Use `0` only if you turned off the background errors.
   - **Violating samples:** `3`, **Sliding window:** `5`, **Dealerting samples:** `5`. These are the defaults; use `1` of `3` for a faster alert.
3. **Event template:**
   - **Title:** `Divide-by-zero errors on dynatrace-demo`
   - **Event type:** **Error**
   - **Allow merge:** leave it on, so repeated violations join one Problem
4. Save, then run `dtdemo-load spike 10`.

### C2. Log event on the ERROR log line

Instead of the request failure, this alerts on the log line the app writes to `/var/log/dynatrace-demo/application.log`.

1. Make sure the log is ingested. Search **Logs** for `Divide by zero exception caught`. If nothing shows up, add `/var/log/dynatrace-demo/application.log` as a custom log source or ingest rule under Log Monitoring in Settings.
2. Create the log event:
   - **Latest:** go to **Settings → Process and contextualize → OpenPipeline → Logs → Pipelines**. Edit the pipeline your logs are routed to, open the **Davis** tab, and add a **Davis event processor**.
   - **Classic:** go to **Settings → Log Monitoring → Events extraction** and select **Add log event**.
3. Configure:
   - **Matching condition** (DQL matcher): `matchesPhrase(content, "Divide by zero exception caught")`
   - **Event name / title:** `Divide-by-zero exception in dynatrace-demo`. This also becomes the Problem title.
   - **Event type:**
     - Latest (OpenPipeline): add the event property `event.type` = `ERROR_EVENT`. The docs' example uses `CUSTOM_ALERT`, which also works.
     - Classic: choose **Error** from the event type list.
4. Every matching log line triggers a log event, and by default they merge into one Problem. Each event stays open for **15 minutes** (the default `dt.event.timeout`) after the last matching line. So:
   - Turn off the generator's background errors first with `dtdemo-load baseline 60 0`. Otherwise the ~1 error per minute keeps the Problem open permanently.
   - Then run `bash scripts/trigger.sh error 1`. A Problem appears once the log line is ingested and processed. It closes about 15 minutes after the last error.

Log events are billed under the Dynatrace Platform Subscription (DPS) events consumption, which is usually negligible for a demo.

---

## Suggested demo flow

1. **Healthy state:** the load generator is already running (check with `dtdemo-load status`). Show the service, its steady traffic, and a couple of failed traces from the ~2% background errors. Point out that there is **no Problem**: Davis doesn't alert on background noise.
2. **Incident:** run `dtdemo-load spike 10` and keep `dtdemo-load watch` open in a second terminal. Show the failure rate climbing, then the **Problem card** opening with its impact (the affected service and endpoint), the root cause (`ArithmeticException` in `DynatraceDemoApplication.errorTransaction`), and the linked logs. Expect it 5–10 minutes into the spike.
3. **Recovery:** run `dtdemo-load calm` and show the Problem closing on its own.

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| The service isn't listed | OneAgent was installed after the app started. Restart the app with `sudo systemctl restart dynatrace-demo`. Also check that OneAgent is in Full-Stack mode, not Infrastructure-only. |
| `/error` requests aren't shown as failures | Someone may have changed failure detection. Check **Settings → Process and contextualize → Services → Failure detection rules**, or the service's own failure detection settings. |
| Failures show but no Problem opens (Option A) | The service has run for less than ~34 hours, so failure-rate alerting hasn't started yet. Use Option B or C. |
| Option B or C doesn't fire | Make sure the spike lasts at least 5–10 minutes; fixed thresholds are judged over 5-minute periods and custom alerts default to 3 of 5 minutes. For B, check the low-load (actions/min) setting. For C1, check the alert's **Status** and run the query in a Notebook. |
| A Problem opens but no email or Slack arrives | The alerting profile filters it out, for example by severity or delay. Check the alerting profile and the problem notification integration. |
| A log event doesn't fire | The log isn't ingested, or it's routed to a different OpenPipeline pipeline than the one you edited. Search **Logs** for the phrase first. |

---

Sources (docs.dynatrace.com): *Adjust the sensitivity of anomaly detection for services*, *Automated multidimensional baselining*, *Anomaly detection configuration*, *Configure a simple custom alert*, *Built-in metrics on Grail*, *Metric key events*, *Log events* (latest and classic), *Event categories*, *Configure service failure detection*, and the *builtin:anomaly-detection.services* settings schema.
