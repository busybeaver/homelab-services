import sys

files = [
    ".github/workflows/general.yaml",
    ".github/workflows/repository.yaml",
    ".github/justfile.shared",
    ".github/renovate.json5"
]

for f_path in files:
    print(f"--- {f_path} ---")
    with open(f_path, 'r') as f:
        print(f.read())
