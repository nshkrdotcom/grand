defmodule Grand.Assurance.G05.Veil do
  @moduledoc """
  Veil 2.0 Lean DSL explicit-state model checker, deliberately distinct from TLC.
  Pinned API: `#gen_spec`, `#model_check interpreted {} {} (sequential := true)`
  under `lake --dir VEIL_ROOT env lean MODEL`. Only recognized checker messages
  qualify a run; successful Lean elaboration alone does NOT count as a pass.
  """

  @behaviour Grand.Assurance.G04.Verifier
  alias Grand.Assurance.G04.{Files, Runner}
  alias Grand.Assurance.G05.Tool

  @impl true
  def prepare(%{"model" => model}, opts) when is_map(model) do
    with %{
           "file" => path,
           "module" => mod,
           "property" => property,
           "mode" => "explicit_interpreted",
           "bounds" => bounds,
           "fairness" => "none",
           "hypotheses" => hypotheses,
           "translation" => translation
         } <- model,
         true <-
           Files.identifier?(mod) and Files.identifier?(property) and
             is_map(bounds) and bounds["finite_state"] == true and
             bounds["max_depth"] == "exhaustive" and valid_hypotheses?(hypotheses) and
             is_binary(translation) and byte_size(translation) in 1..1_000,
         {:ok, source} <- Files.load(path, ".lean"),
         true <- checked_source?(source["bytes"], mod, property),
         tool <- Tool.identity("veil", opts) do
      {:ok,
       %{
         "engine" => "lake",
         "args" => [],
         "files" => %{"Model.lean" => source["bytes"]},
         "source_files" => %{"model" => source["identity"]},
         "tool" => tool,
         "property" => property,
         "qualifications" => %{
           "kind" => "veil_dsl_explicit_state_model",
           "mode" => "explicit_interpreted",
           "solver" => "none_for_explicit_state",
           "check_command" => "#model_check interpreted",
           "bounds" => bounds,
           "fairness" => "none",
           "hypotheses" => hypotheses,
           "translation" => translation,
           "axiom_audit" => "Lean_and_Veil_model_assumptions_not_independently_enumerated",
           "finite_exploration_not_unbounded_proof" => true,
           "target_runtime_checked" => false,
           "interchangeable_with_tlc" => false,
           "discharges_obligation" => false
         }
       }}
    else
      false -> {:error, :invalid_veil_scope_or_model}
      _ -> {:error, :invalid_veil_model}
    end
  end

  def prepare(_, _), do: {:error, :invalid_veil_model}

  @impl true
  def execute(plan, opts) do
    cond do
      not Keyword.get(opts, :execute, false) ->
        {:ok, Runner.skipped("unrun")}

      not Keyword.get(opts, :allow_law_code, false) ->
        {:error, :explicit_law_code_permission_required}

      not plan["tool"]["available"] ->
        {:ok, Runner.skipped("missing_veil_toolchain")}

      true ->
        root = plan["tool"]["root"]

        Runner.execute(
          %{plan | "args" => ["--dir", root, "env", "lean", "@WORKSPACE@/Model.lean"]},
          opts
        )
    end
  end

  @impl true
  def normalize(plan, raw) do
    case raw["reason"] do
      "unrun" ->
        report("unrun", ["execution was not requested"])

      "missing_veil_toolchain" ->
        report("unsupported", ["pinned Veil build unavailable"])

      "missing_engine" ->
        report("unsupported", ["Lake executable unavailable"])

      reason when reason in ["timeout", "cancelled", "output_limit", "artifact_limit"] ->
        report("inconclusive", [reason])

      reason when is_binary(reason) ->
        report("error", [reason])

      nil ->
        qualify(plan, raw)
    end
  end

  defp qualify(plan, raw) do
    output = (raw["stdout"] || "") <> "\n" <> (raw["stderr"] || "")
    violation = Regex.match?(~r/Violation:\s*safety_failure\s*\(violates:\s*[^)]+\)/, output)

    correct_property =
      Regex.match?(
        Regex.compile!(
          "Violation:\\s*safety_failure\\s*\\(violates:\\s*#{Regex.escape(plan["property"])}\\)"
        ),
        output
      )

    pass = Regex.match?(~r/No violation\s*\(explored\s+[1-9][0-9]*\s+states\)/, output)

    complete =
      not String.contains?(output, ["maxDepth", "incomplete", "sorry", "unsound", "admitted"])

    cond do
      counterexample?(raw, {violation, correct_property, pass, complete}, output) ->
        {:ok,
         %{
           "status" => "counterexample",
           "engine_version" => "Veil pinned via Lean DSL",
           "diagnostics" => ["Veil reported a named safety violation in its finite model"],
           "counterexample" => String.slice(output, 0, 16_384),
           "theorems" => [],
           "dependencies" => [],
           "axioms" => %{"status" => "not_audited", "names" => nil}
         }}

      raw["exit_code"] != 0 ->
        report("error", ["Veil or Lean command failed; no qualified model result"])

      {pass, violation, complete} == {true, false, true} ->
        report("bounded_pass", [
          "Veil explicit-state checker reported no violation for finite model"
        ])

      true ->
        report("inconclusive", [
          "No qualified Veil model-check outcome in batch output (InfoView may be required)"
        ])
    end
  end

  defp counterexample?(%{"exit_code" => 1}, {true, true, false, true}, output) do
    String.contains?(output, "State 0 (via init)") and
      String.contains?(output, "released = true") and
      String.contains?(output, "confirmed = false")
  end

  defp counterexample?(_, _, _), do: false

  defp checked_source?(source, mod, property) do
    required_model_form?(source, mod, property) and safe_commands?(source) and
      finite_boolean_state?(source)
  end

  defp required_model_form?(source, mod, property) do
    String.starts_with?(String.trim_leading(source), "module\n") and
      String.contains?(source, "public import Veil") and
      String.contains?(source, "veil module #{mod}") and
      String.contains?(source, "safety [#{property}]") and
      String.contains?(source, "#gen_spec") and
      Regex.match?(~r/^#model_check interpreted \{\} \{\} \(sequential := true\)\s*$/m, source) and
      length(Regex.scan(~r/\bsafety\s*\[/, source)) == 1 and
      length(Regex.scan(~r/#model_check/, source)) == 1 and
      String.contains?(source, "end #{mod}")
  end

  defp finite_boolean_state?(source) do
    Regex.scan(~r/^individual\s+(\w+)\s*:\s*(\w+)\s*$/m, source, capture: :all_but_first)
    |> Enum.sort() == [["confirmed", "Bool"], ["released", "Bool"]]
  end

  defp safe_commands?(source) do
    not Regex.match?(
      ~r/#eval|#print|#check_invariants|#temporal_check|#run_tac|\bsorry\b|\badmit\b|\bIO\.|No violation|Violation:|set_option|\baxiom\b|\bunsafe\b|\bmaxDepth\b|^\s*(sort|relation|function|assumption)\b/m,
      source
    )
  end

  defp valid_hypotheses?(values) do
    is_list(values) and length(values) <= 12 and
      Enum.all?(values, fn v ->
        is_binary(v) and byte_size(v) <= 300
      end)
  end

  defp report(status, diagnostics) do
    {:ok,
     %{
       "status" => status,
       "engine_version" => "not_qualified",
       "diagnostics" => diagnostics,
       "counterexample" => nil,
       "theorems" => [],
       "dependencies" => [],
       "axioms" => %{"status" => "not_audited", "names" => nil}
     }}
  end
end
