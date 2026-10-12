package main

# SAST policy gate. Input: {"mode": warn|enforce-critical|enforce-full,
# "sarif": <merged SARIF from all scanners>, "baseline": {"fingerprints": [...]}}.
#
# There are no path exemptions: every finding from every scanner is evaluated.
# Findings whose fingerprint (sha256 of tool|ruleId|path|message) is listed in
# the baseline are suppressed in every mode and surfaced as warnings. Anything
# new blocks under enforcement: enforce-critical denies first-party findings at
# level "error"; enforce-full denies every finding, any level. Malformed input,
# invalid mode, or a malformed baseline denies (fail-closed).

valid_modes := {"warn", "enforce-critical", "enforce-full"}

valid_mode(m) if m in valid_modes

wellformed if {
	is_array(input.sarif.runs)
	count(input.sarif.runs) > 0
	is_array(object.get(input, ["baseline", "fingerprints"], null))
	every run in input.sarif.runs {
		is_array(run.results)
		non_empty_string(object.get(run, ["tool", "driver", "name"], ""))
		rules_wellformed(run)
	}
}

rules_wellformed(run) if {
	object.get(run, ["tool", "driver", "rules"], null) == null
}

rules_wellformed(run) if {
	is_array(object.get(run, ["tool", "driver", "rules"], null))
}

non_empty_string(s) if {
	is_string(s)
	s != ""
}

tool_name_of(run) := object.get(run, ["tool", "driver", "name"], "")

tool_rules_of(run) := object.get(run, ["tool", "driver", "rules"], [])

# Severity: result.level if present, else the run's rule table, else a
# per-tool default (gitleaks findings are secrets => error; everything
# else => warning). enforce-full denies all three levels anyway.
level_of(run, result) := level if {
	level := result.level
} else := level if {
	some rule in tool_rules_of(run)
	rule.id == result.ruleId
	level := rule.defaultConfiguration.level
} else := default_level(run)

default_level(run) := "error" if {
	contains(lower(tool_name_of(run)), "gitleaks")
} else := "warning"

rule_id_of(result) := object.get(result, "ruleId", "<unknown-rule>")

message_of(result) := text if {
	text := result.message.text
} else := "<no message>"

path_of(result) := uri if {
	some location in result.locations
	uri := location.physicalLocation.artifactLocation.uri
} else := "<unknown-path>"

fingerprint(run, result) := crypto.sha256(sprintf("%s|%s|%s|%s", [
	tool_name_of(run),
	rule_id_of(result),
	path_of(result),
	message_of(result),
]))

baseline_hashes := {hash | some e in input.baseline.fingerprints; hash := e.sha256}

baseline_entry_valid(e) if {
	crypto.sha256(sprintf("%s|%s|%s|%s", [e.tool, e.ruleId, e.path, e.message])) == e.sha256
}

baselined(run, result) if {
	fingerprint(run, result) in baseline_hashes
}

denied_level(level, "enforce-critical") if level == "error"

denied_level(level, "enforce-full") if level in {"error", "warning", "note"}

deny contains msg if {
	not wellformed
	msg := "gate input malformed: expected non-empty sarif.runs[] with results[] and a baseline.fingerprints[] array"
}

deny contains msg if {
	not valid_mode(input.mode)
	msg := sprintf("gate mode invalid: %v", [input.mode])
}

deny contains msg if {
	some e in input.baseline.fingerprints
	not baseline_entry_valid(e)
	msg := sprintf("baseline entry malformed (fingerprint does not match fields): %s %s at %s", [object.get(e, "tool", "?"), object.get(e, "ruleId", "?"), object.get(e, "path", "?")])
}

deny contains msg if {
	input.mode == "enforce-critical"
	some run in input.sarif.runs
	some result in run.results
	level_of(run, result) == "error"
	not baselined(run, result)
	msg := sprintf("[enforce-critical] %s at %s: %s", [rule_id_of(result), path_of(result), message_of(result)])
}

deny contains msg if {
	input.mode == "enforce-full"
	some run in input.sarif.runs
	some result in run.results
	not baselined(run, result)
	msg := sprintf("[enforce-full] %s at %s: %s", [rule_id_of(result), path_of(result), message_of(result)])
}

warn contains msg if {
	some run in input.sarif.runs
	some result in run.results
	baselined(run, result)
	msg := sprintf("[baseline] %s at %s: %s", [rule_id_of(result), path_of(result), message_of(result)])
}

warn contains msg if {
	some run in input.sarif.runs
	some result in run.results
	not baselined(run, result)
	not denied_level(level_of(run, result), input.mode)
	msg := sprintf("[%s] %s at %s: %s", [input.mode, rule_id_of(result), path_of(result), message_of(result)])
}
