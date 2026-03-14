import os

files_to_review = ['.env.ci', '.github/workflows/docker.yaml', 'docker-compose.yaml']
for file in files_to_review:
    print(f"--- {file} ---")
    if os.path.exists(file):
        with open(file, 'r') as f:
            print(f.read())
    else:
        print("File not found")
    print("\n")
