defmodule Grand.CLI.G04IntegrationTest do
  use ExUnit.Case, async: false

  alias Grand.CLI
  alias Grand.Core.JSON

  @fixtures Path.expand("../../../fixtures", __DIR__)
  @cli_root Path.expand("..", __DIR__)
  @date "2026-11-06T20:00:00Z"
  @project "fixture:synthetic-retry"
  @human ["--actor", "human:fixture-reviewer", "--ack-human", "--at", @date]

  setup do
    dir = Path.join(System.tmp_dir!(), "grand-g04-cli-#{System.unique_integer([:positive])}")
    store = Path.join(dir, "store")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    source = Path.join(@fixtures, "g03_synthetic_retry_v2.json")

    {:ok, _} =
      CLI.run(["import", source, "--project", @project, "--schema", "2", "--store", store])

    for {kind, op} <- [{"assumption", "register"}, {"requirement", "draft"}] do
      file = Path.join(@fixtures, "g03_#{kind}_input.json")
      assert {:ok, _} = CLI.run(["g03", kind, op, file, "--store", store] ++ @human)
    end

    for decision <- ["submit", "approve"] do
      assert {:ok, _} =
               CLI.run(
                 ["g03", "requirement", decision, "g03-confirm-once", "--store", store] ++ @human
               )
    end

    file = Path.join(@fixtures, "g03_obligation_input.json")
    assert {:ok, _} = CLI.run(["g03", "obligation", "create", file, "--store", store] ++ @human)
    %{dir: dir, store: store}
  end

  defp command(args) do
    {output, status} =
      System.cmd("mix", ["grand" | args],
        cd: @cli_root,
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> case do
        nil -> {:error, :no_cli_output}
        last -> JSON.decode(last)
      end

    {status, result, output}
  end

  defp manifest(name), do: Path.join(@fixtures, "g04/#{name}-manifest.json")

  test "real mix grand g04 inspect/run needs explicit execution, with no historical G03 rewrite",
       %{
         store: store
       } do
    assert {0, {:ok, result}, _} = command(["g04", "inspect", manifest("tlc"), "--store", store])
    assert result["status"] == "unrun"
    assert result["qualifications"]["bounds"] == %{"limit" => 2}

    assert {0, {:ok, unsupported}, _} =
             command(["g04", "run", manifest("tlc"), "--store", store, "--execute"])

    assert unsupported["status"] == "unsupported"

    assert {0, {:ok, g03}, _} =
             command(["g03", "receipt", "g03-obligation-once", "--store", store])

    assert g03["verification_result"]["status"] == "unrun"
  end

  test "real mix grand g04 denies law execution without extra permission and won't overwrite", %{
    store: store,
    dir: dir
  } do
    {status, _, message} =
      command(["g04", "run", manifest("lean"), "--store", store, "--execute"])

    assert status != 0
    assert message =~ "explicit_law_code_permission_required"

    path = Path.join(dir, "result.json")
    File.write!(path, "DO NOT OVERWRITE")

    {status, _, _} =
      command(["g04", "inspect", manifest("tlc"), "--store", store, "--out", path])

    assert status != 0
    assert File.read!(path) == "DO NOT OVERWRITE"

    {status, _, message} =
      command([
        "g04",
        "run",
        manifest("lean"),
        "--store",
        store,
        "--execute",
        "--allow-law-code",
        "--timeout-ms",
        "-4"
      ])

    assert status != 0
    assert message =~ "unsafe_runner_policy" or message =~ "unsupported"
  end

  test "real TLC CLI pass, trace and applicability with an installed jar", %{
    store: store,
    dir: dir
  } do
    jar = System.get_env("GRAND_TLC_JAR")

    if is_binary(jar) and File.regular?(jar) do
      for {name, expected} <- [{"tlc", "bounded_pass"}, {"tlc-bad", "counterexample"}] do
        output = Path.join(dir, name <> ".json")

        assert {0, {:ok, _}, _} =
                 command([
                   "g04",
                   "run",
                   manifest(name),
                   "--store",
                   store,
                   "--execute",
                   "--tlc-jar",
                   jar,
                   "--out",
                   output
                 ])

        {:ok, result} = JSON.decode(File.read!(output))
        assert result["status"] == expected
        assert result["engine_version"] =~ "TLC2 Version 2.19"
        assert result["qualifications"]["bounds"] == %{"limit" => 2}
        if expected == "counterexample", do: assert(result["counterexample"] =~ "count = 2")

        assert {0, {:ok, %{"applicability" => "current"}}, _} =
                 command(["g04", "applicability", output, manifest(name), "--store", store])

        if evidence = System.get_env("GRAND_G04_EVIDENCE_DIR") do
          File.mkdir_p!(evidence)
          File.cp!(output, Path.join(evidence, name <> "-result.json"))
        end
      end
    else
      assert {:ok, result} =
               CLI.run(["g04", "run", manifest("tlc"), "--store", store, "--execute"])

      assert result["status"] == "unsupported"
    end
  end

  test "inspect ignores execution and malformed JSON paths return errors", %{
    store: store,
    dir: dir
  } do
    assert {:ok, result} =
             CLI.run(["g04", "inspect", manifest("lean"), "--store", store, "--execute"])

    assert result["status"] == "unrun"
    {:ok, input} = JSON.decode(File.read!(manifest("lean")))
    path = Path.join(dir, "malformed.json")
    {:ok, encoded} = JSON.encode(put_in(input, ["law", "file"], 42))
    File.write!(path, encoded)
    assert {:error, _} = CLI.run(["g04", "inspect", path, "--store", store])
  end
end
