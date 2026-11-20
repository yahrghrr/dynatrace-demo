# Dashboards

## `server-health-averages.json`: fleet CPU, memory and disk

A dashboard for the **Dashboards** app (latest Dynatrace, Grail/DQL) that shows the **average CPU, memory and disk usage across all servers** monitored by OneAgent.

| Tile | What it shows | Metric (Grail) |
|---|---|---|
| Hosts reporting | Number of hosts sending host metrics in the timeframe | `dt.host.cpu.usage` |
| Avg CPU usage (%) | Average CPU across all hosts | `dt.host.cpu.usage` |
| Avg memory usage (%) | Average memory across all hosts | `dt.host.memory.usage` |
| Avg disk used (%) | Average used space across every disk on every host | `dt.host.disk.used.percent` |
| Average utilization over time | CPU, memory and disk averages as one line chart | all three |
| Per-host averages | One row per host, sorted by CPU, to spot the outlier behind an average | all three |

The three average tiles turn **amber at 70%** and **red at 85%**. Everything follows the dashboard's timeframe picker.

### Import it

1. Open the **Dashboards** app.
2. Select **Upload** (in older versions: **⋯ → Import**) and choose `dashboards/server-health-averages.json`.
3. Save it. Set the timeframe to e.g. *Last 2 hours*.

Each tile is plain DQL, so you can open any tile with **Edit** to tweak it, or paste the query into a **Notebook**.

### Notes

- Hosts need OneAgent (any mode that reports host metrics). Hosts appear within a few minutes of install.
- To scope to some servers instead of all, add a filter to each query, for example
  `timeseries v = avg(dt.host.cpu.usage), filter: { in(dt.entity.host, classicEntitySelector("type(HOST),tag(demo)")) }`.
- Disk is a plain average over all disks. One nearly-full disk can hide behind many empty ones, so check the per-host table.
