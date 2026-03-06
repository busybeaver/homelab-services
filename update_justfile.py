import re

with open(".github/justfile.shared", "r") as f:
    content = f.read()

# Define checksums
checksums = {
    "comet-darwin-amd64": "f0b8eee36c3a6af89f095ef971d8f9135f574ecc61bceab2549edb01c43c26a1",
    "comet-darwin-arm64": "50c07b4cc85979541956835906e513fb421e69875e48193fe26361773a3e438a"
}

# Find the comet installation block
pattern = r'(  wget -cO - "https://github.com/liamg/comet/releases/download/v\${VERSION-}/\${FILENAME-}" > /tmp/comet)'
replacement = r"""  if [[ "{{arch()}}" == "x86_64" ]]; then
    EXPECTED_SHA="f0b8eee36c3a6af89f095ef971d8f9135f574ecc61bceab2549edb01c43c26a1"
  else
    EXPECTED_SHA="50c07b4cc85979541956835906e513fb421e69875e48193fe26361773a3e438a"
  fi

  wget -cO - "https://github.com/liamg/comet/releases/download/v${VERSION-}/${FILENAME-}" > /tmp/comet
  echo "${EXPECTED_SHA}  /tmp/comet" | shasum -a 256 -c -"""

content = re.sub(pattern, replacement, content)

with open(".github/justfile.shared", "w") as f:
    f.write(content)
