set dotenv-load := true

template := `cat .trufflehog.example.yml`
config := replace(template, "[TRUFFLEHOG_URL]", env_var('TRUFFLEHOG_URL'))
config_exists := path_exists(".trufflehog.yml")

default:
    just --list

@trufflehog-config:
    case "$TRUFFLEHOG_URL" in https*) ;; *) echo "Error: TRUFFLEHOG_URL does not start with 'https'"; exit 1;; esac
    echo "{{ config }}" > .trufflehog.yml

@trufflehog:
    {{ if config_exists == "false" { "just trufflehog-config" } else {""} }}
    trufflehog git file://. --config .trufflehog.yml --exclude-paths=.trufflehog-ignore --results=verified,unknown --since-commit HEAD --fail

@trufflehog-fs:
    {{ if config_exists == "false" { "just trufflehog-config" } else {""} }}
    trufflehog filesystem --config .trufflehog.yml --exclude-paths=.trufflehog-ignore-fs --results=verified,unknown --fail .
