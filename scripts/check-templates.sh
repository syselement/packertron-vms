#!/usr/bin/env bash
#
# Run every check CI runs - the template checks, the Ubuntu suite and the
# secret scan - locally, before pushing.
#
# Docs:
#   Packer CLI   https://developer.hashicorp.com/packer/docs/commands
#   cloud-init   https://cloudinit.readthedocs.io/en/latest/reference/cli.html
#   README.md    ../scripts/README.md, which check covers what, and the hook
#
# Run:
#   scripts/check-templates.sh                 # everything
#   scripts/check-templates.sh docs links      # several scopes
#   scripts/check-templates.sh proxmox packer  # one hypervisor's templates
#
# Scopes: packer, seeds, preseeds, unattend, powershell, matrix, shell, docs,
# markdown, links, yaml, workflows, firstboot, tofu, ubuntu, bats, secrets.
# A tool that is not packaged for Ubuntu - pwsh, actionlint, zizmor,
# markdownlint-cli2, gitleaks - is skipped where missing, unless
# CHECKS_REQUIRE_TOOLS=1, which CI sets, makes that a failure.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

readonly WORKFLOW="\
.github/workflows/template-checks.yml"

# - Discovered rather than listed, so a new template is covered the day it is added.
# - The CI matrix cannot discover them - GitHub evaluates it before any
#   checkout - so check_matrix below keeps that one hand-written list honest.
# Empty today; a template that cannot validate yet goes here, with the reason.
readonly -a SKIP_TEMPLATES=()

failures=0

# Empty means every hypervisor; set from the command line to narrow the run.
HYPERVISOR=""

# A well-formed public key that matches no private key, for validate only.
readonly CHECK_SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIChecksOnlyNotARealKeyNotARealKeyNotARealKey checks@example.invalid"

note() { printf '\n== %s\n' "$*"; }
pass() { printf '   ok   %s\n' "$*"; }
fail() {
    printf '   FAIL %s\n' "$*" >&2
    failures=$((failures + 1))
}

# A missing optional tool: skipped here, a failure where CI asks for every one.
missing_tool() {
    local tool="$1" what="$2"

    if [[ "${CHECKS_REQUIRE_TOOLS:-0}" == 1 ]]; then
        fail "$tool is not installed; it ${what}"
    else
        printf '   skip %s (%s is not installed here; CI runs it)\n' "$what" "$tool"
    fi
}

is_skipped() {
    local candidate="$1" skip
    for skip in "${SKIP_TEMPLATES[@]}"; do
        [[ "$candidate" == "$skip" ]] && return 0
    done
    return 1
}

# A template is named "<hypervisor>/<os>", its path under templates/ and also
# what the CI matrix lists.
template_directories() {
    local path directory
    for path in "$REPO_ROOT"/templates/*/*/*.pkr.hcl; do
        [[ -e "$path" ]] || continue
        directory="$(dirname -- "$path")"
        printf '%s\n' "${directory#"$REPO_ROOT"/templates/}"
    done | sort -u
}

