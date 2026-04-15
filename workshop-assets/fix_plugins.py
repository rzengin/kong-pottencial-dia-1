import re

files = [
    "07-correlation-id/kong.yaml",
    "08-observabilidad/kong.yaml",
    "11-clustering/kong.yaml"
]

clean_consumers = """consumers:
  - username: App-External
    keyauth_credentials:
      - key: my-external-key
  - username: App-Internal
    keyauth_credentials:
      - key: my-internal-key
"""

for fn in files:
    with open(fn, "r", encoding="utf-8") as f:
        content = f.read()

    # Replace everything from `consumers:` to the end
    content = re.sub(r'consumers:\n.*', clean_consumers, content, flags=re.DOTALL)
    
    with open(fn, "w", encoding="utf-8") as f:
        f.write(content)
