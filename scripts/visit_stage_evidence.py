"""Bind staged visit evidence without changing any quality criterion or verdict."""
import hashlib
import json


OUTPUT_KIND = "application_assembled_model_stages"


def text_sha(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def object_sha(value):
    return text_sha(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")))


def require(value, message):
    if not value:
        raise ValueError("Visit stage evidence: " + message)


def bind_visit_stages(row, *, raw_output_field="output"):
    """Extra stage provenance; the unchanged scorer does not verify this layer.

    Incomplete attempts remain valid evidence of failure. Completed assemblies
    must retain every actual generation and agree with the recorded decisions.
    This function never grades the medical meaning of any generated object.
    """
    trace = row.get("visitExtractionTrace")
    require(raw_output_field in {"output", "rawOutput"}, "unknown caller output schema")
    staged = row.get("outputKind") == OUTPUT_KIND
    if not staged:
        require(trace is None, "trace present without staged-output attribution")
        return None
    require(row.get("kind") == "visit" and isinstance(trace, dict), "missing visit trace")
    require(trace.get("outputOrigin") == OUTPUT_KIND, "trace origin mismatch")
    stages = trace.get("stages")
    require(isinstance(stages, list), "missing stage list")
    bindings, ids, models = [], [], []
    for stage in stages:
        request = stage.get("request", {})
        stage_id = request.get("id")
        require(isinstance(stage_id, str) and stage_id and stage_id not in ids, "missing or duplicate stage id")
        ids.append(stage_id)
        require(isinstance(request.get("unitIDs"), list), "missing stage unit ids")
        require(isinstance(request.get("prompt"), str) and request["prompt"], "missing logical prompt")
        require(isinstance(request.get("grammar"), str) and request["grammar"], "missing actual grammar")
        require(request.get("maximumTokens") == 650, "unexpected per-call token maximum")
        generation = stage.get("generation")
        binding = dict(id=stage_id, unitIDs=request["unitIDs"], maximumTokens=request["maximumTokens"],
                       logicalPromptSHA256=text_sha(request["prompt"]), grammarSHA256=text_sha(request["grammar"]))
        if generation is not None:
            require(isinstance(generation, dict), "invalid generation")
            require(isinstance(generation.get("output"), str), "missing actual raw output")
            require(isinstance(generation.get("preparedPrompt"), str) and generation["preparedPrompt"], "missing actual prepared prompt")
            require(isinstance(generation.get("modelID"), str) and generation["modelID"], "missing actual model id")
            models.append(generation["modelID"])
            binding.update(preparedPromptSHA256=text_sha(generation["preparedPrompt"]),
                           outputSHA256=text_sha(generation["output"]), modelID=generation["modelID"],
                           configuration=generation.get("configuration", {}), promptTokens=generation.get("promptTokens"))
        else:
            require(isinstance(stage.get("error"), str) and stage["error"], "unexplained missing generation")
        binding["errorSHA256"] = text_sha(stage["error"]) if stage.get("error") else None
        bindings.append(binding)
    if trace.get("completed") is True:
        require(stages and not trace.get("errors") and trace.get("classificationCoverageComplete") is True, "incomplete successful trace")
        require(all(s.get("generation") is not None and not s.get("error") for s in stages), "successful trace lost a generation")
        require(len(set(models)) == 1 and trace.get("modelID") == models[0], "model changed between stages")
        units = trace.get("units", [])
        unit_ids = [unit.get("id") for unit in units]
        require(unit_ids and len(set(unit_ids)) == len(unit_ids), "missing or duplicate source units")
        decisions = trace.get("classifications", [])
        require([value.get("id") for value in decisions] == unit_ids, "classification coverage mismatch")
        first = stages[0]
        require(first["request"]["id"] == "classify" and first["request"]["unitIDs"] == unit_ids, "classifier source mismatch")
        raw_decisions = json.loads(first["generation"]["output"])
        require(raw_decisions.get("units") == decisions, "classification differs from actual raw output")
        selected = [value["id"] for value in decisions if value.get("kinds") != ["none"]]
        require(ids == ["classify"] + ["extract." + str(value) for value in selected], "missing or unexpected extraction stage")
        require([s["request"]["unitIDs"] for s in stages[1:]] == [[value] for value in selected], "extraction source binding mismatch")
        require(row.get(raw_output_field) == trace.get("assembledOutput"), "row assembly differs from trace")
    return dict(caseID=row["caseID"], effort=row.get("effort"), repeatIndex=row.get("repeatIndex", 0),
                outputKind=OUTPUT_KIND, primaryOutputField=raw_output_field, traceSHA256=object_sha(trace), completed=trace.get("completed") is True,
                generationCalls=len(stages), maximumRequestedTokens=sum(s["request"]["maximumTokens"] for s in stages),
                stages=bindings)
