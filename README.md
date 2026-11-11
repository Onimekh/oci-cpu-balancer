# OCI Adaptive CPU Load Balancer & Watchdog

A production-grade, closed-loop CPU controller and watchdog system designed specifically for Oracle Cloud Infrastructure (OCI) Ampere A1 (aarch64) compute instances running Ubuntu 22.04 LTS. 

This utility maintains overall system-wide CPU utilization between 40% and 50% to satisfy OCI's active-usage metrics, while yielding 100% of CPU cycles to real workloads (like Wazuh, Elasticsearch, or web servers) the instant real work occurs.

## Architecture & Design
* **Zero-Allocation Worker Loop:** Uses lock-free C-types and in-register 64-bit Xorshift arithmetic. Zero IPC queues, zero object serialization, and zero heap churn.
* **Aggressive Preemption:** Workers run at `nice -n 19` with `SCHED_IDLE` CFS policies. The Linux kernel preempts burner routines instantly with zero perceptible latency.
* **Strict Memory Capping:** Hard-capped at 20 MB via systemd `MemoryMax` to protect primary host services.
* **24-Hour Watchdog:** An hourly timer that detects if the service was manually stopped and automatically restarts it if the system remains idle for 24 hours.

## Prerequisites
* OS: Ubuntu 22.04 LTS
* Architecture: aarch64 (ARM64)
* Python 3 standard library
* Root/sudo privileges for installation

## Installation

Clone this repository to your OCI instance and run the `install.sh` script. The installer will automatically copy the files to their correct system paths, set up restricted permissions, and start the systemd services.

```bash
# 1. Clone the repository
git clone [https://github.com/YOUR-USERNAME/YOUR-REPO-NAME.git](https://github.com/YOUR-USERNAME/YOUR-REPO-NAME.git)
cd YOUR-REPO-NAME

# 2. Make the installer executable
chmod +x install.sh

# 3. Run the installer as root
sudo ./install.sh
```

## File Destinations
The `install.sh` script maps the files in this repository to the following system paths:
* `oci-cpu-balancer` -> `/usr/local/bin/oci-cpu-balancer`
* `oci-cpu-watchdog` -> `/usr/local/bin/oci-cpu-watchdog`
* `oci-cpu-balancer.conf` -> `/etc/oci-cpu-balancer.conf`
* `*.service` / `*.timer` -> `/etc/systemd/system/`

## Configuration
Settings can be adjusted in `/etc/oci-cpu-balancer.conf`.

```ini
TARGET_MIN_CPU=40
TARGET_MAX_CPU=50
SAMPLE_INTERVAL_SEC=1.0
IDLE_THRESHOLD_PERCENT=15
IDLE_TRIGGER_HOURS=24
LOG_LEVEL=INFO
```
After modifying the configuration, reload the daemon without dropping workers:
```bash
sudo systemctl reload oci-cpu-balancer.service
```

## Operations & Monitoring

**Check Service Status:**
```bash
sudo systemctl status oci-cpu-balancer.service
sudo systemctl status oci-cpu-watchdog.timer
```

**Verify Process Priorities & Memory:**
```bash
ps -eo pid,user,ni,cls,rss,comm | grep oci-cpu
```
*(You should see `NI` = 19, `CLS` = IDL, and low RSS).*

**View Logs:**
```bash
sudo journalctl -u oci-cpu-balancer.service -f
```

## Uninstallation
To completely remove the service, user, config files, and logs, simply run the installer with the uninstall flag:
```bash
sudo ./install.sh --uninstall
```