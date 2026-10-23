# Redactor fixtures

Every value here is fake. The values are split into `parts`, which the tests join, so that secret
scanners do not flag this repository for strings that only look like credentials.

- `corpus.json`. `secrets` must be caught and must round-trip through `Redaction.restore`. `keep`
  must come back unchanged: these are the identifiers an agent prompt needs.
- `known-misses.json`. These are the shapes the redactor deliberately does not catch. The test
  fails if one of them starts being caught, so the list stays an accurate statement of what
  "known secret shapes" leaves out.