check_templates() {
    local directory

    if ! command -v packer >/dev/null 2>&1; then
        fail "packer is not installed; see https://developer.hashicorp.com/packer/install"
        return
    fi

    while read -r directory; do
        [[ -n "$directory" ]] || continue
        # An explicit hypervisor narrows the run to templates/<hypervisor>/.
        if [[ -n "$HYPERVISOR" && "${directory%%/*}" != "$HYPERVISOR" ]]; then
            continue
        fi
        if is_skipped "$directory"; then
            printf '   skip %s (in SKIP_TEMPLATES)\n' "$directory"
            continue
        fi

        note "$directory"
        pushd "$REPO_ROOT/templates/$directory" >/dev/null || {
            fail "$directory: cannot enter"
            continue
        }

        if packer init . >/dev/null; then
            pass "packer init"
        else
            fail "$directory: packer init"
        fi

        if packer fmt -check -diff .; then
            pass "packer fmt"
        else
            fail "$directory: packer fmt (run: packer fmt .)"
        fi

        # Throwaway values for what a build takes from the operator: the
        # Proxmox builder will not validate without a token, and a seed
        # needs a key. validate never contacts the API.
        local -a validate_vars=()
        if grep -q 'proxmox-iso' ./*.pkr.hcl 2>/dev/null; then
            validate_vars+=(
                -var 'proxmox_api_token_id=local@pve!local'
                -var 'proxmox_api_token_secret=not-a-real-secret'
                -var 'ssh_password=not-a-real-secret'
            )
        fi
        if grep -q 'variable "ssh_authorized_key"' ./*.pkr.hcl 2>/dev/null; then
            validate_vars+=(-var "ssh_authorized_key=${CHECK_SSH_KEY}")
        fi
        if packer validate "${validate_vars[@]}" . >/dev/null; then
            pass "packer validate"
        else
            fail "$directory: packer validate"
        fi

        popd >/dev/null || true
    done < <(template_directories)
}

# Both drift directions are quiet failures: a template missing from the matrix
# is never checked by CI, and a matrix entry for a directory that no longer
# exists fails every run with a path error instead of a useful message.
matrix_templates() {
    awk '
        /^ *template: *$/ { inlist = 1; next }
        inlist && /^ *- / { sub(/^ *- +/, ""); sub(/ *(#.*)?$/, ""); print; next }
        inlist && !/^ *#/ { inlist = 0 }
    ' "$REPO_ROOT/$WORKFLOW"
}

check_matrix() {
    local expected actual

    note "CI matrix vs templates on disk"

    if [[ ! -f "$REPO_ROOT/$WORKFLOW" ]]; then
        fail "$WORKFLOW: not found"
        return
    fi

    expected="$(
        while read -r directory; do
            [[ -n "$directory" ]] || continue
            is_skipped "$directory" || printf '%s\n' "$directory"
        done < <(template_directories) | sort
    )"
    actual="$(matrix_templates | sort)"

    if [[ "$expected" == "$actual" ]]; then
        pass "$(printf '%s' "$actual" | grep -c .) template(s) listed, and no others exist"
        return
    fi

    # Process substitution, not a pipe: a piped loop runs in a subshell, so
    # fail() would increment a copy of $failures and the script would exit 0
    # while reporting failures.
    while read -r missing; do
        [[ -n "$missing" ]] || continue
        fail "$missing exists on disk but is not in the $WORKFLOW matrix, so CI never checks it"
    done < <(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))

    while read -r extra; do
        [[ -n "$extra" ]] || continue
        fail "the $WORKFLOW matrix lists $extra, which is not a template directory (or is in SKIP_TEMPLATES)"
    done < <(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))
}

# Everything outside scripts/ubuntu/, which ubuntu-static-checks.yml covers.
# Discovered, so a new script is linted the day it is added. Git hooks have no
# extension, and shfmt reads their language from the shebang.
repository_shell_scripts() {
    local path
    for path in "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/scripts/proxmox/*.sh \
        "$REPO_ROOT"/templates/*/*.sh "$REPO_ROOT"/templates/*/*/*.sh "$REPO_ROOT"/.githooks/*; do
        [[ -f "$path" ]] || continue
        printf '%s\n' "${path#"$REPO_ROOT"/}"
    done | sort -u
}

check_shell() {
    local relative tool missing=0

    note "shell scripts outside scripts/ubuntu/"

    for tool in bash shellcheck shfmt; do
        command -v "$tool" >/dev/null 2>&1 || {
            fail "$tool is not installed"
            missing=1
        }
    done
    ((missing == 0)) || return

    while read -r relative; do
        [[ -n "$relative" ]] || continue
        if bash -n "$REPO_ROOT/$relative" &&
            shellcheck -x "$REPO_ROOT/$relative" &&
            shfmt -d -i 4 -ci "$REPO_ROOT/$relative"; then
            pass "$relative"
        else
            fail "$relative: syntax, shellcheck or shfmt"
        fi
    done < <(repository_shell_scripts)
}

# AGENTS.md keeps Markdown unwrapped: one paragraph or list item per line,
# however long. Wrapping it is easy to do by reflex and invisible in review, so
# it is checked rather than trusted. Code blocks, tables, blockquotes, headings
# and list boundaries are all real structure and left alone.
check_docs() {
    local relative found

    note "Markdown sentences on one line"

    found="$(
        while read -r relative; do
            [[ -n "$relative" ]] || continue
            awk -v file="$relative" '
                /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
                fence { next }
                {
                    line[NR] = $0
                }
                END {
                    for (i = 1; i <= NR; i++) {
                        cur = line[i]; nxt = line[i + 1]
                        if (cur ~ /^[[:space:]]*$/ || nxt ~ /^[[:space:]]*$/) continue
                        if (cur ~ /^[[:space:]]*(#|\||>)/ || nxt ~ /^[[:space:]]*(#|\||>|```|~~~)/) continue
                        if (cur ~ /^[[:space:]]*[-=*_ ]{3,}$/ || nxt ~ /^[[:space:]]*[-=*_ ]{3,}$/) continue
                        if (nxt ~ /^[[:space:]]*([-*+]|[0-9]+[.)]) /) continue
                        if (cur ~ /  $/) continue
                        printf "%s:%d\n", file, i
                    }
                }
            ' "$REPO_ROOT/$relative"
        done < <(cd "$REPO_ROOT" && git ls-files '*.md' | grep -v '^CHANGELOG.md$')
    )"

    if [[ -z "$found" ]]; then
        pass "no sentence is split across two lines"
        return
    fi
    # Process substitution, not a pipe: a piped loop runs in a subshell, so
    # fail() would increment a copy of $failures and this would exit 0.
    while read -r location; do
        [[ -n "$location" ]] || continue
        fail "$location: sentence continues on the next line; keep it on one"
    done < <(printf '%s\n' "$found")
}

# AGENTS.md: a --- rule before every ## heading and at the end of the file,
# and nowhere else.
check_rules() {
    local relative found

    note "Markdown rules before each ## heading"

    found="$(
        while read -r relative; do
            [[ -n "$relative" ]] || continue
            awk -v file="$relative" '
                /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
                fence { next }
                /^[[:space:]]*$/ { next }
                /^## / && last != "---" { printf "%s:%d: no --- rule before this heading\n", file, NR }
                last == "---" && !/^## / { printf "%s:%d: a --- rule may only precede a ## heading or end the file\n", file, lastnr }
                { last = $0; lastnr = NR }
                END { if (last != "---") printf "%s:%d: no --- rule at the end of the file\n", file, NR }
            ' "$REPO_ROOT/$relative"
        done < <(cd "$REPO_ROOT" && git ls-files '*.md' | grep -v '^CHANGELOG.md$')
    )"

    if [[ -z "$found" ]]; then
        pass "every ## heading has its rule, and every file ends with one"
        return
    fi
    while read -r location; do
        [[ -n "$location" ]] || continue
        fail "$location"
    done < <(printf '%s\n' "$found")
}

# The deploy/ module reads the first-boot files with file(), so a rename there
# breaks it in a way nothing else here would catch.
check_tofu() {
    local module="$REPO_ROOT/deploy"

    note "deploy/ OpenTofu module"

    if [[ ! -d "$module" ]]; then
        pass "no deploy/ module"
        return
    fi
    if ! command -v tofu >/dev/null 2>&1; then
        fail "tofu is not installed; see https://opentofu.org/docs/intro/install/"
        return
    fi

    # Tracked files only. A local deploy.tfvars or kali.tfvars is the operator's
    # own, gitignored, and never seen by CI, so formatting it is not this
    # repository's business - and -recursive would also descend
    # into terraform.tfstate.d/.
    local source unformatted=0
    while read -r source; do
        [[ -n "$source" ]] || continue
        tofu fmt -check "$REPO_ROOT/$source" >/dev/null ||
            {
                fail "$source: tofu fmt (run: tofu fmt $source)"
                unformatted=1
            }
    done < <(cd "$REPO_ROOT" && git ls-files 'deploy/*.tf' 'deploy/*.tfvars')
    ((unformatted == 1)) || pass "tofu fmt"

    # -backend=false so this never touches remote state.
    if tofu -chdir="$module" init -backend=false -input=false >/dev/null; then
        pass "tofu init"
    else
        fail "deploy/: tofu init"
        return
    fi

    if tofu -chdir="$module" validate >/dev/null; then
        pass "tofu validate"
    else
        fail "deploy/: tofu validate"
    fi
}

# cloud-init cannot include a file, so every seed carries its own copy of the
# first-boot stub and unit. This is what stops an edit to
# scripts/ubuntu/firstboot/ from reaching only the seeds someone remembered.
check_firstboot() {
    note "embedded first-boot copies"

    if "$REPO_ROOT/scripts/sync-firstboot.sh" --check; then
        pass "every seed embeds the current scripts/ubuntu/firstboot/ files"
    else
        fail "a seed is out of date; run scripts/sync-firstboot.sh"
    fi
}

# Prints each offending line and returns non-zero if there is one. Continuation
# lines (a trailing backslash) belong to the entry above and carry no type.
preseed_type_errors() {
    local file="$1"

    awk -v file="${file#"$REPO_ROOT"/}" '
        continued            { continued = /\\$/; next }
        /^[[:space:]]*(#|$)/ { next }
        {
            continued = /\\$/
            type = $3
            if (type !~ /^(string|boolean|select|multiselect|note|password|text|title|error)$/) {
                printf "   %s:%d: unknown debconf type \"%s\"\n", file, NR, type > "/dev/stderr"
                bad = 1
            } else if (type == "boolean" && $4 !~ /^(true|false)$/) {
                printf "   %s:%d: boolean must be true or false, not \"%s\"\n", file, NR, $4 > "/dev/stderr"
                bad = 1
            }
        }
        END { exit bad }
    ' "$file"
}

# debian-installer preseeds are debconf selections, not cloud-config, and get
# the check debconf itself offers plus the type check above.
check_preseeds() {
    local file relative

    note "debian-installer preseeds"
    for file in "$REPO_ROOT"/templates/*/*/http/*.preseed; do
        [[ -f "$file" ]] || continue
        relative="${file#"$REPO_ROOT"/}"
        if ! command -v debconf-set-selections >/dev/null 2>&1; then
            fail "debconf-set-selections is not installed (package debconf)"
            break
        fi
        if ! debconf-set-selections --checkonly "$file" 2>/dev/null; then
            fail "$relative: preseed syntax"
            debconf-set-selections --checkonly "$file" 2>&1 | tail -5 >&2 || true
            continue
        fi
        # --checkonly only insists on three fields: it accepts a misspelt
        # type or a boolean set to "maybe", and d-i then stops at a question
        # nobody is there to answer.
        if preseed_type_errors "$file"; then
            pass "$relative"
        else
            fail "$relative: unknown debconf type or bad boolean (see above)"
        fi
    done
}

# Windows Setup reads an answer file once, at install time, and a malformed
# one fails there with nothing Packer can see.
check_unattend() {
    local file relative

    note "Windows answer files"

    if ! command -v xmllint >/dev/null 2>&1; then
        fail "xmllint is not installed (package libxml2-utils)"
        return
    fi

    # Per-template answer files, the one shared by the Proxmox Windows
    # templates, and the sysprep file beside cloudbase-init's configuration.
    for file in "$REPO_ROOT"/templates/*/*/config/*.xml "$REPO_ROOT"/templates/*/*.xml \
        "$REPO_ROOT"/scripts/windows/*/*.xml; do
        [[ -f "$file" ]] || continue
        relative="${file#"$REPO_ROOT"/}"
        if ! xmllint --noout "$file" 2>/dev/null; then
            fail "$relative: not well-formed XML"
            xmllint --noout "$file" 2>&1 | head -5 >&2 || true
            continue
        fi
        # Placeholders from the upstream this was adapted from; nothing
        # substitutes them.
        if grep -q 'SECLAB_' "$file"; then
            fail "$relative: unsubstituted SECLAB_ placeholder"
            continue
        fi
        # Proxmox attaches no floppy, so an a:\ path there can never resolve.
        # VMware can, so the rule stops at templates/proxmox/.
        if [[ "$relative" == templates/proxmox/* ]] && grep -qiE '\ba:[\]' "$file"; then
            fail "$relative: a:\\ path, but Proxmox attaches no floppy drive"
            continue
        fi
        pass "$relative"
    done
}

# The Windows provisioners only run inside a build, half an hour in, so a
# syntax error there is the most expensive typo in this repository; pwsh's own
# parser finds it in a second. PSScriptAnalyzer then holds every script to zero
# findings. Neither is in the Ubuntu archive, so where one is missing its check
# is skipped, not failed. GitHub's runners ship both, so CI does not skip.
check_powershell() {
    local state relative message

    note "PowerShell syntax and PSScriptAnalyzer"

    if ! command -v pwsh >/dev/null 2>&1; then
        missing_tool pwsh "parses and lints the PowerShell"
        return
    fi

    # One pwsh for every file, fed on stdin: its startup is slower than the
    # parsing. Tracked files plus new ones not yet added, never ignored ones.
    # shellcheck disable=SC2016 # the script is PowerShell; its $ are pwsh's
    while IFS=$'\t' read -r state relative message; do
        case "$state" in
            ok) pass "$relative" ;;
            FAIL) fail "$relative: $message" ;;
            SKIP) missing_tool PSScriptAnalyzer "lints the PowerShell" ;;
        esac
    done < <(
        cd "$REPO_ROOT" &&
            git ls-files --cached --others --exclude-standard '*.ps1' |
            pwsh -NoProfile -NonInteractive -Command '
                $analyze = [bool](Get-Module -ListAvailable -Name PSScriptAnalyzer)
                if (-not $analyze) {
                    "SKIP`tPSScriptAnalyzer"
                }
                $input | ForEach-Object {
                    $path = Join-Path (Get-Location) $_
                    $errors = $null
                    [System.Management.Automation.Language.Parser]::ParseFile(
                        $path, [ref]$null, [ref]$errors) | Out-Null
                    if ($errors.Count) {
                        "FAIL`t$_`tline $($errors[0].Extent.StartLineNumber): $($errors[0].Message)"
                        return
                    }
                    if ($analyze) {
                        $findings = @(Invoke-ScriptAnalyzer -Path $path)
                        if ($findings.Count) {
                            $first = $findings[0]
                            "FAIL`t$_`t$($findings.Count) PSScriptAnalyzer finding(s), first at line $($first.Line): $($first.RuleName)"
                            return
                        }
                    }
                    "ok`t$_"
                }'
    )
}

# Tracked files only, never the operator's own: a local tfvars, the state, or
# a file someone has not added yet is not this repository's to judge.
tracked() {
    (cd "$REPO_ROOT" && git ls-files -- "$@")
}

# The checks .github/workflows/ubuntu-static-checks.yml runs.
check_ubuntu() {
    local dir="$REPO_ROOT/scripts/ubuntu" tool missing=0

    note "scripts/ubuntu/ lint and Bats suite"
    for tool in bash shellcheck shfmt bats; do
        command -v "$tool" >/dev/null 2>&1 || {
            fail "$tool is not installed"
            missing=1
        }
    done
    ((missing == 0)) || return

    if (cd "$dir" && bash -n ./*.sh ./lib/*.sh ./firstboot/*.sh); then
        pass "bash -n"
    else
        fail "scripts/ubuntu: bash -n"
    fi
    if (cd "$dir" && shellcheck -x ./*.sh ./lib/*.sh ./firstboot/*.sh); then
        pass "shellcheck"
    else
        fail "scripts/ubuntu: shellcheck"
    fi
    if (cd "$dir" && shfmt -d -i 4 -ci ./*.sh ./lib/*.sh ./firstboot/*.sh); then
        pass "shfmt"
    else
        fail "scripts/ubuntu: shfmt (run: shfmt -w -i 4 -ci on the files above)"
    fi
    if (cd "$dir" && bats tests >/dev/null); then
        pass "bats tests"
    else
        fail "scripts/ubuntu: bats tests (run: cd scripts/ubuntu && bats tests)"
    fi
}

# Every Bats suite outside scripts/ubuntu/, discovered as scripts/*/tests/.
check_bats() {
    local suite relative

    note "Bats suites outside scripts/ubuntu/"
    command -v bats >/dev/null 2>&1 || {
        fail "bats is not installed"
        return
    }
    for suite in "$REPO_ROOT"/scripts/*/tests; do
        [[ -d "$suite" ]] || continue
        relative="${suite#"$REPO_ROOT"/}"
        [[ "$relative" == scripts/ubuntu/tests ]] && continue
        if bats "$suite" >/dev/null; then
            pass "$relative"
        else
            fail "$relative (run: bats $relative)"
        fi
    done
}

# History, not the working tree: a tree scan would read the operator's own
# tfvars and state, which are gitignored and never pushed.
check_secrets() {
    note "secrets in the git history"
    command -v gitleaks >/dev/null 2>&1 || {
        missing_tool gitleaks "scans the history for secrets"
        return
    }
    if gitleaks git "$REPO_ROOT" --no-banner --redact --log-level error; then
        pass "gitleaks: no leaks"
    else
        fail "gitleaks found a secret in the history; see above"
    fi
}

# actionlint checks workflow syntax and expressions, and shellcheck's view of
# every run: block; zizmor checks them for security mistakes. zizmor's online
# audits - an action pinned to an impostor commit, a known-vulnerable version
# - run when a GitHub token is in the environment, as in CI.
check_workflows() {
    local -a zizmor_flags=(--config "$REPO_ROOT/.github/zizmor.yml" --format plain)

    note "GitHub Actions workflows"
    if command -v actionlint >/dev/null 2>&1; then
        if (cd "$REPO_ROOT" && actionlint -no-color); then
            pass "actionlint"
        else
            fail "actionlint; see above"
        fi
    else
        missing_tool actionlint "lints the workflows"
    fi

    if ! command -v zizmor >/dev/null 2>&1; then
        missing_tool zizmor "audits the workflows for security mistakes"
        return
    fi
    [[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]] || zizmor_flags+=(--offline)
    if zizmor "${zizmor_flags[@]}" "$REPO_ROOT/.github/workflows" >/dev/null 2>&1; then
        pass "zizmor"
    else
        zizmor "${zizmor_flags[@]}" "$REPO_ROOT/.github/workflows" >&2 || true
        fail "zizmor; see above"
    fi
}

# version.yaml is rewritten by the release workflow on every release.
check_yaml() {
    local -a files=()

    note "YAML"
    command -v yamllint >/dev/null 2>&1 || {
        missing_tool yamllint "lints the YAML"
        return
    }
    mapfile -t files < <(tracked '*.yml' '*.yaml' 'templates/*/*/http/user-data' | grep -v '^version\.yaml$')
    if (cd "$REPO_ROOT" && yamllint --strict "${files[@]}"); then
        pass "${#files[@]} file(s)"
    else
        fail "yamllint; see above"
    fi
}

check_markdown() {
    local -a files=()

    note "Markdown style"
    command -v markdownlint-cli2 >/dev/null 2>&1 || {
        missing_tool markdownlint-cli2 "lints the Markdown"
        return
    }
    mapfile -t files < <(tracked '*.md')
    if (cd "$REPO_ROOT" && markdownlint-cli2 "${files[@]}" >/dev/null 2>&1); then
        pass "${#files[@]} file(s)"
    else
        (cd "$REPO_ROOT" && markdownlint-cli2 "${files[@]}") >&2 || true
        fail "markdownlint; see above"
    fi
}

# A relative link or anchor that points nowhere is invisible in review and
# only found by a reader. External URLs are not fetched: that would make the
# check depend on the network and on other people's sites.
check_links() {
    local found

    note "relative links and anchors in Markdown"
    command -v python3 >/dev/null 2>&1 || {
        missing_tool python3 "checks the Markdown links"
        return
    }
    # shellcheck disable=SC2016 # the quoted text is Python
    found="$(tracked '*.md' | (cd "$REPO_ROOT" && python3 -c '
import os, re, sys

FENCE = re.compile(r"^\s*(```|~~~)")
LINK = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
REF = re.compile(r"^\s*\[[^\]]+\]:\s*(\S+)")

def prose(path):
    """Lines outside fenced blocks, with inline code removed."""
    inside = False
    with open(path, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            if FENCE.match(line):
                inside = not inside
                continue
            if not inside:
                yield number, re.sub(r"`[^`]*`", "", line)

def slug(text):
    # GitHub: drop link targets and markup, lowercase, keep word characters,
    # spaces and hyphens, then turn spaces into hyphens.
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"[^\w\- ]", "", text.strip().lower())
    return text.replace(" ", "-")

anchors = {}
def anchors_of(path):
    if path not in anchors:
        seen, found = {}, set()
        inside = False
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                if FENCE.match(line):
                    inside = not inside
                    continue
                match = None if inside else re.match(r"^#{1,6}\s+(.*?)\s*#*\s*$", line)
                if match:
                    base = slug(match.group(1).replace("`", ""))
                    count = seen.get(base, 0)
                    seen[base] = count + 1
                    found.add(base if count == 0 else f"{base}-{count}")
        anchors[path] = found
    return anchors[path]

broken = []
for source in sys.stdin.read().split():
    for number, line in prose(source):
        targets = LINK.findall(line) + REF.findall(line)
        for target in targets:
            if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I) or target.startswith("<"):
                continue
            path, _, anchor = target.partition("#")
            resolved = os.path.normpath(os.path.join(os.path.dirname(source), path)) if path else source
            if not os.path.exists(resolved):
                broken.append(f"{source}:{number}: {target} - no such file")
            elif anchor and resolved.endswith(".md") and anchor.lower() not in anchors_of(resolved):
                broken.append(f"{source}:{number}: {target} - no such heading")
print("\n".join(broken))
'))" || {
        fail "the link checker itself failed"
        return
    }

    if [[ -z "$found" ]]; then
        pass "every relative link and anchor resolves"
        return
    fi
    while read -r location; do
        [[ -n "$location" ]] || continue
        fail "$location"
    done < <(printf '%s\n' "$found")
}

