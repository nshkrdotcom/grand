defmodule Grand.Assurance.G04.Runner do
  @moduledoc """
  Small local subprocess boundary for allowlisted checker commands only. Source
  imports never use this module. Executables are found by name, arguments are
  supplied as an argv vector (never interpolated into shell text), and the
  workspace is deleted after execution. A fixed shell wrapper redirects the
  two streams; callers never supply shell source or executable names.

  This is bounded local process control, NOT a container/network sandbox.
  Run only trusted checker/law files on a trusted host.
  """

  @engines ~w(lean java elixir lake)
  @files ~w(Law.lean Model.tla Model.cfg Source.ex Support.ex Law.ex Verify.exs Model.lean)
  @shell ~s(ulimit -f "$1" || exit 125; shift; echo $$ >process.pid; exec "$@" >stdout.log 2>stderr.log)

  @doc "Run an approved plan, or report unrun when execution was not requested."
  @spec execute(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(plan, opts) when is_map(plan) and is_list(opts) do
    if Keyword.get(opts, :execute, false) do
      with :ok <- policy(opts),
           :ok <- valid_plan(plan),
           {:ok, executable} <- locate(plan["engine"]),
           {:ok, workspace} <- workspace() do
        try do
          with :ok <- stage(workspace, plan["files"]) do
            start(executable, staged_args(plan["args"], workspace), workspace, opts)
          end
        after
          File.rm_rf!(workspace)
        end
      else
        {:error, :missing_engine} -> {:ok, skipped("missing_engine")}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, skipped("unrun")}
    end
  end

  def execute(_, _), do: {:error, :invalid_runner_plan}

  @doc "Return a distinct data-only status without launching a process."
  def skipped(reason)
      when reason in ~w(unrun missing_engine missing_tlc_jar missing_lynx_toolchain missing_veil_toolchain) do
    %{
      "stdout" => "",
      "stderr" => "",
      "exit_code" => nil,
      "elapsed_ms" => 0,
      "reason" => reason
    }
  end

  defp policy(opts) do
    timeout = Keyword.get(opts, :timeout_ms, 5_000)
    output = Keyword.get(opts, :output_limit_bytes, 65_536)
    cancel = Keyword.get(opts, :cancel_ref)

    if is_integer(timeout) and timeout in 10..60_000 and is_integer(output) and
         output in 256..262_144 and (is_nil(cancel) or is_reference(cancel)) do
      :ok
    else
      {:error, :unsafe_runner_policy}
    end
  end

  defp valid_plan(%{"engine" => engine, "args" => args, "files" => files}) do
    if engine in @engines and valid_args?(args) and valid_files?(files) and
         command_allowed?(engine, args, files) do
      :ok
    else
      {:error, :unsafe_runner_plan}
    end
  end

  defp valid_plan(_), do: {:error, :unsafe_runner_plan}

  defp valid_args?(args) do
    is_list(args) and length(args) <= 20 and Enum.all?(args, &valid_arg?/1)
  end

  defp valid_arg?(value) do
    is_binary(value) and byte_size(value) in 1..1_024 and String.valid?(value) and
      not String.contains?(value, [<<0>>, "\n", "\r"])
  end

  defp valid_files?(files) do
    is_map(files) and map_size(files) <= 5 and Enum.all?(files, &valid_file?/1)
  end

  defp valid_file?({name, content}) do
    name in @files and is_binary(content) and byte_size(content) <= 256_000
  end

  defp command_allowed?("elixir", ["-pa", ebin, "Verify.exs"], files) do
    Path.type(ebin) == :absolute and
      String.ends_with?(ebin, "/_build/dev/lib/lynx/ebin") and
      Enum.sort(Map.keys(files)) == ~w(Law.ex Source.ex Support.ex Verify.exs)
  end

  defp command_allowed?("lake", ["--dir", root, "env", "lean", "@WORKSPACE@/Model.lean"], files) do
    Path.type(root) == :absolute and Path.basename(root) == "veil" and
      Map.keys(files) == ["Model.lean"]
  end

  defp command_allowed?("lean", ["--version"], files), do: map_size(files) == 0
  defp command_allowed?("lean", ["Law.lean"], files), do: Map.keys(files) == ["Law.lean"]

  defp command_allowed?(
         "java",
         [
           "-Xmx256m",
           "-cp",
           path,
           "tlc2.TLC",
           "-config",
           "Model.cfg",
           "-workers",
           "1",
           "Model.tla"
         ],
         files
       ) do
    Path.type(path) == :absolute and Path.extname(path) == ".jar" and
      Enum.sort(Map.keys(files)) == ["Model.cfg", "Model.tla"]
  end

  defp command_allowed?(_, _, _), do: false

  defp locate(name) do
    case System.find_executable(name) do
      nil -> {:error, :missing_engine}
      path -> {:ok, path}
    end
  end

  defp workspace do
    path =
      Path.join(
        System.tmp_dir!(),
        "grand-g04-#{Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)}"
      )

    case File.mkdir(path) do
      :ok ->
        case File.chmod(path, 0o700) do
          :ok ->
            {:ok, path}

          {:error, reason} ->
            File.rm_rf!(path)
            {:error, {:workspace_permissions_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:workspace_create_failed, reason}}
    end
  end

  defp stage(dir, files) do
    Enum.reduce_while(files, :ok, fn {name, content}, :ok ->
      case stage_file(Path.join(dir, name), content) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, {:workspace_write_failed, reason}}}
      end
    end)
  end

  defp stage_file(path, content) do
    with :ok <- File.write(path, content, [:exclusive, :binary]), do: File.chmod(path, 0o600)
  end

  defp staged_args(args, dir) do
    Enum.map(args, &String.replace(&1, "@WORKSPACE@", dir))
  end

  defp start(executable, arguments, dir, opts) do
    with shell when is_binary(shell) <- System.find_executable("sh"),
         session when is_binary(session) <- System.find_executable("setsid"),
         killer when is_binary(killer) <- System.find_executable("kill") do
      launch(session, shell, killer, executable, arguments, dir, opts)
    else
      _ -> {:error, :runner_process_controls_unavailable}
    end
  end

  defp launch(session, shell, killer, executable, arguments, dir, opts) do
    # BEAM's JIT needs a larger process file limit; separately bound the
    # workspace (64 MB) and each log stream. Lynx's export is about 27 MB.
    file_cap =
      if Path.basename(executable) == "elixir",
        do: 512_000_000,
        else: Keyword.get(opts, :output_limit_bytes, 65_536)

    blocks = Integer.to_string(div(file_cap + 511, 512))
    argv = ["--wait", shell, "-c", @shell, "grand-g04", blocks, executable | arguments]

    port =
      Port.open({:spawn_executable, String.to_charlist(session)}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :hide,
        {:cd, String.to_charlist(dir)},
        {:args, Enum.map(argv, &String.to_charlist/1)}
      ])

    started = System.monotonic_time(:millisecond)
    opts = opts |> Keyword.put(:process_killer, killer) |> Keyword.put(:workspace, dir)

    try do
      await(port, dir, started, opts)
    after
      stop(port, opts)
    end
  end

  defp await(port, dir, started, opts) do
    elapsed = System.monotonic_time(:millisecond) - started
    timeout = Keyword.get(opts, :timeout_ms, 5_000)
    max_output = Keyword.get(opts, :output_limit_bytes, 65_536)
    token = Keyword.get(opts, :cancel_ref)

    cond do
      output_exceeded?(dir, max_output) ->
        stop(port, opts)
        {:ok, captured(dir, nil, elapsed, "output_limit", max_output)}

      workspace_size(dir) > 64_000_000 ->
        stop(port, opts)
        {:ok, captured(dir, nil, elapsed, "artifact_limit", max_output)}

      elapsed >= timeout ->
        stop(port, opts)
        {:ok, captured(dir, nil, elapsed, "timeout", max_output)}

      true ->
        receive do
          {^port, {:exit_status, status}} ->
            reason = completion_reason(dir, max_output)
            {:ok, captured(dir, status, elapsed, reason, max_output)}

          {^port, {:data, _launcher_diagnostic}} ->
            await(port, dir, started, opts)

          {:g04_cancel, ^token} when is_reference(token) ->
            stop(port, opts)
            {:ok, captured(dir, nil, elapsed, "cancelled", max_output)}
        after
          40 -> await(port, dir, started, opts)
        end
    end
  end

  defp output_exceeded?(dir, cap) do
    Enum.any?(["stdout.log", "stderr.log"], fn name ->
      case File.stat(Path.join(dir, name)) do
        {:ok, stat} -> stat.size > cap
        _ -> false
      end
    end)
  end

  defp completion_reason(dir, cap) do
    cond do
      output_exceeded?(dir, cap) -> "output_limit"
      workspace_size(dir) > 64_000_000 -> "artifact_limit"
      true -> nil
    end
  end

  defp workspace_size(dir) do
    case File.ls(dir) do
      {:ok, names} -> Enum.reduce(names, 0, &(&2 + entry_size(Path.join(dir, &1))))
      _ -> 0
    end
  end

  defp entry_size(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular, size: size}} -> size
      {:ok, %{type: :directory}} -> workspace_size(path)
      _ -> 0
    end
  end

  defp stop(port, opts) do
    killer = Keyword.fetch!(opts, :process_killer)

    case File.read(Path.join(Keyword.fetch!(opts, :workspace), "process.pid")) do
      {:ok, text} ->
        case Integer.parse(String.trim(text)) do
          {pid, ""} when pid > 1 ->
            System.cmd(killer, ["-KILL", "--", "-#{pid}"], stderr_to_stdout: true)

          _ ->
            :ok
        end

      _ ->
        :ok
    end

    if Port.info(port) != nil, do: Port.close(port)
  end

  defp captured(dir, exit_code, elapsed, reason, max_output) do
    %{
      "stdout" => read_capped(Path.join(dir, "stdout.log"), max_output),
      "stderr" => read_capped(Path.join(dir, "stderr.log"), max_output),
      "exit_code" => exit_code,
      "elapsed_ms" => elapsed,
      "reason" => reason,
      "artifacts" => %{
        "proof_export" => artifact?(Path.join(dir, "proof.ndjson")),
        "translated_lean" =>
          case File.ls(Path.join(dir, "translated")) do
            {:ok, files} -> files != []
            _ -> false
          end
      }
    }
  end

  defp artifact?(path) do
    case File.lstat(path) do
      {:ok, stat} -> stat.type == :regular and stat.size in 1..64_000_000
      _ -> false
    end
  end

  defp read_capped(path, max_output) do
    case File.open(path, [:read, :binary]) do
      {:ok, handle} ->
        value = IO.binread(handle, max_output)
        File.close(handle)

        output_text(value)

      {:error, _} ->
        ""
    end
  end

  defp output_text(:eof), do: ""

  defp output_text(bytes) when is_binary(bytes) do
    if String.valid?(bytes), do: bytes, else: "[non-UTF8 engine output]"
  end

  defp output_text(_), do: "[unreadable engine output]"
end
