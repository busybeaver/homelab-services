import sys

with open('docker-compose.yaml', 'r') as f:
    content = f.read()

old_anchor = """x-hardened-security: &hardened-security
  cap_drop:
    - ALL
  read_only: true
  security_opt:
    - no-new-privileges:true"""

new_anchor = """x-hardened-security: &hardened-security
  cap_drop:
    - ALL
  read_only: true
  security_opt:
    - no-new-privileges:true
  sysctls:
    - net.ipv4.ip_unprivileged_port_start=0"""

if old_anchor in content:
    new_content = content.replace(old_anchor, new_anchor)
    with open('docker-compose.yaml', 'w') as f:
        f.write(new_content)
    print("Successfully updated docker-compose.yaml")
else:
    print("Anchor not found or already modified")
