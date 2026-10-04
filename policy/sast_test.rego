package main

finding(level, path, rid, text) := {
	"level": level,
	"ruleId": rid,
	"message": {"text": text},
	"locations": [{
		"physicalLocation": {"artifactLocation": {"uri": path}},
	}],
}

gate_input(mode, results) := {
	"mode": mode,
	"sarif": {
		"runs": [{
			"tool": {"driver": {"name": "semgrep", "rules": []}},
			"results": results,
		}],
	},
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

test_enforce_critical_never_denies_vendor if {
	count(deny) == 0 with input as gate_input("enforce-critical", [vendor_error])
	count(warn) == 1 with input as gate_input("enforce-critical", [vendor_error])
}

test_enforce_full_denies_first_party_warning if {
	deny["[enforce-full] rule.b (warning) at scripts/build.sh: meh"] with input as gate_input(
		"enforce-full",
		[first_party_warning],
	)
}

test_enforce_full_keeps_vendor_visible_as_warning if {
	count(deny) == 0 with input as gate_input("enforce-full", [vendor_error])
	count(warn) == 1 with input as gate_input("enforce-full", [vendor_error])
}

test_warn_mode_denies_nothing if {
	count(deny) == 0 with input as gate_input("warn", [first_party_error])
	count(warn) == 1 with input as gate_input("warn", [first_party_error])
}

test_unknown_mode_denies if {
	deny["gate mode invalid: banana"] with input as gate_input("banana", [])
}

test_malformed_input_denies if {
	deny["gate input malformed: expected sarif.runs[0].results"] with input as {"mode": "enforce-critical"}
}

test_critical_denies_error_resolved_from_rule_table if {
	deny["[enforce-critical] rule.sev at src/x.php: from rule table"] with input as {
		"mode": "enforce-critical",
		"sarif": {"runs": [{
			"tool": {"driver": {"name": "semgrep", "rules": [{
				"id": "rule.sev",
				"defaultConfiguration": {"level": "error"},
			}]}},
			"results": [{
				"ruleId": "rule.sev",
				"message": {"text": "from rule table"},
				"locations": [{"physicalLocation": {"artifactLocation": {"uri": "src/x.php"}}}],
			}],
		}]},
	}
}

test_missing_rule_table_denies_as_malformed if {
	deny["gate input malformed: expected sarif.runs[0].results"] with input as {
		"mode": "enforce-critical",
		"sarif": {"runs": [{
			"tool": {"driver": {"name": "semgrep"}},
			"results": [],
		}]},
	}
}