check_seeds() {
    local file documents

    note "cloud-init seeds"
    for file in "$REPO_ROOT"/scripts/ubuntu/autoinstall-*.yaml "$REPO_ROOT"/templates/*/*/http/user-data; do
        [[ -f "$file" ]] || continue
        local relative="${file#"$REPO_ROOT"/}"

        # cloud-init reads the first document and silently ignores the rest, so
        # a second one is dead text that still looks live.
        documents="$(grep -c '^#cloud-config' "$file" || true)"
        if ((documents > 1)); then
            fail "$relative: $documents #cloud-config documents; only the first is read"
            continue
        fi

        if cloud-init schema --config-file "$file" >/dev/null 2>&1; then
            pass "$relative"
        else
            fail "$relative: schema"
            cloud-init schema --config-file "$file" --annotate 2>&1 | tail -20 >&2 || true
        fi
    done

    # A seed carries the @SSH_AUTHORIZED_KEY@ placeholder, never a key: a
    # committed key would be authorized on every machine built from a fork.
    while read -r found; do
        [[ -n "$found" ]] || continue
        fail "${found%%:*}: a public key is committed; use @SSH_AUTHORIZED_KEY@ instead"
    done < <(cd "$REPO_ROOT" && grep -l -E '(ssh-(ed25519|rsa|dss)|ecdsa-sha2-nistp[0-9]+|sk-[a-z0-9-]+@openssh\.com) AAAA' \
        scripts/ubuntu/autoinstall-*.yaml templates/*/*/http/* 2>/dev/null)
}

main() {
    local scope
    local -a scopes=()

    # A hypervisor name is accepted first, validated against the directories
    # that exist rather than a hard-coded list.
    if [[ -n "${1:-}" && -d "$REPO_ROOT/templates/$1" ]]; then
        HYPERVISOR="$1"
        shift
    fi
    scopes=("${@:-all}")

    for scope in "${scopes[@]}"; do
        case "$scope" in
            all)
                check_templates
                check_preseeds
                check_seeds
                check_unattend
                check_firstboot
                check_tofu
                check_shell
                check_powershell
                check_docs
                check_rules
                check_markdown
                check_links
                check_yaml
                check_workflows
                check_matrix
                check_ubuntu
                check_bats
                check_secrets
                ;;
            packer) check_templates ;;
            seeds)
                check_preseeds
                check_seeds
                ;;
            preseeds) check_preseeds ;;
            unattend) check_unattend ;;
            powershell) check_powershell ;;
            firstboot) check_firstboot ;;
            tofu) check_tofu ;;
            matrix) check_matrix ;;
            shell) check_shell ;;
            docs)
                check_docs
                check_rules
                ;;
            markdown) check_markdown ;;
            links) check_links ;;
            yaml) check_yaml ;;
            workflows) check_workflows ;;
            ubuntu) check_ubuntu ;;
            bats) check_bats ;;
            secrets) check_secrets ;;
            *)
                printf 'usage: %s [<hypervisor>] [scope ...]\n' "${BASH_SOURCE[0]##*/}" >&2
                printf 'scopes: all packer seeds preseeds unattend powershell firstboot tofu matrix shell docs markdown links yaml workflows ubuntu bats secrets\n' >&2
                printf 'hypervisors: %s\n' "$(cd "$REPO_ROOT/templates" && echo */)" >&2
                exit 2
                ;;
        esac
    done

    printf '\n'
    if ((failures > 0)); then
        printf '%d check(s) failed\n' "$failures" >&2
        exit 1
    fi
    printf 'all checks passed\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
