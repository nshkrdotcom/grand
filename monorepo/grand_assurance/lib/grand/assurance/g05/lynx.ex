defmodule Grand.Assurance.G05.Lynx do
  @moduledoc """
  Lynx's **actual** `Lynx.Laws.verify/2` compiles selected BEAM modules with
  debug info, translates their dependency closure, invokes `Lynx.Runner` through
  Lake and reports named laws. A second `lake check --from-export` is requested.
  This is not a generic Lean-file proof or an import-time target execution.
  """

  @behaviour Grand.Assurance.G04.Verifier
  alias Grand.Assurance.G04.{Files, Runner}
  alias Grand.Assurance.G05.Tool
  alias Grand.Core.JSON

  @worker ~S"""
  # Grand-authored trusted harness for the pinned Lynx.Laws.verify/2 API.
  # Invoked ONLY from an explicitly authorized private runner workspace.
  source_files = ["Support.ex", "Source.ex", "Law.ex"]
  Code.compiler_options(debug_info: true)
  Enum.each(source_files, &Code.compile_file/1)
  module = Module.concat(["Grand", "HoldLedger", "Laws"])
  # No caller-supplied Mix file or execution hook is loaded.
  reports = Lynx.Laws.verify([module], debug: :lean, debug_dir: "translated",
    export: "proof.ndjson", cache: false)
  all_ok = Enum.all?(reports, &(&1.status == :ok))
  {check_exit, check_output} =
    if all_ok do
      Lynx.Commands.lake(Path.join(System.fetch_env!("GRAND_LYNX_ROOT"), "Lean"),
        ["check", "--from-export", Path.expand("proof.ndjson")])
    else
      {1, "translation, elaboration or kernel verification failed"}
    end
  data = %{
    "protocol" => "grand.lynx.report.v1",
    "module" => Atom.to_string(module),
    "reports" => Enum.map(reports, fn r -> %{
      "status" => Atom.to_string(r.status), "module" => r.module,
      "file" => r.file, "cached" => r.cached,
      "theorems" => Enum.map(r.theorems, & &1.name),
      "diagnostics" => Enum.map(r.diagnostics, &%{"severity" => Atom.to_string(&1.severity),
        "declaration" => (&1.declaration || ""), "message" => &1.message})
    } end),
    "independent_kernel_check" => if(check_exit == 0, do: "ok", else: "failed"),
    "independent_check_output" => String.slice(check_output, 0, 2048),
    "axiom_audit" => "not_enumerated_by_Lynx.Laws.verify"
  }
  IO.puts("GRAND_LYNX_REPORT_V1:" <> IO.iodata_to_binary(:json.encode(data)))
  if not all_ok or check_exit != 0, do: System.halt(12)
  """

  @impl true
  def prepare(%{"law" => law}, opts) when is_map(law) do
    with %{"file" => file, "source_file" => source_file, "support_file" => support_file,
           "module" => "Grand.HoldLedger.Laws", "theorem" => theorem,
           "origin" => origin, "license" => license, "hypotheses" => hypotheses} <- law,
         true <- Regex.match?(~r/\A[a-z][a-z0-9_]*\/1\z/, theorem) and
                   is_binary(origin) and byte_size(origin) in 1..300 and
                   is_binary(license) and byte_size(license) in 1..120 and
                   valid_hypotheses?(hypotheses),
         {:ok, source} <- Files.load(source_file, ".ex"),
         {:ok, support} <- Files.load(support_file, ".ex"),
         {:ok, proof} <- Files.load(file, ".ex"),
         true <- String.contains?(proof["bytes"], "use Lynx.Laws") and
                   String.contains?(proof["bytes"], "law #{String.replace(theorem, "/1", "")}") and
                   String.contains?(proof["bytes"], "~LEAN") and
                   Enum.all?([source, support, proof], fn entry ->
                     not String.contains?(entry["bytes"], "GRAND_LYNX_REPORT_V1:")
                   end),
         tool <- Tool.identity("lynx", opts) do
      {:ok, %{
        "engine" => "elixir", "args" => [],
        "files" => %{"Source.ex" => source["bytes"], "Support.ex" => support["bytes"],
                     "Law.ex" => proof["bytes"], "Verify.exs" => @worker},
        "source_files" => %{"source" => source["identity"], "support" => support["identity"],
                            "law" => proof["identity"]},
        "tool" => tool,
        "property" => theorem,
        "qualifications" => %{
          "kind" => "lynx_translated_beam_law", "origin" => origin,
          "license" => license, "hypotheses" => hypotheses,
          "translation" => "Lynx.Laws.verify/2 Core Erlang to Lean",
          "lean_check" => "Lynx.Runner and lake check --from-export",
          "axiom_audit" => "not_enumerated_by_Lynx.Laws.verify",
          "open_axiom_gap" => true, "discharges_obligation" => false,
          "target_runtime_checked" => false,
          "external_effects_and_durability_unproved" => true
        }
      }}
    else
      false -> {:error, :invalid_lynx_law_or_package}
      _ -> {:error, :invalid_lynx_package}
    end
  end

  def prepare(_, _), do: {:error, :invalid_lynx_package}

  @impl true
  def execute(plan, opts) do
    cond do
      not Keyword.get(opts, :execute, false) -> {:ok, Runner.skipped("unrun")}
      not Keyword.get(opts, :allow_law_code, false) ->
        {:error, :explicit_law_code_permission_required}
      not plan["tool"]["available"] -> {:ok, Runner.skipped("missing_lynx_toolchain")}
      true ->
        ebin = Path.join(plan["tool"]["root"], "_build/dev/lib/lynx/ebin")
        Runner.execute(%{plan | "args" => ["-pa", ebin, "Verify.exs"]}, opts)
    end
  end

  @impl true
  def normalize(plan, raw) do
    case raw["reason"] do
      "unrun" -> report("unrun", "not_qualified", ["execution was not requested"])
      "missing_lynx_toolchain" -> report("unsupported", "not_qualified", ["pinned Lynx build unavailable"])
      "missing_engine" -> report("unsupported", "not_qualified", ["Elixir executable unavailable"])
      reason when reason in ["timeout", "cancelled", "output_limit"] ->
        report("inconclusive", "not_qualified", [reason])
      reason when is_binary(reason) -> report("error", "not_qualified", [reason])
      nil -> qualify(plan, raw)
    end
  end

  defp qualify(plan, raw) do
    marker = "GRAND_LYNX_REPORT_V1:"
    matches = raw["stdout"] |> String.split("\n", trim: true) |>
      Enum.filter(&String.starts_with?(&1, marker))

    with [line] <- matches,
         {:ok, data} <- JSON.decode(String.replace_prefix(line, marker, "")),
         %{"protocol" => "grand.lynx.report.v1", "module" => "Elixir.Grand.HoldLedger.Laws",
           "reports" => reports, "independent_kernel_check" => checked,
           "axiom_audit" => "not_enumerated_by_Lynx.Laws.verify"} <- data,
         true <- is_list(reports) and reports != [] and
                   Enum.all?(reports, &valid_report?/1),
         true <- Enum.any?(reports, fn r ->
           r["module"] in ["Grand.HoldLedger.Laws", "Elixir.Grand.HoldLedger.Laws"] and
             plan["property"] in r["theorems"]
         end) do
      good = raw["exit_code"] == 0 and checked == "ok" and
             Enum.all?(reports, &(&1["status"] == "ok" and &1["cached"] == false)) and
             get_in(raw, ["artifacts", "proof_export"]) == true and
             get_in(raw, ["artifacts", "translated_lean"]) == true
      diagnostics =
        Enum.flat_map(reports, fn r -> Enum.map(r["diagnostics"], & &1["message"]) end)
      if good do
        {:ok, %{ "status" => "proved", "engine_version" => "Lynx pinned via local build + Lean kernel",
          "diagnostics" => ["named law translated and checked; axioms not enumerated" | diagnostics],
          "counterexample" => nil,
          "theorems" => Enum.flat_map(reports, & &1["theorems"]),
          "dependencies" => Enum.map(reports, & &1["module"]),
          "axioms" => %{"status" => "not_enumerated", "names" => nil} }}
      else
        report("error", "not_qualified", ["Lynx failure, missing independent kernel check or missing staged artifacts" | diagnostics])
      end
    else
      _ -> report("error", "not_qualified", ["missing, forged or malformed Lynx report; no theorem accepted"])
    end
  end

  defp valid_report?(%{"module" => m, "status" => s, "cached" => cached,
                        "theorems" => th, "diagnostics" => ds}) do
    is_binary(m) and s in ~w(ok error skipped) and is_boolean(cached) and
      is_list(th) and Enum.all?(th, &is_binary/1) and is_list(ds) and
      Enum.all?(ds, fn d -> is_map(d) and is_binary(d["message"]) end)
  end
  defp valid_report?(_), do: false

  defp valid_hypotheses?(values) do
    is_list(values) and length(values) <= 12 and Enum.all?(values, fn v ->
      is_binary(v) and byte_size(v) <= 300
    end)
  end

  defp report(status, version, diagnostics) do
    {:ok, %{"status" => status, "engine_version" => version, "diagnostics" => diagnostics,
       "counterexample" => nil, "theorems" => [], "dependencies" => [],
       "axioms" => %{"status" => "not_audited", "names" => nil}}}
  end
end
