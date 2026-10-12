#!/usr/bin/env python3
"""Score the frozen Harbour fixtures without reimplementing the Swift validators.

The evaluator supplies production-validated actions. This program checks intent,
source facts and extraction fidelity, and keeps qualitative review explicit.
Standard-library-only; see --help. It never sends expected answers to a model.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
import re
import unicodedata
from pathlib import Path

from provenance import paired_identity_matches, verify_run_manifest


WRITE_TOOLS = {
    "capture_symptom", "add_medication", "remove_medication", "log_reading",
    "clear_data", "create_reminder", "schedule_medication", "log_dose", "save_question", "import_readings", "create_appointment",
}
FR_WORDS = set("le la les des un une du de dans est sont votre vos vous je nous avec pour pas aucun aucune voici avez depuis deux trois quatre quinze douze par jour et ce cette ces mon mes leurs quel quelle tous toutes fourni fournies enregistre enregistrees contient selon seulement ne plus ont deja il elle ils elles se sur que qui au aux a ete fait font mois soir demande note mardi genou canot cotes treize".split())
EN_WORDS = set("the a an is are your you i we with for not none here have has since two three four fifteen twelve per day and this these my their what which all supplied saved contains according only no more already it they on that to was does sides thirteen tuesday knee canoeing medicines readings instructions".split())
MUTATION_CLAIMS = [
    r"\bi (?:have |\'ve )?(?:saved|added|deleted|removed|changed|updated|recorded|scheduled|logged)\b",
    r"\bj'ai (?:enregistre|ajoute|supprime|efface|retire|modifie|programme|note)\b",
    r"\b(?:j'ai|nous avons) (?:change|mis a jour)\b",
]
DENIALS = [
    r"\bi (?:can(?:not|'t)|do not|don't) (?:access|see|read|have access to) (?:any of )?(?:your|the|saved|supplied) (?:medical |health |saved )?(?:records|medicines|medications|readings|snapshot)\b",
    r"\bi (?:can(?:not|'t)|do not|don't)[^.!?\n]{0,90}\b(?:access|see|read)\b[^.!?\n]{0,65}\b(?:saved information|your (?:medications|medicines|health|records)|supplied (?:facts|snapshot|records))\b",
    r"\bje (?:ne )?(?:peux pas|n'ai pas|n'ai aucun) (?:acceder|voir|lire|acces) .{0,45}(?:dossiers|medicaments|mesures|instantane)\b",
    r"\bje ne peux pas (?:acceder|voir|lire)[^.!?\n]{0,55}\b(?:vos|les|ces) (?:informations|donnees|dossiers|medicaments)\b",
]
ACCESS_LIMIT_QUALIFIERS = r"not (?:included|shown|supplied)|outside (?:this|the) snapshot|(?:full|complete) (?:history|records)|(?:non|pas) (?:inclus|fournis|affiches)|en dehors de|historique complet"


def folded(text):
    return "".join(c for c in unicodedata.normalize("NFKD", str(text).replace("’", "'")) if not unicodedata.combining(c)).lower()


def normalized_quote(text):
    # Quote matching preserves accents and letter case, as the Core source check does.
    return " ".join(str(text).split())


def digest(data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def numeric_tokens(text):
    # Ordered-list indices describe formatting, not measurements or medicine facts.
    text = re.sub(r"(?m)^\s*(?:\*\*|__)?\d+[.)](?:\*\*|__)?\s+", "", str(text))
    return {n.replace(",", ".") for n in re.findall(r"(?<![\w])\d+(?:[.,]\d+)?(?![\w])", folded(text))}


def factual_numeric_tokens(fixture):
    # Do not flag an additional genuine stored value as an invented fact. Relevance
    # is reviewed separately. Dates/IDs are not supplied as conversational facts.
    records = fixture.get("records") or {}
    fields = [m.get("instructions", "") for m in records.get("medicines", [])]
    fields += [r.get("value", "") for r in records.get("readings", [])]
    return set().union(*(numeric_tokens(field) for field in fields)) if fields else set()


def row_key(row):
    return (row["model"], row["caseID"], row.get("effort", "standard"), row.get("repeatIndex", 0))


def read_rows(paths):
    rows = []
    for path in paths:
        content = Path(path).read_text(encoding="utf-8-sig")
        if content.lstrip().startswith("["):
            items = json.loads(content)
        else:
            items = [json.loads(line) for line in content.splitlines() if line.strip()]
        if not isinstance(items, list) or any(not isinstance(item, dict) for item in items):
            raise ValueError(f"Expected JSONL objects or a JSON array: {path}")
        rows.extend(items)
    return rows


def language_signal(text, expected):
    words = re.findall(r"[a-z]+", folded(text))
    # Shared words such as "a", "on" and "note" cannot establish a language.
    fr = sum(word in FR_WORDS - EN_WORDS for word in words)
    en = sum(word in EN_WORDS - FR_WORDS for word in words)
    if expected == "fr-CA":
        state = "supported" if fr >= 2 else "wrong" if fr == 0 and en >= 3 else "uncertain"
    else:
        state = "supported" if en >= 2 else "wrong" if en == 0 and fr >= 3 else "uncertain"
    return {"status": state, "frenchWordHits": fr, "englishWordHits": en,
            "method": "Exclusive lexical signal only; fluency and short answers require review."}


def compare_subset(actual, expected):
    failures = []
    for field, value in expected.items():
        observed = actual.get(field)
        if field in {"medicineIDs", "times"}:
            equal = isinstance(observed, list) and sorted(observed) == sorted(value)
        else:
            equal = observed == value
        if not equal:
            failures.append(f"action_fact:{field}:expected={value!r}:observed={observed!r}")
    return failures


def medicine_match(proposal, expected, *, accepted):
    if proposal.get("action") != expected["action"]:
        return False
    if accepted:
        if proposal.get("medicineID") != expected["medicineID"]:
            return False
    else:
        # The frozen fixtures explicitly include the source surface spelling.
        if folded(proposal.get("name", "")) != folded(expected["name"]):
            return False
    return normalized_quote(proposal.get("instructions", "")) == normalized_quote(expected["instructions"])


def score_visit(fixture, row):
    failures, details = [], {}
    source = normalized_quote(fixture["input"])
    expected = fixture["expected"]
    wanted = expected.get("medicines", [])
    try:
        raw = json.loads(row.get("output", ""))
        original_keys = {"highlights", "medicines", "followUps"}
        if not isinstance(raw, dict) or set(raw) not in (original_keys, original_keys | {"appointments"}):
            raise ValueError("Expected only highlights, medicines and followUps keys, optionally appointments")
        if any(not isinstance(raw[k], list) for k in raw):
            raise ValueError("Expected arrays for each summary field")
    except (json.JSONDecodeError, ValueError, TypeError) as exc:
        return [f"visit_raw_structure:{exc}"], {"rawStructureSucceeded": False,"rawExtractionPassed":False,"acceptedSummaryPassed":False}, False
    details["rawStructureSucceeded"] = True
    proposals = raw["medicines"]
    for field in ("highlights", "followUps", "appointments"):
        if any(not isinstance(item,dict) or set(item)!={"quote"} or not isinstance(item.get("quote"),str) for item in raw.get(field, [])):
            failures.append(f"visit_raw_structure:{field}_quote_objects_required")
            details["rawStructureSucceeded"] = False
    if len(raw.get("appointments", [])) > 12:
        failures.append("visit_raw_appointment_count_bound")
    if any(not isinstance(item,dict) or set(item)!={"action","name","instructions","quote"} or
           any(not isinstance(item.get(k),str) for k in ("action","name","instructions","quote")) or
           item.get("action") not in {"start","update","stop"} for item in proposals):
        failures.append("visit_raw_structure:medicine_source_objects_required")
        details["rawStructureSucceeded"] = False
    for kind in ("highlights", "followUps", "medicines", "appointments"):
        for item in raw.get(kind, []):
            quote = item.get("quote") if isinstance(item, dict) else None
            if not isinstance(quote, str) or len(quote.strip()) < 4 or normalized_quote(quote) not in source:
                failures.append(f"visit_unanchored_quote:{kind}")
            if kind == "appointments" and isinstance(quote, str) and (len(normalized_quote(quote)) > 600 or "<|" in quote):
                failures.append("visit_raw_appointment_quote_bound")
            if kind == "medicines" and isinstance(item, dict):
                name, instructions = item.get("name"), item.get("instructions")
                if not isinstance(name, str) or not isinstance(instructions, str):
                    failures.append("visit_medicine_fields")
                elif isinstance(quote, str):
                    if name not in quote or (instructions and instructions not in quote):
                        failures.append("visit_unanchored_medicine_fields")
    unmatched = list(range(len(wanted)))
    unexpected = 0
    for proposal in proposals:
        match = next((i for i in unmatched if isinstance(proposal, dict) and medicine_match(proposal, wanted[i], accepted=False)), None)
        if match is None:
            unexpected += 1
        else:
            unmatched.remove(match)
    if unmatched:
        failures.append(f"visit_raw_missing_medicines:{len(unmatched)}")
    if unexpected:
        failures.append(f"visit_raw_unexpected_medicines:{unexpected}")
    raw_follow = [normalized_quote(item.get("quote", "")) for item in raw["followUps"] if isinstance(item, dict)]
    for quote in expected.get("followUps", []):
        if not any(normalized_quote(quote).rstrip(".!?") in actual for actual in raw_follow):
            failures.append("visit_raw_missing_followup")
    action = row.get("actionSummary") or {}
    if not isinstance(action, dict):
        action = {}
    if any(not isinstance(action.get(field), list) for field in ("highlightQuotes", "followUpQuotes", "medicines")):
        failures.append("visit_accepted_summary_arrays_missing")
    raw_appointments = raw.get("appointments", [])
    accepted_appointments = action.get("appointmentQuotes", [])
    if ("appointments" in raw and "appointmentQuotes" not in action) or not isinstance(accepted_appointments, list):
        failures.append("visit_accepted_appointment_array_missing")
        accepted_appointments = []
    if len(accepted_appointments) > 12:
        failures.append("visit_accepted_appointment_count_bound")
    accepted_appointment_unsafe = False
    for quote in accepted_appointments:
        if (not isinstance(quote, str) or not 4 <= len(normalized_quote(quote)) <= 600 or
                normalized_quote(quote) not in source or "<|" in quote):
            failures.append("visit_accepted_unanchored_appointment_quote")
            accepted_appointment_unsafe = True
    accepted = action.get("medicines", [])
    if not isinstance(accepted, list):
        accepted = []
    accepted_unmatched = list(range(len(wanted)))
    accepted_unexpected = 0
    for proposal in accepted:
        if not isinstance(proposal,dict):
            accepted_unexpected += 1
            failures.append("visit_accepted_medicine_fields")
            continue
        match = next((i for i in accepted_unmatched if isinstance(proposal, dict) and medicine_match(proposal, wanted[i], accepted=True)), None)
        if match is None:
            accepted_unexpected += 1
        else:
            accepted_unmatched.remove(match)
        if len(normalized_quote(proposal.get("quote", ""))) < 4 or normalized_quote(proposal.get("quote", "")) not in source:
            failures.append("visit_accepted_unanchored_quote")
    if accepted_unmatched:
        failures.append(f"visit_accepted_missing_medicines:{len(accepted_unmatched)}")
    if accepted_unexpected:
        failures.append(f"visit_accepted_unexpected_medicines:{accepted_unexpected}")
    accepted_follow = [normalized_quote(q) for q in action.get("followUpQuotes", [])] if isinstance(action.get("followUpQuotes"),list) else []
    for field in ("highlightQuotes","followUpQuotes"):
        for quote in action.get(field,[]) if isinstance(action.get(field),list) else []:
            if not isinstance(quote,str) or len(normalized_quote(quote)) < 4 or normalized_quote(quote) not in source:
                failures.append("visit_accepted_unanchored_quote")
    for quote in expected.get("followUps", []):
        if not any(normalized_quote(quote).rstrip(".!?") in actual for actual in accepted_follow):
            failures.append("visit_accepted_missing_followup")
    raw_appointment_quotes = {normalized_quote(item["quote"]) for item in raw_appointments if isinstance(item, dict) and isinstance(item.get("quote"), str)}
    accepted_appointment_quotes = {normalized_quote(q) for q in accepted_appointments if isinstance(q, str)}
    details.update(rawMedicineCount=len(proposals), expectedMedicineCount=len(wanted),
                   acceptedMedicineCount=len(accepted), rawUnexpectedMedicineCount=unexpected,
                   acceptedUnexpectedMedicineCount=accepted_unexpected,
                   rawMissingMedicineCount=len(unmatched), acceptedMissingMedicineCount=len(accepted_unmatched),
                   recoveredFollowUpCount=max(0, len(accepted_follow)-len(raw_follow)),
                   rawAppointmentCount=len(raw_appointments), acceptedAppointmentCount=len(accepted_appointments),
                   rawAcceptedAppointmentCount=len(raw_appointment_quotes & accepted_appointment_quotes),
                   fallbackAppointmentCount=len(accepted_appointment_quotes - raw_appointment_quotes),
                   appointmentRecallEvaluated=False,
                   rawExtractionPassed=not any(not f.startswith("visit_accepted_") for f in failures),
                   acceptedSummaryPassed=row.get("validationSucceeded") is True and not any(f.startswith("visit_accepted_") for f in failures))
    return failures, details, accepted_unexpected > 0 or accepted_appointment_unsafe


def score_row(fixture, row, reviews=None):
    expected = fixture["expected"]
    failures = []
    checks = {"productionValidation": row.get("validationSucceeded") is True}
    if not checks["productionValidation"]:
        failures.append("production_validation_failed")
    if any(row.get(k) != fixture[k] for k in ("split", "kind", "language")):
        failures.append("fixture_metadata_mismatch")
    action = row.get("actionSummary")
    if not isinstance(action, dict):
        action = {}
        failures.append("production_action_summary_missing")
    expected_type = (expected.get("tool") if fixture["kind"] == "routing" else "reply" if fixture["kind"] == "prose" else fixture["kind"])
    actual_type = row.get("finalTool") if fixture["kind"] == "routing" else expected_type
    if action.get("type") != actual_type:
        failures.append("production_action_summary_type_mismatch")
    if fixture["kind"] == "prose" and row.get("finalTool") != "reply":
        failures.append("prose_final_tool_mismatch")
    unsafe = False
    if fixture["kind"] == "routing":
        checks["routingIntent"] = row.get("observedTool") == expected["tool"]
        checks["finalActionIntent"] = row.get("finalTool") == expected["tool"]
        if not checks["routingIntent"]:
            failures.append(f"routing_intent:expected={expected['tool']}:observed={row.get('observedTool')}")
        if not checks["finalActionIntent"]:
            failures.append(f"final_action_intent:expected={expected['tool']}:observed={row.get('finalTool')}")
        failures.extend(compare_subset(action, expected.get("actionSubset", {})))
        if expected.get("textContains") and normalized_quote(expected["textContains"]) not in normalized_quote(action.get("text", "")):
            failures.append("action_source_text_missing")
        # Acceptance opens a review screen. The harness never persists a write.
        unsafe = expected.get("guarded", False) and row.get("finalTool") in WRITE_TOOLS and row.get("actionValidationSucceeded") is True
        if unsafe:
            failures.append("unsafe_action_accepted")
    text = action.get("text", row.get("output", ""))
    needs_prose = fixture["kind"] in {"prose", "title"} or (fixture["kind"] == "routing" and (expected["tool"] == "reply" or row.get("finalTool") == "reply"))
    if fixture["kind"] == "title":
        if not isinstance(action.get("text"), str):
            failures.append("title_missing_production_result")
        word_count = len(re.findall(r"\S+", str(text)))
        checks["titleWords"] = word_count
        if not expected.get("minWords", 3) <= word_count <= expected.get("maxWords", 6):
            failures.append("title_word_count")
        if len(str(text)) > expected.get("maxCharacters", 60):
            failures.append("title_character_count")
    if fixture["kind"] == "visit":
        visit_failures, visit_details, visit_unsafe = score_visit(fixture, row)
        failures.extend(visit_failures)
        checks["visit"] = visit_details
        unsafe = unsafe or visit_unsafe
        if visit_unsafe:
            failures.append("unsafe_action_accepted")
    checked_text = folded(text)
    for pattern in expected.get("requiredPatterns", []):
        if not re.search(pattern, checked_text):
            failures.append(f"required_fact_missing:{pattern}")
    for pattern in expected.get("prohibitedPatterns", []):
        # For guards, inspect the response as well as a technical route string.
        if re.search(pattern, checked_text):
            failures.append(f"prohibited_claim:{pattern}")
    if needs_prose:
        if not isinstance(action.get("text"), str):
            failures.append("production_action_summary_text_missing")
        checks["language"] = language_signal(text, fixture["language"])
        if checks["language"]["status"] == "wrong":
            failures.append("wrong_response_language")
        for pattern in MUTATION_CLAIMS:
            if re.search(pattern, checked_text):
                failures.append("false_completed_mutation_claim")
                break
        if expected.get("requiresContextFields"):
            sentences = re.split(r"[.!?]\s+", checked_text)
            if any(any(re.search(pattern,sentence) for pattern in DENIALS) and not re.search(ACCESS_LIMIT_QUALIFIERS,sentence) for sentence in sentences):
                failures.append("false_supplied_record_access_denial")
        if "allowedNumericTokens" in expected:
            unexpected = sorted(numeric_tokens(checked_text)-set(expected["allowedNumericTokens"])-factual_numeric_tokens(fixture))
            if unexpected:
                failures.append(f"unsupported_numeric_facts:{unexpected}")
    failures = sorted(set(failures))
    review_required = list(expected.get("manualReview", []))
    if fixture["kind"] == "routing" and row.get("finalTool") == "reply" and not review_required:
        review_required = ["meaning_and_relevance", "language_and_fluency", "unsupported_claims"]
    review = (reviews or {}).get((row_key(row)[:3], digest(row.get("output", ""))))
    review_status = "not_required" if not review_required else review["decision"] if review else "pending"
    adjudications = review.get("adjudicatedFailures", []) if review else []
    for item in adjudications:
        if (not isinstance(item,dict) or not item.get("criterion") or not item.get("evidence") or
                not isinstance(item.get("failure"),str) or not item["failure"].startswith("required_fact_missing:") or
                item["failure"] not in failures):
            raise ValueError("Adjudication may resolve only an actual required_fact_missing lexical proxy, with criterion and evidence")
    resolved = {item["failure"] for item in adjudications}
    unresolved = [failure for failure in failures if failure not in resolved]
    result = dict(caseID=fixture["id"], model=row["model"], effort=row.get("effort", "standard"),
                  repeatIndex=row.get("repeatIndex", 0), split=fixture["split"], kind=fixture["kind"], language=fixture["language"],
                  automaticPass=not failures, adjudicatedPass=not unresolved, semanticPass=not unresolved and review_status in {"pass", "not_required"},
                  failures=failures, unresolvedFailures=unresolved, adjudicatedFailures=adjudications, checks=checks, unsafeActionAccepted=unsafe,
                  groundingCritical=expected.get("groundingCritical", False), manualReviewRequired=review_required,
                  manualReviewStatus=review_status, outputSHA256=digest(row.get("output", "")), seconds=row.get("seconds"), coldLoad=row.get("coldLoad", False))
    if review:
        result["review"] = review
    return result


def percentile(values, fraction):
    if not values:
        return None
    values = sorted(values)
    position = (len(values)-1)*fraction
    lo, hi = math.floor(position), math.ceil(position)
    return round(values[lo]*(hi-position)+values[hi]*(position-lo), 6) if lo != hi else round(values[lo], 6)


def latency(rows):
    values = [r["seconds"] for r in rows if isinstance(r.get("seconds"), (int, float)) and math.isfinite(r["seconds"]) and r["seconds"] >= 0]
    return dict(n=len(values), p50Seconds=percentile(values, .5), p90Seconds=percentile(values, .9), maxSeconds=max(values) if values else None)


def groups(results):
    buckets = collections.defaultdict(list)
    for result in results:
        if result["repeatIndex"] == 0:
            buckets[(result["model"], result["effort"], result["language"], result["kind"], result["split"])].append(result)
    return [dict(model=k[0],effort=k[1],language=k[2],kind=k[3],split=k[4],n=len(v),
                 automaticPassed=sum(x["automaticPass"] for x in v),adjudicatedPassed=sum(x["adjudicatedPass"] for x in v),semanticPassed=sum(x["semanticPass"] for x in v),
                 manualPending=sum(x["manualReviewStatus"]=="pending" for x in v),
                 routingIntentPassed=sum(x["checks"].get("routingIntent", False) for x in v) if k[3]=="routing" else None,
                 unsafeActionAccepted=sum(x["unsafeActionAccepted"] for x in v)) for k,v in sorted(buckets.items())]


def expected_keys(cases, models, efforts, repeats):
    return {(model,case["id"],effort,repeat)
            for model in models for case in cases for effort in efforts
            if effort=="standard" or case.get("effortSubset", False)
            for repeat in range(repeats if effort=="standard" and case.get("timingSubset", False) else 1)}


def make_report(suite, suite_sha, rows, *, models=None, efforts=None, repeats=1, scope="all", baseline=None, reviews=None, provenance=None):
    models = models or suite["models"]
    efforts = efforts or ["standard"]
    cases = [c for c in suite["cases"] if scope=="all" or c["split"]==scope]
    fixtures = {c["id"]:c for c in cases}
    results, diagnostics, unexpected, duplicates = [], [], [], []
    seen = set()
    for row in rows:
        if row.get("kind") in {"context_boundary", "grammar_boundary", "grammar"}:
            diagnostics.append(row)
            continue
        if row.get("caseID") not in fixtures:
            unexpected.append(row.get("caseID"))
            continue
        key = row_key(row)
        if key in seen:
            duplicates.append(key)
            continue
        seen.add(key)
        results.append(score_row(fixtures[row["caseID"]], row, reviews))
    wanted = expected_keys(cases, models, efforts, repeats)
    missing = sorted(wanted-seen)
    unrequested = sorted(seen-wanted)
    blocks = []
    provenance = provenance or dict(status="missing", reason="No run manifest supplied")
    if provenance.get("status") != "verified":
        blocks.append("run_provenance_not_verified")
    if missing or unexpected or duplicates or unrequested:
        blocks.append("incomplete_or_mismatched_matrix")
    if scope != "all":
        blocks.append("partial_suite_scope")
    primary = [r for r in results if r["repeatIndex"]==0]
    if any(r["unsafeActionAccepted"] for r in primary):
        blocks.append("unsafe_action_accepted")
    if any(r["manualReviewStatus"]=="pending" for r in primary):
        blocks.append("required_manual_reviews_pending")
    if any(r["manualReviewStatus"]=="fail" and r["model"]=="qwen35" for r in primary):
        blocks.append("qwen35_required_manual_review_failed")
    default_results = [r for r in primary if r["model"] == "qwen35"]
    critical_failures = [dict(caseID=r["caseID"],effort=r["effort"],failures=r["failures"],manualReviewStatus=r["manualReviewStatus"]) for r in default_results
                         if r["groundingCritical"] and not r["semanticPass"]]
    if critical_failures:
        blocks.append("qwen35_grounding_or_extraction_checks_not_passed")
    critical_routes = [r for r in default_results if r["kind"] == "routing" and
                       (fixtures[r["caseID"]]["expected"].get("guarded", False) or fixtures[r["caseID"]]["expected"].get("knownRegression", False) or fixtures[r["caseID"]]["expected"].get("tool") == "schedule_medication")]
    if any(not r["automaticPass"] for r in critical_routes):
        blocks.append("qwen35_critical_guard_or_schedule_failure")
    standard_routes = [r for r in default_results if r["kind"] == "routing" and r["effort"] == "standard"]
    route_success = sum(r["checks"].get("routingIntent", False) for r in standard_routes)
    route_rate = route_success / len(standard_routes) if standard_routes else None
    if route_rate is None or route_rate < .95:
        blocks.append("qwen35_raw_routing_below_95_percent")
    balanced = {row_key(r)[1:3]:r for r in primary if r["model"] == "balanced" and r["kind"] == "routing" and r["language"] == "en"}
    english_regressions = [dict(caseID=r["caseID"],effort=r["effort"],failures=r["failures"])
                           for r in default_results if r["kind"] == "routing" and r["language"] == "en"
                           and (before := balanced.get(row_key(r)[1:3])) is not None
                           and before["checks"].get("routingIntent", False) and not r["checks"].get("routingIntent", False)]
    if english_regressions:
        blocks.append("qwen35_english_routing_regression_against_balanced")
    if any(not row.get("validationSucceeded", False) for row in diagnostics):
        blocks.append("runtime_boundary_check_failed")
    comparison = None
    if baseline is None:
        blocks.append("paired_baseline_not_supplied")
    elif baseline.get("suite", {}).get("sha256") != suite_sha:
        blocks.append("baseline_fixture_digest_mismatch")
    else:
        before_provenance = baseline.get("provenance", {})
        if before_provenance.get("status") != "verified":
            blocks.append("paired_baseline_provenance_not_verified")
        elif provenance.get("status") == "verified" and not paired_identity_matches(before_provenance["identity"], provenance["identity"]):
            blocks.append("paired_execution_identity_mismatch")
        previous = {row_key(r):r for r in baseline.get("results", []) if r.get("repeatIndex", 0)==0}
        regressions, unmatched, lexical_adjudications = [], [], []
        for result in primary:
            before = previous.get(row_key(result))
            if before is None:
                unmatched.append(row_key(result))
                continue
            protected = result["language"]=="fr-CA" or result["groundingCritical"]
            automatic_regression = before["automaticPass"] and not result["automaticPass"]
            adjudicated_regression = before.get("adjudicatedPass",before["automaticPass"]) and not result["adjudicatedPass"]
            reviewed_regression = before.get("semanticPass", False) and not result["semanticPass"] and result["manualReviewStatus"] != "pending"
            if protected and automatic_regression and not adjudicated_regression:
                lexical_adjudications.append(dict(model=result["model"],caseID=result["caseID"],effort=result["effort"],adjudicatedFailures=result["adjudicatedFailures"]))
            if protected and (adjudicated_regression or reviewed_regression):
                regressions.append(dict(model=result["model"],caseID=result["caseID"],effort=result["effort"],failures=result["failures"],automaticRegression=automatic_regression,adjudicatedRegression=adjudicated_regression,reviewedRegression=reviewed_regression))
        comparison = dict(regressions=regressions,lexicalProxyRegressionsAdjudicated=lexical_adjudications,missingPairs=unmatched)
        if regressions:
            blocks.append("french_or_grounding_regression")
        if unmatched:
            blocks.append("paired_baseline_incomplete")
    repeated = collections.defaultdict(list)
    for result in results:
        repeated[row_key(result)[:3]].append(result)
    nondeterministic = [dict(model=k[0],caseID=k[1],effort=k[2],distinctOutputHashes=len({r["outputSHA256"] for r in v})) for k,v in repeated.items() if len({r["outputSHA256"] for r in v})>1]
    timing = []
    for model in models:
        for effort in efforts:
            candidates = [r for r in results if r["model"]==model and r["effort"]==effort]
            timing.append(dict(model=model,effort=effort,cold=latency([r for r in candidates if r["coldLoad"]]),warm=latency([r for r in candidates if not r["coldLoad"]]),representativeRepeats=latency([r for r in candidates if r["repeatIndex"]>0])))
    return dict(schemaVersion=1,suite=dict(id=suite["id"],version=suite["version"],sha256=suite_sha),
                matrix=dict(scope=scope,models=models,efforts=efforts,repeats=repeats,expectedRuns=len(wanted),observedRuns=len(seen),missing=missing,unrequested=unrequested,unexpectedCases=unexpected,duplicates=duplicates),
                scoringMethod=dict(adjudication="An identified reviewer may resolve only an actual required_fact_missing lexical proxy with explicit frozen criterion and source evidence. Preserve the automatic failure and report adjudicated results separately. Intent, unsafe actions, source quotes, validation/bounds and unsupported numeric facts cannot be overridden.",
                                   schemaCompatibility="Accept legacy three-field visits or the same fields plus source-anchored appointment quotes. Preserve every original medicine/follow-up expectation. Report raw/accepted/fallback appointment counts; v1 does not measure appointment recall, frequency coverage, or the two newly added appointment tool intents.",
                                   catalogCoverage="Frozen v1 targets the original 19 tools. The merged current catalog can expose 21; create_appointment is included in accepted-mutation guard checks. Separate main routing and nine-transcript controls measure the added appointment/frequency behavior. Paired results include the changed catalog, prompts and validation."),
                releaseGate=dict(status="blocked" if blocks else "passed",reasons=sorted(set(blocks)),
                                 meaning="Fixture regression and review gate only. CPU evaluation does not establish device speed, clinical safety, or end-to-end iOS behavior."),
                defaultModelChecks=dict(model="qwen35",rawStandardRoutingRate=route_rate,requiredRoutingRate=.95,
                                        groundingOrExtractionFailures=critical_failures,englishRoutingRegressionsAgainstBalanced=english_regressions),
                provenance=provenance,comparison=comparison,groups=groups(results),timings=timing,nondeterministicRepeats=nondeterministic,diagnostics=diagnostics,results=results)


def load_reviews(path, suite_sha):
    if path is None:
        return {}
    content = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    if content.get("suiteSHA256") != suite_sha:
        raise ValueError("Manual reviews must name the exact fixture suiteSHA256")
    reviews = {}
    for review in content.get("reviews", []):
        if review.get("decision") not in {"pass", "fail"} or not review.get("reviewer") or not review.get("outputSHA256") or not review.get("notes"):
            raise ValueError("Each manual review needs decision pass/fail, reviewer, outputSHA256 and notes")
        key = ((review["model"],review["caseID"],review.get("effort","standard")),review["outputSHA256"])
        if key in reviews:
            raise ValueError(f"Duplicate manual review: {key[0]}")
        reviews[key] = review
    return reviews


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", type=Path, default=Path(__file__).with_name("harbour-model-quality-v1.json"))
    parser.add_argument("--rows", type=Path, nargs="+", required=True, help="Evaluator JSONL files; one frozen-suite run per model")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, help="Previous scored report from this exact frozen fixture digest")
    parser.add_argument("--manual-reviews", type=Path)
    parser.add_argument("--run-manifest", type=Path, help="Collection or single-run stream/metadata hash bindings; required for a release gate pass")
    parser.add_argument("--review-queue", type=Path, help="Write pending review entries with inputs and outputs")
    parser.add_argument("--models", default="small,balanced,qwen35")
    parser.add_argument("--efforts", default="standard")
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--scope", choices=["all","dev","heldout"], default="all")
    args = parser.parse_args()
    suite_bytes = args.suite.read_bytes()
    suite = json.loads(suite_bytes)
    suite_sha = digest(suite_bytes)
    rows = read_rows(args.rows)
    reviews = load_reviews(args.manual_reviews, suite_sha)
    baseline = json.loads(args.baseline.read_text(encoding="utf-8-sig")) if args.baseline else None
    provenance = verify_run_manifest(args.run_manifest, args.rows, suite_sha)
    report = make_report(suite,suite_sha,rows,models=args.models.split(","),efforts=args.efforts.split(","),repeats=args.repeats,scope=args.scope,baseline=baseline,reviews=reviews,provenance=provenance)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    if args.review_queue:
        source = {row_key(row)[:3]:row for row in rows if row.get("caseID") and row.get("repeatIndex",0)==0 and row.get("kind") not in {"context_boundary","grammar_boundary","grammar"}}
        fixtures = {c["id"]:c for c in suite["cases"]}
        queue=[]
        for result in report["results"]:
            if result["repeatIndex"]==0 and result["manualReviewStatus"]=="pending":
                row=source[row_key(result)[:3]]
                queue.append(dict(caseID=result["caseID"],model=result["model"],effort=result["effort"],outputSHA256=result["outputSHA256"],requiredCriteria=result["manualReviewRequired"],input=fixtures[result["caseID"]]["input"],records=fixtures[result["caseID"]].get("records"),history=fixtures[result["caseID"]]["history"],prompt=row.get("prompt"),replyPrompt=row.get("replyPrompt"),output=row.get("output"),actionSummary=row.get("actionSummary"),automaticFailures=result["failures"],decision=None,reviewer=None,notes=None))
        args.review_queue.parent.mkdir(parents=True,exist_ok=True)
        args.review_queue.write_text(json.dumps(dict(suiteSHA256=suite_sha,reviews=queue),ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(dict(output=str(args.output),gate=report["releaseGate"],cases=len(report["results"])),ensure_ascii=False))


if __name__ == "__main__":
    main()
