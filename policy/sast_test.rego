package main

fp_of(tool, rid, path, text) := crypto.sha256(sprintf("%s|%s|%s|%s", [tool, rid, path, text]))

entry(tool, rid, path, text) := {
	"tool": tool,
	"ruleId": rid,
	"path": path,
	"message": text,
	"sha256": fp_of(tool, rid, path, text),
}

finding(level, path, rid, text) := {
	"level": level,
	"ruleId": rid,
	"message": {"text": text},
	"locations": [{
		"physicalLocation": {"artifactLocation": {"uri": path}},
	}],
}

bare_finding(path, rid, text) := {
	"ruleId": rid,
	"message": {"text": text},
	"locations": [{
		"physicalLocation": {"artifactLocation": {"uri": path}},
	}],
}

semgrep_run(results) := {
	"tool": {"driver": {"name": "Semgrep OSS", "rules": []}},
	"results": results,
}

semgrep_run_rules(rules, results) := {
	"tool": {"driver": {"name": "Semgrep OSS", "rules": rules}},
	"results": results,
}

gitleaks_run(results) := {
	"tool": {"driver": {"name": "gitleaks"}},
	"results": results,
}

gate_input(mode, results) := gate_input_runs(mode, [semgrep_run(results)], [])

gate_input_runs(mode, runs, entries) := {
	"mode": mode,
	"sarif": {"runs": runs},
	"baseline": {"fingerprints": entries},
}

first_party_error := finding("error", ".github/workflows/ci.yml", "rule.a", "bad thing")

first_party_warning := finding("warning", "scripts/build.sh", "rule.b", "meh")

vendor_error := finding("error", "dvwa/vulnerabilities/sqli/index.php", "rule.c", "expected in vendor")

test_enforce_critical_denies_first_party_error if {
	deny["[enforce-critical] rule.a at .github/workflows/ci.yml: bad thing"] with input as gate_input(
		"enforce-critical",
		[first_party_error],
	)
}

test_enforce_critical_ignores_first_party_warning if {
	count(deny) == 0 with input as gate_input("enforce-critical", [first_party_warning])
	count(warn) == 1 with input as gate_input("enforce-critical", [first_party_warning])
}

test_baselined_finding_never_denied if {
	count(deny) == 0 with input as gate_input_runs(
		"enforce-critical",
		[semgrep_run([vendor_error])],
		[entry("Semgrep OSS", "rule.c", "dvwa/vulnerabilities/sqli/index.php", "expected in vendor")],
	)
	count(warn) == 1 with input as gate_input_runs(
		"enforce-critical",
		[semgrep_run([vendor_error])],
		[entry("Semgrep OSS", "rule.c", "dvwa/vulnerabilities/sqli/index.php", "expected in vendor")],
	)
}

test_enforce_full_denies_nonbaselined_warning if {
	count(deny) == 1 with input as gate_input_runs(
		"enforce-full",
		[semgrep_run([first_party_warning])],
		[],
	)
}

test_no_path_exemption_new_dvwa_finding_denied if {
	deny["[enforce-critical] rule.d at dvwa/new.php: newly introduced"] with input as gate_input(
		"enforce-critical",
		[finding("error", "dvwa/new.php", "rule.d", "newly introduced")],
	)
}

test_enforce_full_denies_first_party_warning if {
	deny["[enforce-full] rule.b at scripts/build.sh: meh"] with input as gate_input(
		"enforce-full",
		[first_party_warning],
	)
}

test_enforce_full_keeps_baselined_visible_as_warning if {
	count(deny) == 0 with input as gate_input_runs(
		"enforce-full",
		[semgrep_run([vendor_error])],
		[entry("Semgrep OSS", "rule.c", "dvwa/vulnerabilities/sqli/index.php", "expected in vendor")],
	)
	count(warn) == 1 with input as gate_input_runs(
		"enforce-full",
		[semgrep_run([vendor_error])],
		[entry("Semgrep OSS", "rule.c", "dvwa/vulnerabilities/sqli/index.php", "expected in vendor")],
	)
}

