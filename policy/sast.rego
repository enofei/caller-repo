package main

# SAST policy gate.
#
# Input shape (built by the reusable policy workflow):
#   {"mode": "warn" | "enforce-critical" | "enforce-full", "sarif": <semgrep SARIF>}
#
# Semantics:
#   warn             -> no deny; all findings surface as warnings
#   enforce-critical -> deny first-party findings at SARIF level "error"
#   enforce-full     -> deny all first-party findings (any level)
#   dvwa/**          -> never denied (third-party vendor code), surfaced as warnings
#
# Malformed input or an unknown mode denies (fail-closed).

valid_modes := {"warn", "enforce-critical", "enforce-full"}

valid_mode(m) if m in valid_modes

wellformed if {
	is_array(input.sarif.runs)
	count(input.sarif.runs) > 0
	run0 := input.sarif.runs[0]
	is_array(object.get(run0, "results", null))
	is_array(object.get(run0.tool.driver, "rules", null))
}

results := object.get(input.sarif.runs[0], "results", [])

# Result-level severity is authoritative when present; otherwise resolve it
# from the rule descriptor's defaultConfiguration.level (Semgrep's usual
# shape), falling back to "warning".
level_of(result) := level if {
	level := result.level
} else := level if {
	some rule in input.sarif.runs[0].tool.driver.rules
	rule.id == result.ruleId
	level := rule.defaultConfiguration.level
} else := "warning"

rule_id_of(result) := object.get(result, "ruleId", "<unknown-rule>")

message_of(result) := text if {
	text := result.message.text
} else := "<no message>"

path_of(result) := uri if {
	some location in result.locations
	uri := location.physicalLocation.artifactLocation.uri
} else := "<unknown-path>"

exempt_path(path) if regex.match(`(?:^|/)dvwa/`, path)

denied_level(level, "enforce-critical") if level == "error"

denied_level(level, "enforce-full") if level in {"error", "warning", "note"}

# --- fail-closed guards ---

deny contains msg if {
	not wellformed
	msg := "gate input malformed: expected sarif.runs[0].results"
}

deny contains msg if {
	not valid_mode(input.mode)
	msg := sprintf("gate mode invalid: %v", [input.mode])
}

# --- enforce-critical: first-party findings at level error ---

deny contains msg if {
	input.mode == "enforce-critical"
	some result in results
	level_of(result) == "error"
	path := path_of(result)
	not exempt_path(path)
	msg := sprintf("[enforce-critical] %s at %s: %s", [rule_id_of(result), path, message_of(result)])
}

# --- enforce-full: every first-party finding ---

deny contains msg if {
	input.mode == "enforce-full"
	some result in results
	path := path_of(result)
	not exempt_path(path)
	msg := sprintf("[enforce-full] %s (%s) at %s: %s", [rule_id_of(result), level_of(result), path, message_of(result)])
}

# --- warnings: exempt findings are always visible ---

warn contains msg if {
	some result in results
	path := path_of(result)
	exempt_path(path)
	msg := sprintf("[exempt-dvwa] %s (%s): %s", [rule_id_of(result), level_of(result), message_of(result)])
}

# --- warnings: findings not denied in the current mode stay visible ---

warn contains msg if {
	some result in results
	path := path_of(result)
	not exempt_path(path)
	not denied_level(level_of(result), input.mode)
	msg := sprintf("[%s] %s at %s: %s", [input.mode, rule_id_of(result), path, message_of(result)])
}
