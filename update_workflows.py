import re
import sys

def update_general_yaml(content):
    new_concurrency = """concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true
"""
    # Replace the commented out concurrency block
    pattern = r'# concurrency:.*?#   group:.*?#   something broke;.*?#   group:.*?\n\n'
    # Actually let's be more robust
    if "# concurrency:" in content:
        # Match from # concurrency: until jobs:
        content = re.sub(r'# concurrency:.*?(?=jobs:)', new_concurrency + "\n", content, flags=re.DOTALL)
    return content

def update_repository_yaml(content):
    lines = content.splitlines()
    new_lines = []

    inserted_concurrency = False

    for line in lines:
        new_lines.append(line)
        if line.startswith("on:") and not inserted_concurrency:
            new_lines.append("concurrency:")
            new_lines.append("  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}")
            new_lines.append("  cancel-in-progress: true")
            new_lines.append("")
            inserted_concurrency = True

    content = "\n".join(new_lines)

    # Add permissions and if guard to the job
    job_pattern = r'(  repository:)'
    replacement = r'\1\n    permissions:\n      contents: read\n    # Only run for the repository owner or on non-pull_request_target events to protect secrets\n    if: >\n      github.event_name != "pull_request_target" ||\n      github.event.pull_request.head.repo.full_name == github.repository'

    content = re.sub(job_pattern, replacement, content)
    return content + "\n"

# Read general.yaml
with open(".github/workflows/general.yaml", "r") as f:
    general = f.read()
with open(".github/workflows/general.yaml", "w") as f:
    f.write(update_general_yaml(general))

# Read repository.yaml
with open(".github/workflows/repository.yaml", "r") as f:
    repository = f.read()
with open(".github/workflows/repository.yaml", "w") as f:
    f.write(update_repository_yaml(repository))
