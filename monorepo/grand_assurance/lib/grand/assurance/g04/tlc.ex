defmodule Grand.Assurance.G04.TLC do
  @moduledoc """
  Finite TLA+/TLC model adapter. Only the explicitly supplied Model.tla and
  Model.cfg are read, staged into a disposable workspace and passed to the
  separately installed TLC JAR. A finite pass applies only to the stated
  model/constant/configuration; it is never a theorem about the target.
  """

  @behaviour Grand.Assurance.G04.Verifier
  alias Grand.Assurance.G04.Files
  alias Grand.Assurance.G04.Runner

  @impl true
  def prepare(%{"model" => model}, _opts) when is_map(model) do
    with %{
           "file" => file,
           "config_file" => cfg,
           "property" => property,
           "bounds" => %{"limit" => limit},
           "fairness" => fairness,
           "hypotheses" => hypotheses
         } <- model,
         true <- Files.identifier?(property) and is_integer(limit) and limit in 1..32 and
                   fairness in ["none", "declared_in_spec"] and is_list(hypotheses) and
                   Enum.all?(hypotheses, &(is_binary(&1) and byte_size(&1) <= 300)),
         {:ok, source} <- Files.load(file, ".tla"),
         {:ok, config} <- Files.load(cfg, ".cfg"),
         true <- compatible_config?(source["bytes"], config["bytes"], property, limit) and
                   compatible_fairness?(source["bytes"], fairness) do
      {:ok,
       %{
         "engine" => "java",
         "args" => [],
         "files" => %{"Model.tla" => source["bytes"], "Model.cfg" => config["bytes"]},
         "source_files" => %{
           "model" => source["identity"],
           "config" => config["identity"]
         },
         "property" => property,
         "qualifications" => %{
           "kind" => "finite_tlc_model",
           "bounds" => %{"limit" => limit},
           "fairness" => fairness,
           "hypotheses" => hypotheses,
           "finite_exploration_not_unbounded_proof" => true,
           "target_runtime_checked" => false
         }
       }}
    else
      false -> {:error, :invalid_tlc_scope_or_config}
      _ -> {:error, :invalid_tlc_model}
    end
  end

  def prepare(_, _), do: {:error, :invalid_tlc_model}

  @impl true
  def execute(plan, opts) do
    if Keyword.get(opts, :execute, false) do
      case jar(Keyword.get(opts, :tlc_jar)) do
        {:ok, path} ->
          args = [
            "-Xmx256m",
            "-cp",
            path,
            "tlc2.TLC",
            "-config",
            "Model.cfg",
            "-workers",
            "1",
            "Model.tla"
          ]

          Runner.execute(%{plan | "args" => args}, opts)

        {:error, :missing_tlc_jar} ->
          {:ok, Runner.skipped("missing_tlc_jar")}

        other ->
          other
      end
    else
      {:ok, Runner.skipped("unrun")}
    end
  end

  @impl true
  def normalize(plan, raw) do
    output = (raw["stdout"] || "") <> "\n" <> (raw["stderr"] || "")
    version =
      case Regex.run(~r/TLC2 Version [0-9]+\.[0-9]+[^\r\n]*/, output) do
        [value] -> String.trim(value)
        _ -> "not_qualified"
      end

    {status, diagnostics, counterexample} = classify(raw, output, version, plan["property"])

    {:ok,
     %{
       "status" => status,
       "engine_version" => version,
       "diagnostics" => diagnostics,
       "counterexample" => counterexample
     }}
  end

  defp compatible_config?(source, config, property, limit) do
    String.contains?(source, "---- MODULE Model ----") and
      Regex.match?(~r/(?m)^\s*SPECIFICATION\s+Spec\s*$/, config) and
      Regex.match?(Regex.compile!("(?m)^\\s*INVARIANT\\s+#{Regex.escape(property)}\\s*$"), config) and
      Regex.match?(Regex.compile!("(?m)^\\s*CONSTANT\\s+Limit\\s*=\\s*#{limit}\\s*$"), config)
  end

  defp compatible_fairness?(source, "none") do
    not String.contains?(source, ["WF_", "SF_"])
  end

  defp compatible_fairness?(source, "declared_in_spec") do
    String.contains?(source, ["WF_", "SF_"])
  end

  defp jar(nil), do: {:error, :missing_tlc_jar}

  defp jar(path) when is_binary(path) do
    with true <- Path.extname(path) == ".jar",
         {:ok, stat} <- File.lstat(path),
         true <- stat.type == :regular and stat.size in 1..40_000_000 do
      {:ok, Path.expand(path)}
    else
      _ -> {:error, :invalid_tlc_jar}
    end
  end

  defp jar(_), do: {:error, :invalid_tlc_jar}

  defp classify(%{"reason" => "unrun"}, _, _, _),
    do: {"unrun", ["execution was not requested"], nil}

  defp classify(%{"reason" => reason}, _, _, _)
       when reason in ["missing_engine", "missing_tlc_jar"],
       do: {"unsupported", [reason], nil}

  defp classify(%{"reason" => reason}, _, _, _) when reason in ["timeout", "cancelled"],
    do: {"inconclusive", [reason], nil}

  defp classify(%{"reason" => reason}, _, _, _) when is_binary(reason),
    do: {"error", [reason], nil}

  defp classify(%{"exit_code" => exit_code}, _output, "not_qualified", _),
    do: {"error", ["missing TLC version header; tool output not qualified (exit #{exit_code})"], nil}

  defp classify(raw, output, _version, property) do
    violation = String.contains?(output, "Invariant #{property} is violated")
    states = Regex.match?(~r/\bState 1:/, output) and Regex.match?(~r/\bState 2:/, output)
    counts = Regex.match?(~r/\b[0-9]+ distinct states found/, output)

    cond do
      violation and states and counts and is_integer(raw["exit_code"]) and
          raw["exit_code"] != 0 ->
        {"counterexample", ["TLC reported an invariant violation with a state trace"],
         output}

      raw["exit_code"] == 0 and counts and
          String.contains?(output, "Model checking completed. No error has been found.") ->
        {"bounded_pass", ["TLC completed finite exploration under the provided configuration"],
         nil}

      true ->
        {"error", ["TLC failed, emitted malformed/incomplete output or lacked a trace"], nil}
    end
  end
end
