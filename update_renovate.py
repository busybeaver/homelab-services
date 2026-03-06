import json

# Renovate file is json5, but often standard json parser works if it's not too complex.
# If not, we'll use a regex.
path = ".github/renovate.json5"
with open(path, "r") as f:
    content = f.read()

if '":pinGitHubActionDigests"' not in content:
    # Insert it into the extends array
    if '"extends": [' in content:
        content = content.replace('"extends": [', '"extends": [\n    ":pinGitHubActionDigests",')

with open(path, "w") as f:
    f.write(content)
