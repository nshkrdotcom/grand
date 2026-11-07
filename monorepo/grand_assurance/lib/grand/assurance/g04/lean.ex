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
         true <- Files.identifier?(theorem) and is_list(hypotheses) and
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
               Runner.execute(%{"engine" => "lean", "args" => ["--version"], "files" => %{}}, opts) do
          case version do
            %{"reason" => "missing_engine"} ->
              {:ok, version}

            %{"reason" => nil, "exit_code" => 0, "stdout" => output} ->
              if String.starts_with?(String.trim(output), "Lean (version ") do
                with {:ok, actual} <- Runner.execute(plan, opts) do
                  {:ok, Map.put(actual, "version_output", String.trim(output))}
                end
              else
                {:ok, Map.put(version, "reason", "invalid_engine_version")}
              end

            _ ->
              {:ok, Map.put(version, "reason", "engine_version_probe_failed")}
          end
        end
    end
  end

  @impl true
  def normalize(plan, raw) do
    output = raw["stdout"] || ""
    expected = "'#{plan["property"]}' does not depend on any axioms"
    version = Map.get(raw, "version_output", "not_qualified")
    version_qualified = String.starts_with?(version, "Lean (version ")

    {status, diagnostics} =
      case raw do
        %{"reason" => "unrun"} -> {"unrun", ["execution was not requested"]}
        %{"reason" => "missing_engine"} -> {"unsupported", ["Lean executable unavailable"]}
        %{"reason" => "timeout"} -> {"inconclusive", ["Lean timed out"]}
        %{"reason" => "cancelled"} -> {"inconclusive", ["run cancelled"]}
        %{"reason" => reason} when is_binary(reason) -> {"error", [reason]}
        %{"exit_code" => 0} when version_qualified -> normalize_success(output, expected)
        %{"exit_code" => 0} -> {"error", ["Lean version probe missing or unqualified"]}
        _ -> {"error", ["Lean rejected the law or exited abnormally; not a counterexample"]}
      end

    {:ok,
     %{
       "status" => status,
       "engine_version" => version,
       "diagnostics" => diagnostics,
       "counterexample" => nil
     }}
  end

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
