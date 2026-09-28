# Tailscale Sidecar Container Security & User Evaluation

## Executive Summary

When running Tailscale sidecar containers in Docker (specifically in **Kernel TUN mode** with `TS_USERSPACE: "false"`), setting a non-root `user:` directive is **not required or recommended** unless switching to Userspace Networking (`TS_USERSPACE: "true"`).

Because kernel networking requires direct access to `/dev/net/tun` and network namespace configuration, running Tailscale as non-root under `TS_USERSPACE: "false"` will fail during startup when `tailscaled` attempts to initialize the TUN interface or apply netlink configurations.

Instead, the current architecture achieves strong security hardening by relying on **Linux Capability Dropping** (`cap_drop: [ALL]`), **Minimal Explicit Capabilities** (`cap_add: [NET_ADMIN, NET_RAW]`), **Privilege Escalation Prevention** (`no-new-privileges:true`), **Resource Limits** (CPU, memory, PIDs), and **Network Isolation** via dedicated internal bridge networks.

---

## Detailed Technical Analysis

### 1. Requirements for Kernel TUN Mode (`TS_USERSPACE: "false"`)

In the current `docker-compose.yaml`, Tailscale sidecars use:
- `devices: ["/dev/net/tun:/dev/net/tun"]`
- `cap_add: ["NET_ADMIN", "NET_RAW"]`
- `environment: TS_USERSPACE: "false"`

Under Linux container execution:
1. `tailscaled` must open `/dev/net/tun` and execute netlink calls (`RTM_NEWLINK`, `RTM_NEWADDR`, route table manipulation) to instantiate the `tailscale0` virtual network interface within the container's network namespace.
2. Even with `CAP_NET_ADMIN` granted in Docker, Linux capability checks for system calls that mutate kernel network state or open device nodes check against effective process credentials.
3. If an unprivileged UID (e.g. `user: "1001:2000"`) is specified, `tailscaled` loses effective root privileges required to bind kernel interfaces unless binary file capabilities (`setcap`) are present on `tailscaled`.
4. However, file capabilities are intentionally rendered non-functional because `security_opt: ["no-new-privileges:true"]` prevents privilege transition during binary execution.

Therefore, setting a non-root user (`user: "1001:2000"` or dedicated Tailscale UIDs) under `TS_USERSPACE: "false"` breaks container startup.

---

## Architecture & Security Trade-Off Matrix

| Strategy | Security Posture | Compatibility (`TS_USERSPACE: "false"`) | Maintainability & Overhead |
| :--- | :--- | :--- | :--- |
| **Option A: Container Root (UID 0) + Capability Hardening** *(Current Setup)* | **High**: Process is UID 0 inside container namespace, but stripped of all Linux capabilities except `NET_ADMIN`/`NET_RAW`. Protected by `no-new-privileges:true` and resource caps. | **100% Compatible**: Full kernel networking performance and standard TUN behavior. | **Lowest**: Low maintenance, no UID/GID permission management on state volumes. |
| **Option B: Dedicated Non-Root User per Service** | **High Principle**, but **Incompatible**: Unprivileged process cannot configure kernel TUN interface without binary setcap capability. | **Incompatible** under `TS_USERSPACE: "false"`. (Only compatible with `TS_USERSPACE: "true"`). | **High**: Requires managing unique UIDs (`1010`, `1011`, etc.) and matching volume ownership. |
| **Option C: Single Shared Non-Root User** | **Medium**: Compromise of one sidecar exposes shared volume access if volumes are co-located. | **Incompatible** under `TS_USERSPACE: "false"`. (Only compatible with `TS_USERSPACE: "true"`). | **Medium**: Single UID to manage across sidecars. |
| **Option D: Userspace Networking (`TS_USERSPACE: "true"`) with Non-Root Users** | **Highest Isolation**: Runs completely in unprivileged userspace, no `/dev/net/tun` or `NET_ADMIN` required. | **N/A** (Requires changing requirement from `TS_USERSPACE: "false"` to `"true"`). | **Medium**: Higher proxy/SOCKS5 configuration complexity for application connectivity; potential performance penalty on heavy throughput. |

---

## Recommendations for Security & Maintainability

1. **Retain Current Kernel Mode Model (Option A) for Existing Requirements**
   - Since `TS_USERSPACE: "false"` is a strict requirement, keep container UID 0 inside the container namespace while retaining current security anchors:
     ```yaml
     cap_drop:
       - ALL
     cap_add:
       - NET_ADMIN
       - NET_RAW
     security_opt:
       - no-new-privileges:true
     cpus: 0.25
     mem_limit: 128m
     pids_limit: 100
     ```

2. **Per-Service Network & State Volume Isolation**
   - Maintain isolated Named Volumes for state storage (`adguard-home-ts-state`, `node-red-ts-state`, `beszel-hub-ts-state`).
   - Keep isolated internal bridge networks (`adguard-home_internal`, `node-red_internal`, `beszel-hub_internal`) so sidecars only communicate with their specific app container.

3. **Future Consideration: Transition to Userspace Mode (`TS_USERSPACE: "true"`)**
   - If dedicated non-root users (`user: "${TAILSCALE_USER}:${DOCKER_USER_GROUP}"`) become a strict security requirement in the future, transition sidecars to `TS_USERSPACE: "true"`.
   - In userspace mode, `cap_add` (`NET_ADMIN`, `NET_RAW`) and `/dev/net/tun` device mounts can be completely removed, allowing Tailscale to run as an unprivileged dedicated non-root user.
