defmodule Grand.Assurance.G04.Runner do
  @moduledoc """
  Small local subprocess boundary for the two supported engines only. Source
  imports never use this module. Executables are found by name, arguments are
  supplied as an argv vector (never interpolated into shell text), and the
  workspace is deleted after execution. A fixed shell wrapper redirects the
  two streams; callers never supply shell source or executable names.

  This is bounded local process control, NOT a container/network sandbox.
  Run only trusted checker/law files on a trusted host.
  """

  @engines ~w(lean java)
  @files ~w(Law.lean Model.tla Model.cfg)
  @shell ~s(exec "$@" >stdout.log 2>stderr.log)

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
            start(executable, plan["args"], workspace, opts)
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
  def skipped(reason) when reason in ~w(unrun missing_engine missing_tlc_jar) do
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
    allowed_args =
      is_list(args) and length(args) <= 20 and
        Enum.all?(args, fn value ->
          is_binary(value) and byte_size(value) in 1..1_024 and String.valid?(value) and
            not String.contains?(value, [<<0>>, "\n", "\r"])
        end)

    allowed_files =
      is_map(files) and map_size(files) <= 3 and
        Enum.all?(files, fn {name, content} ->
          name in @files and is_binary(content) and byte_size(content) <= 256_000
        end)

    if engine in @engines and allowed_args and allowed_files and command_allowed?(engine, args, files) do
      :ok
    else
      {:error, :unsafe_runner_plan}
    end
  end

  defp valid_plan(_), do: {:error, :unsafe_runner_plan}

  defp command_allowed?("lean", ["--version"], files), do: map_size(files) == 0
  defp command_allowed?("lean", ["Law.lean"], files), do: Map.keys(files) == ["Law.lean"]

  defp command_allowed?(
         "java",
         ["-Xmx256m", "-cp", path, "tlc2.TLC", "-config", "Model.cfg", "-workers", "1", "Model.tla"],
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
        "grand-g04-#{System.unique_integer([:positive, :monotonic])}"
      )

    case File.mkdir(path) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, {:workspace_create_failed, reason}}
    end
  end

  defp stage(dir, files) do
    Enum.reduce_while(files, :ok, fn {name, content}, :ok ->
      case File.write(Path.join(dir, name), content, [:exclusive, :binary]) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:workspace_write_failed, reason}}}
      end
    end)
  end

  defp start(executable, arguments, dir, opts) do
    case System.find_executable("sh") do
      nil -> {:error, :runner_shell_unavailable}
      shell -> launch(shell, executable, arguments, dir, opts)
    end
  end

  defp launch(shell, executable, arguments, dir, opts) do
    argv = ["-c", @shell, "grand-g04", executable | arguments]

    port =
      Port.open({:spawn_executable, String.to_charlist(shell)}, [
        :binary,
        :exit_status,
        :hide,
        {:cd, String.to_charlist(dir)},
        {:args, Enum.map(argv, &String.to_charlist/1)}
      ])

    started = System.monotonic_time(:millisecond)
    await(port, dir, started, opts)
  end

  defp await(port, dir, started, opts) do
    elapsed = System.monotonic_time(:millisecond) - started
    timeout = Keyword.get(opts, :timeout_ms, 5_000)
    max_output = Keyword.get(opts, :output_limit_bytes, 65_536)
    token = Keyword.get(opts, :cancel_ref)

    cond do
      output_size(dir) > max_output ->
        stop(port)
        {:ok, captured(dir, nil, elapsed, "output_limit", max_output)}

      elapsed >= timeout ->
        stop(port)
        {:ok, captured(dir, nil, elapsed, "timeout", max_output)}

      true ->
        receive do
          {^port, {:exit_status, status}} ->
            reason = if output_size(dir) > max_output, do: "output_limit", else: nil
            {:ok, captured(dir, status, elapsed, reason, max_output)}

          {:g04_cancel, ^token} when is_reference(token) ->
            stop(port)
            {:ok, captured(dir, nil, elapsed, "cancelled", max_output)}
        after
          40 -> await(port, dir, started, opts)
        end
    end
  end

  defp output_size(dir) do
    Enum.reduce(["stdout.log", "stderr.log"], 0, fn name, size ->
      case File.stat(Path.join(dir, name)) do
        {:ok, stat} -> size + stat.size
        _ -> size
      end
    end)
  end

  defp stop(port) do
    if Port.info(port) != nil, do: Port.close(port)
  end

  defp captured(dir, exit_code, elapsed, reason, max_output) do
    %{
      "stdout" => read_capped(Path.join(dir, "stdout.log"), max_output),
      "stderr" => read_capped(Path.join(dir, "stderr.log"), max_output),
      "exit_code" => exit_code,
      "elapsed_ms" => elapsed,
      "reason" => reason
    }
  end

  defp read_capped(path, max_output) do
    case File.open(path, [:read, :binary]) do
      {:ok, handle} ->
        value = IO.binread(handle, max_output)
        File.close(handle)
        if is_binary(value) and String.valid?(value), do: value, else: "[non-UTF8 engine output]"

      {:error, _} ->
        ""
    end
  end
end
