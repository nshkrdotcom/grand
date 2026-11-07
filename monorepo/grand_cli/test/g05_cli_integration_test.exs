defmodule Grand.CLI.G05IntegrationTest do
  use ExUnit.Case, async: false

  alias Grand.CLI
  alias Grand.Core.JSON

  @fixtures Path.expand("../../../fixtures", __DIR__)
  @g05 Path.join(@fixtures, "g05")
  @cli_root Path.expand("..", __DIR__)
  @date "2026-11-06T20:00:00Z"
  @project "fixture:synthetic-retry"
  @human ["--actor", "human:fixture-reviewer", "--ack-human", "--at", @date]

  setup do
    dir = Path.join(System.tmp_dir!(), "grand-g05-cli-#{System.unique_integer([:positive])}")
    store = Path.join(dir, "store")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    source = Path.join(@fixtures, "g03_synthetic_retry_v2.json")

    assert {:ok, _} =
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

    assert {:ok, _} =
             CLI.run(
               [
                 "g03",
                 "obligation",
                 "create",
                 Path.join(@fixtures, "g03_obligation_input.json"),
                 "--store",
                 store
               ] ++ @human
             )

    %{dir: dir, store: store}
  end

  defp command(args) do
    {output, status} =
      System.cmd("mix", ["grand" | args],
        cd: @cli_root,
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    decoded =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> case do
        nil -> {:error, :empty_cli_output}
        text -> JSON.decode(text)
      end

    {status, decoded, output}
  end

  defp input(name), do: Path.join(@g05, "#{name}-manifest.json")

  test "G05-TEST-07 actual mix grand g05 inspect and run require opt-in without rewriting G03", %{
    store: store
  } do
    assert {0, {:ok, unrun}, _} =
             command(["g05", "inspect", input("lynx-good"), "--store", store, "--execute"])

    assert unrun["status"] == "unrun"
    assert unrun["schema_version"] == 4

    assert {status, _, reason} =
             command(["g05", "run", input("lynx-good"), "--store", store, "--execute"])

    assert status != 0
    assert reason =~ "explicit_law_code_permission_required"

    assert {0, {:ok, receipt}, _} =
             command(["g03", "receipt", "g03-obligation-once", "--store", store])

    assert receipt["verification_result"]["status"] == "unrun"
  end

  test "G05-TEST-07/09 exclusive outputs, exact scope and applicability", %{
    store: store,
    dir: dir
  } do
    path = Path.join(dir, "proof.json")

    assert {0, {:ok, _}, _} =
             command(["g05", "inspect", input("lynx-good"), "--store", store, "--out", path])

    assert {0, {:ok, %{"applicability" => "current"}}, _} =
             command(["g05", "applicability", path, input("lynx-good"), "--store", store])

    assert {0, {:ok, %{"applicability" => "stale", "reasons" => reasons}}, _} =
             command(["g05", "applicability", path, input("lynx-bad"), "--store", store])

    assert "source_files" in reasons
    before = File.read!(path)

    assert {status, _, _} =
             command(["g05", "inspect", input("veil-safe"), "--store", store, "--out", path])

    assert status != 0
    assert File.read!(path) == before

    {:ok, data} = JSON.decode(File.read!(input("veil-safe")))
    mutated = put_in(data, ["assumptions"], [])
    {:ok, bytes} = JSON.encode(mutated)
    altered = Path.join(dir, "wrong-scope.json")
    File.write!(altered, bytes)
    assert {status, _, message} = command(["g05", "inspect", altered, "--store", store])
    assert status != 0
    assert message =~ "g05_assumption_revision_mismatch"
  end

  test "G05-TEST-01..05 actual mix grand impact emits syntactic report only", %{dir: dir} do
    before = Path.join(@g05, "impact/before.json")
    after_snapshot = Path.join(@g05, "impact/premature.json")
    links = Path.join(@g05, "impact/links.json")
    path = Path.join(dir, "impact.json")

    assert {0, {:ok, %{"command" => "g05"}}, _} =
             command(["g05", "impact", before, after_snapshot, links, "--out", path])

    {:ok, data} = JSON.decode(File.read!(path))
    assert data["format"] == "grand.g05.impact"
    assert data["evidence_status"] == "stale"
    assert "g03-confirm-once" in data["affected_requirements"]
  end

  @tag timeout: 180_000
  test "G05-TEST-06/08 real CLI engine acceptance only with installed pinned tools", %{
    store: store,
    dir: dir
  } do
    if System.get_env("GRAND_RUN_G05_ENGINES") == "1" do
      assert {0, {:ok, historical_before}, _} =
               command(["g03", "receipt", "g03-obligation-once", "--store", store])

      for {name, expected} <- [
            {"lynx-good", "proved"},
            {"lynx-bad", "error"},
            {"veil-safe", "bounded_pass"},
            {"veil-bad", "counterexample"}
          ] do
        path = Path.join(dir, "#{name}-result.json")

        assert {0, {:ok, %{"status" => ^expected}}, output} =
                 command([
                   "g05",
                   "run",
                   input(name),
                   "--store",
                   store,
                   "--execute",
                   "--allow-law-code",
                   "--timeout-ms",
                   "60000",
                   "--out",
                   path
                 ])

        assert output != ""
        {:ok, data} = JSON.decode(File.read!(path))
        assert data["status"] == expected
        retain_result(path)

        assert {0, {:ok, %{"applicability" => "current"}}, _} =
                 command(["g05", "applicability", path, input(name), "--store", store])
      end

      for {name, expected} <- [{"tlc-safe", "bounded_pass"}, {"tlc-bad", "counterexample"}] do
        path = Path.join(dir, "#{name}-result.json")

        assert {0, {:ok, %{"status" => ^expected}}, _} =
                 command([
                   "g04",
                   "run",
                   input(name),
                   "--store",
                   store,
                   "--execute",
                   "--tlc-jar",
                   System.fetch_env!("GRAND_TLC_JAR"),
                   "--timeout-ms",
                   "60000",
                   "--out",
                   path
                 ])

        {:ok, data} = JSON.decode(File.read!(path))
        assert data["property"] == "NoPrematureRelease"
        retain_result(path)
      end

      assert {0, {:ok, ^historical_before}, _} =
               command(["g03", "receipt", "g03-obligation-once", "--store", store])

      receipt_path = Path.join(dir, "g03-unchanged-conditional-receipt.json")

      assert {0, {:ok, _}, _} =
               command([
                 "g03",
                 "receipt",
                 "g03-obligation-once",
                 "--store",
                 store,
                 "--out",
                 receipt_path
               ])

      retain_result(receipt_path)
    else
      for name <- ~w(lynx-good veil-safe) do
        assert {:ok, %{"status" => "unrun"}} =
                 CLI.run(["g05", "inspect", input(name), "--store", store])
      end
    end
  end

  defp retain_result(path) do
    if output = System.get_env("GRAND_G05_RESULTS_DIR") do
      File.mkdir_p!(output)
      File.cp!(path, Path.join(output, Path.basename(path)))
    end
  end
end