test_warn_mode_denies_nothing if {
	count(deny) == 0 with input as gate_input("warn", [first_party_error])
	count(warn) == 1 with input as gate_input("warn", [first_party_error])
}

test_unknown_mode_denies if {
	deny["gate mode invalid: banana"] with input as gate_input("banana", [])
}

test_malformed_input_denies if {
	deny["gate input malformed: expected non-empty sarif.runs[] with results[] and a baseline.fingerprints[] array"] with input as {
		"mode": "enforce-critical",
		"sarif": {"runs": []},
		"baseline": {"fingerprints": []},
	}
}

test_missing_baseline_denies_as_malformed if {
	count(deny) > 0 with input as {
		"mode": "enforce-critical",
		"sarif": {"runs": [semgrep_run([])]},
	}
}

test_critical_denies_error_resolved_from_rule_table if {
	deny["[enforce-critical] rule.sev at src/x.php: from rule table"] with input as gate_input_runs(
		"enforce-critical",
		[semgrep_run_rules([{"id": "rule.sev", "defaultConfiguration": {"level": "error"}}], [bare_finding("src/x.php", "rule.sev", "from rule table")])],
		[],
	)
}

test_missing_rules_table_is_wellformed_severity_falls_back if {
	count(deny) == 0 with input as gate_input_runs(
		"enforce-critical",
		[{"tool": {"driver": {"name": "Trivy"}}, "results": [bare_finding("src/x.php", "rule.g", "note-level default")]}],
		[],
	)
	count(warn) == 1 with input as gate_input_runs(
		"enforce-critical",
		[{"tool": {"driver": {"name": "Trivy"}}, "results": [bare_finding("src/x.php", "rule.g", "note-level default")]}],
		[],
	)
}

test_gitleaks_missing_level_defaults_to_error if {
	deny["[enforce-critical] rule.secret at keys/id_rsa: leaked key"] with input as gate_input_runs(
		"enforce-critical",
		[gitleaks_run([bare_finding("keys/id_rsa", "rule.secret", "leaked key")])],
		[],
	)
}

test_tampered_baseline_entry_denies if {
	count(deny) > 0 with input as gate_input_runs(
		"enforce-critical",
		[semgrep_run([])],
		[{"tool": "Semgrep OSS", "ruleId": "rule.a", "path": "x.php", "message": "m", "sha256": "deadbeef"}],
	)
}

test_multi_run_findings_all_evaluated if {
	count(deny) == 2 with input as gate_input_runs(
		"enforce-critical",
		[
			semgrep_run([finding("error", "a.php", "rule.x", "one")]),
			gitleaks_run([bare_finding("b.pem", "rule.y", "two")]),
		],
		[],
	)
}

test_dir_and_git_duplicates_each_baselined if {
	count(deny) == 0 with input as gate_input_runs(
		"enforce-full",
		[
			gitleaks_run([bare_finding("dvwa/x.php", "generic-api-key", "generic-api-key has detected secret for file dvwa/x.php.")]),
			gitleaks_run([bare_finding("dvwa/x.php", "generic-api-key", "generic-api-key has detected secret for file dvwa/x.php at commit abc123.")]),
		],
		[
			entry("gitleaks", "generic-api-key", "dvwa/x.php", "generic-api-key has detected secret for file dvwa/x.php."),
			entry("gitleaks", "generic-api-key", "dvwa/x.php", "generic-api-key has detected secret for file dvwa/x.php at commit abc123."),
		],
	)
	count(warn) == 2 with input as gate_input_runs(
		"enforce-full",
		[
			gitleaks_run([bare_finding("dvwa/x.php", "generic-api-key", "generic-api-key has detected secret for file dvwa/x.php.")]),
			gitleaks_run([bare_finding("dvwa/x.php", "generic-api-key", "generic-api-key has detected secret for file dvwa/x.php at commit abc123.")]),
		],
		[
			entry("gitleaks", "generic-api-key", "dvwa/x.php", "generic-api-key has detected secret for file dvwa/x.php."),
			entry("gitleaks", "generic-api-key", "dvwa/x.php", "generic-api-key has detected secret for file dvwa/x.php at commit abc123."),
		],
	)
}
