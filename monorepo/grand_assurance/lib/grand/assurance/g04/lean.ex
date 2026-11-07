defmodule Grand.Assurance.G04.Lean do
  @moduledoc """
  Scoped Lean 4 source-law adapter. A supplied law is NOT linked to the target
  implementation by running Lean; the G03 source references remain conditional.
  `lean Law.lean` requires explicit --execute AND --allow-law-code. For an
  axiom-free result the file must request `#print axioms LawName` and Lean must
  report the named theorem has no axioms. This is not a Lynx compatibility claim.
  """

  @behaviour Grand.Assurance.G04.Verifier
  alias Grand.Assurance.G04.Files
  alias Grand.Assurance.G04.Runner

  @impl true
  def prepare(%{"law" => law}, _opts) when is_map(law) do
    with %{"file" => file, "theorem" => theorem, "hypotheses" => hypotheses} <- law,
         true <-
           Files.identifier?(theorem) and is_list(hypotheses) and
             Enum.all?(hypotheses, &(is_binary(&1) and byte_size(&1) <= 300)),
         {:ok, source} <- Files.load(file, ".lean"),
         true <- contains_law?(source["bytes"], theorem) do
      {:ok,
       %{
         "engine" => "lean",
         "args" => ["Law.lean"],
         "files" => %{"Law.lean" => source["bytes"]},
         "source_files" => %{"law" => source["identity"]},
         "property" => theorem,
         "qualifications" => %{
           "kind" => "source_linked_lean_law",
           "law_origin" => Map.get(law, "origin", "user_supplied_law"),
           "hypotheses" => hypotheses,
           "target_runtime_checked" => false,
           "lynx_law_bundle_qualified" => false,
           "lean_macro_execution_requires_extra_opt_in" => true
         }
       }}
    else
      false -> {:error, :invalid_or_unlinked_lean_law}
      _ -> {:error, :invalid_lean_law}
    end
  end

  def prepare(_, _), do: {:error, :invalid_lean_law}

  @impl true
  def execute(plan, opts) do
    cond do
      not Keyword.get(opts, :execute, false) ->
        {:ok, Runner.skipped("unrun")}

      not Keyword.get(opts, :allow_law_code, false) ->
        {:error, :explicit_law_code_permission_required}

      true ->
        with {:ok, version} <-
               Runner.execute(
                 %{"engine" => "lean", "args" => ["--version"], "files" => %{}},
                 opts
               ) do
          execute_versioned(plan, opts, version)
        end
    end
  end

  defp execute_versioned(_plan, _opts, %{"reason" => "missing_engine"} = version),
    do: {:ok, version}

  defp execute_versioned(
         plan,
         opts,
         %{"reason" => nil, "exit_code" => 0, "stdout" => output} = version
       ) do
    if String.starts_with?(String.trim(output), "Lean (version ") do
      with {:ok, actual} <- Runner.execute(plan, opts) do
        {:ok, Map.put(actual, "version_output", String.trim(output))}
      end
    else
      {:ok, Map.put(version, "reason", "invalid_engine_version")}
    end
  end

  defp execute_versioned(_plan, _opts, version),
    do: {:ok, Map.put(version, "reason", "engine_version_probe_failed")}

  @impl true
  def normalize(plan, raw) do
    output = raw["stdout"] || ""
    expected = "'#{plan["property"]}' does not depend on any axioms"
    version = Map.get(raw, "version_output", "not_qualified")
    version_qualified = String.starts_with?(version, "Lean (version ")

    {status, diagnostics} = classify(raw, version_qualified, output, expected)

    {:ok,
     %{
       "status" => status,
       "engine_version" => version,
       "diagnostics" => diagnostics,
       "counterexample" => nil
     }}
  end

  defp classify(%{"reason" => "unrun"}, _, _, _), do: {"unrun", ["execution was not requested"]}

  defp classify(%{"reason" => "missing_engine"}, _, _, _),
    do: {"unsupported", ["Lean executable unavailable"]}

  defp classify(%{"reason" => reason}, _, _, _) when reason in ["timeout", "cancelled"],
    do: {"inconclusive", [reason]}

  defp classify(%{"reason" => reason}, _, _, _) when is_binary(reason), do: {"error", [reason]}

  defp classify(%{"exit_code" => 0}, true, output, expected),
    do: normalize_success(output, expected)

  defp classify(%{"exit_code" => 0}, false, _, _),
    do: {"error", ["Lean version probe missing or unqualified"]}

  defp classify(_, _, _, _),
    do: {"error", ["Lean rejected the law or exited abnormally; not a counterexample"]}

  defp contains_law?(source, theorem) do
    local_name = theorem |> String.split(".") |> List.last()
    definition = Regex.compile!("\\b(?:theorem|lemma)\\s+#{Regex.escape(local_name)}\\b")
    Regex.match?(definition, source) and String.contains?(source, "#print axioms #{theorem}")
  end

  defp normalize_success(output, expected) do
    # Require the complete line from #print axioms, not an arbitrary substring
    # or compiler success. Explicit sorry/axiom diagnostics veto acceptance.
    named_lines = output |> String.split("\n") |> Enum.map(&String.trim/1)
    # The lean CLI may prefix #print axioms messages with filename/line/column.
    report = Regex.compile!("^Law\\.lean:\\d+:\\d+:\\s*(?:info:\\s*)?#{Regex.escape(expected)}$")
    accepted_report = Enum.any?(named_lines, &(&1 == expected or Regex.match?(report, &1)))

    if accepted_report and not String.contains?(output, ["sorryAx", "depends on axioms:"]) do
      {"proved", ["Lean accepted a named axiom-free law; target semantics not checked"]}
    else
      {"error", ["missing or contradictory named axiom-free report"]}
    end
  end
end
