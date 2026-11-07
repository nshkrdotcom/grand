defmodule Grand.Core.LifecycleStore do
  @moduledoc """
  Bounded local G03-only atomic journal. One validated record/revision per commit.

  An exclusive directory lock serializes local writers, a self-hashed append-only
  commit forms the complete change, and atomic HEAD rename publishes it. Orphan
  commits after interrupted pre-HEAD writes are invisible; no automatic repair.
  Readers validate the entire hash chain and all historical revisions before
  returning data. This is not production durability or hostile-user security.
  """

  alias Grand.Core.G03
  alias Grand.Core.JSON

  @sha ~r/\A[0-9a-f]{64}\z/
  @max_commits 512
  @max_bytes 4_000_000
  @kinds ~w(candidate requirement assumption obligation)

  @doc "Read all committed v2 histories, rejecting a damaged or conflicted chain."
  @spec read(binary()) :: {:ok, map()} | {:error, term()}
  def read(root) when is_binary(root) do
    with {:ok, head} <- read_head(root),
         {:ok, state} <- load_chain(root, head) do
      {:ok, Map.put(state, "head", head)}
    end
  end

  def read(_), do: {:error, :invalid_lifecycle_root}

  @doc "Return the current head token for optimistic compare-and-append."
  def head(root) do
    with {:ok, state} <- read(root), do: {:ok, state["head"]}
  end

  @doc "Exact immutable revision history; no implicit cross-version migration."
  def history(root, kind, id) when kind in @kinds and is_binary(id) do
    with {:ok, state} <- read(root) do
      case get_in(state, [kind, id]) do
        nil -> {:error, {:unresolved_g03_record, kind, id}}
        records -> {:ok, records}
      end
    end
  end

  def history(_, _, _), do: {:error, :invalid_lifecycle_lookup}

  def latest(root, kind, id) do
    with {:ok, revisions} <- history(root, kind, id), do: {:ok, List.last(revisions)}
  end

  @doc """
  Append with validated references and optional expected head. `:fault` is a
  test-only deterministic injection point, never exposed in the CLI. A returned
  failure after HEAD publication would have ambiguous commit status; callers must
  inspect HEAD before retrying. This implementation only injects before HEAD.
  """
  def append(root, kind, record, opts \\ [])

  def append(root, kind, record, opts)
      when is_binary(root) and kind in @kinds and is_list(opts) do
    with {:ok, _} <- G03.validate(kind, record),
         :ok <- File.mkdir_p(directory(root)),
         :ok <- acquire(root) do
      try do
        append_locked(root, kind, record, opts)
      after
        File.rmdir(lock_path(root))
      end
    end
  end

  def append(_, _, _, _), do: {:error, :invalid_lifecycle_append}

  defp append_locked(root, kind, record, opts) do
    with {:ok, state} <- read(root),
         :ok <- expected_head(state["head"], Keyword.get(opts, :expected_head, :any)),
         :ok <- commit_limit(state["head"]),
         :ok <- validate_next(state, kind, record, Keyword.get(opts, :resolve_source)),
         {:ok, commit} <- build_commit(state["head"], kind, record),
         {:ok, _path} <- publish_commit(root, commit, Keyword.get(opts, :fault)),
         :ok <- write_head(root, commit, Keyword.get(opts, :fault)) do
      {:ok, %{"head" => commit["digest"], "sequence" => commit["sequence"]}}
    end
  end

  defp expected_head(_, :any), do: :ok
  defp expected_head(current, current), do: :ok
  defp expected_head(_, _), do: {:error, :stale_lifecycle_head}

  defp commit_limit(nil), do: :ok
  defp commit_limit(%{"sequence" => n}) when n < @max_commits, do: :ok
  defp commit_limit(_), do: {:error, :lifecycle_commit_limit}

  defp validate_next(state, kind, r, resolver) do
    previous = state |> Map.get(kind, %{}) |> Map.get(r["id"], []) |> List.last()

    with :ok <- G03.transition(kind, previous, r),
         :ok <- validate_links(state, kind, r) do
      validate_sources(kind, r, resolver)
    end
  end

  defp validate_links(state, "requirement", r) do
    with :ok <- require_revisions(state, "assumption", r["assumptions"], r["scope"]),
         :ok <- optional_candidate(state, r) do
      replacement(state, "requirement", r)
    end
  end

  defp validate_links(state, "obligation", r) do
    target = r["requirement"]

    with {:ok, req} <- exact(state, "requirement", target),
         :ok <- test(req["status"] == "approved", :requirement_revision_not_approved),
         :ok <- test(req["scope"] == r["scope"], :requirement_scope_mismatch),
         :ok <-
           test(
             Enum.all?(r["source_refs"], &(&1 in req["behavior_refs"])),
             :obligation_reference_not_in_requirement
           ),
         :ok <-
           test(
             r["assumptions"] == req["assumptions"],
             :obligation_assumption_revisions_mismatch
           ) do
      require_revisions(state, "assumption", r["assumptions"], r["scope"])
    end
  end

  defp validate_links(state, kind, r) do
    replacement(state, kind, r)
  end

  defp optional_candidate(state, r) do
    case r["source_candidate_id"] do
      nil ->
        :ok

      id ->
        case get_in(state, ["candidate", id]) do
          [_ | _] = versions ->
            test(List.last(versions)["scope"] == r["scope"], :candidate_scope_mismatch)

          _ ->
            {:error, {:dangling_candidate, id}}
        end
    end
  end

  defp replacement(state, kind, %{"status" => "superseded", "superseded_by" => id} = r) do
    case get_in(state, [kind, id]) do
      nil ->
        {:error, {:dangling_supersession, kind, id}}

      versions ->
        replacement = List.last(versions)

        if replacement["scope"] == r["scope"] and
             replacement["status"] in ~w(approved proposed open attested tested discharged) do
          :ok
        else
          {:error, :incompatible_supersession_target}
        end
    end
  end

  defp replacement(_, _, _), do: :ok

  defp require_revisions(state, kind, refs, scope) do
    Enum.reduce_while(refs, :ok, fn ref, :ok ->
      case exact(state, kind, ref) do
        {:ok, %{"scope" => ^scope}} -> {:cont, :ok}
        {:ok, _} -> {:halt, {:error, {:reference_scope_mismatch, kind, ref}}}
        error -> {:halt, error}
      end
    end)
  end

  defp exact(state, kind, %{"id" => id, "revision" => revision}) do
    case get_in(state, [kind, id]) do
      nil ->
        {:error, {:dangling_lifecycle_revision, kind, id, revision}}

      versions ->
        case Enum.find(versions, &(&1["revision"] == revision)) do
          nil -> {:error, {:dangling_lifecycle_revision, kind, id, revision}}
          record -> {:ok, record}
        end
    end
  end

  defp validate_sources(kind, r, resolver) do
    resolve_sources(source_refs(kind, r), resolver)
  end

  defp source_refs("candidate", r), do: r["source_refs"]
  defp source_refs("requirement", r), do: r["behavior_refs"]
  defp source_refs("assumption", r), do: Enum.flat_map(r["evidence"], & &1["source_refs"])
  defp source_refs("obligation", r), do: r["source_refs"] ++ r["witness"]["source_refs"]

  defp resolve_sources([], _), do: :ok

  defp resolve_sources(refs, resolver) when is_function(resolver, 1) do
    Enum.reduce_while(refs, :ok, fn ref, :ok -> resolve_source(resolver.(ref)) end)
  end

  defp resolve_sources(_, _), do: {:error, :exact_source_resolver_required}

  defp resolve_source({:ok, _}), do: {:cont, :ok}
  defp resolve_source({:error, reason}), do: {:halt, {:error, {:unresolved_exact_source, reason}}}
  defp resolve_source(_), do: {:halt, {:error, :invalid_exact_source_resolver_result}}

  defp build_commit(head, kind, record) do
    payload = %{
      "format" => "grand.g03.lifecycle.commit",
      "schema_version" => 2,
      "sequence" => if(is_nil(head), do: 1, else: head["sequence"] + 1),
      "parent" => if(is_nil(head), do: nil, else: head["digest"]),
      "kind" => kind,
      "record" => record
    }

    with {:ok, bytes} <- JSON.encode(payload),
         :ok <- test(byte_size(bytes) <= @max_bytes, :lifecycle_commit_oversized) do
      {:ok, Map.put(payload, "digest", digest(bytes))}
    end
  end

  defp publish_commit(root, commit, fault) do
    path = commit_path(root, commit["digest"])

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, encoded} <- JSON.encode(commit),
         {:ok, temp} <- stage(path, encoded),
         result <- link_commit(temp, path, fault) do
      File.rm(temp)
      result
    end
  end

  defp link_commit(_temp, _path, :before_commit), do: {:error, :injected_before_commit}

  defp link_commit(temp, path, _) do
    case File.ln(temp, path) do
      :ok ->
        {:ok, path}

      {:error, :eexist} ->
        identical_commit(temp, path)

      {:error, reason} ->
        {:error, {:lifecycle_commit_publish_failed, reason}}
    end
  end

  defp identical_commit(temp, path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, ^bytes} <- File.read(temp) do
      {:ok, path}
    else
      _ -> {:error, :lifecycle_commit_conflict}
    end
  end

  defp write_head(_root, _commit, :before_head), do: {:error, :injected_before_head}

  defp write_head(root, commit, _) do
    path = head_path(root)

    pointer = %{
      "format" => "grand.g03.lifecycle.head",
      "schema_version" => 2,
      "digest" => commit["digest"],
      "sequence" => commit["sequence"]
    }

    with {:ok, encoded} <- JSON.encode(pointer),
         {:ok, temp} <- stage(path, encoded) do
      result = File.rename(temp, path)
      File.rm(temp)
      result
    end
  end

  defp stage(path, bytes) when byte_size(bytes) <= @max_bytes do
    temp = path <> ".tmp-" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)

    case File.open(temp, [:write, :binary, :exclusive]) do
      {:ok, handle} ->
        result =
          with :ok <- IO.binwrite(handle, bytes), do: :file.sync(handle)

        File.close(handle)

        case result do
          :ok ->
            {:ok, temp}

          error ->
            File.rm(temp)
            error
        end

      error ->
        error
    end
  end

  defp stage(_, _), do: {:error, :lifecycle_commit_oversized}

  defp read_head(root) do
    case read_file(head_path(root)) do
      {:error, :enoent} ->
        {:ok, nil}

      {:ok, json} ->
        with {:ok, head} <- JSON.decode(json),
             :ok <-
               test(
                 is_map(head) and
                   Enum.sort(Map.keys(head)) == ~w(digest format schema_version sequence) and
                   head_pointer?(head),
                 :corrupt_lifecycle_head
               ),
             {:ok, canonical} <- JSON.encode(head),
             :ok <- test(json == canonical, :noncanonical_lifecycle_head) do
          {:ok, head}
        end

      error ->
        error
    end
  end

  defp load_chain(_root, nil), do: {:ok, empty_state()}

  defp load_chain(root, head) do
    with {:ok, commits} <- follow(root, head["digest"], head["sequence"], %{}, []),
         do: replay(commits)
  end

  defp follow(_root, nil, 0, _seen, commits), do: {:ok, commits}
  defp follow(_root, _, 0, _seen, _), do: {:error, :invalid_lifecycle_chain_root}

  defp follow(root, digest_id, sequence, seen, commits) do
    if not sha?(digest_id) or Map.has_key?(seen, digest_id) do
      {:error, :cycle_or_invalid_lifecycle_digest}
    else
      with {:ok, json} <- read_file(commit_path(root, digest_id)),
           {:ok, commit} <- JSON.decode(json),
           :ok <- validate_commit(commit, json, digest_id, sequence) do
        follow(root, commit["parent"], sequence - 1, Map.put(seen, digest_id, true), [
          commit | commits
        ])
      end
    end
  end

  defp head_pointer?(head) do
    head["format"] == "grand.g03.lifecycle.head" and head["schema_version"] == 2 and
      sha?(head["digest"]) and is_integer(head["sequence"]) and
      head["sequence"] in 1..@max_commits
  end

  defp valid_parent?(nil, 1), do: true
  defp valid_parent?(parent, sequence) when sequence > 1, do: sha?(parent)
  defp valid_parent?(_, _), do: false

  defp validate_commit(c, encoded, expected_hash, sequence) when is_map(c) do
    expected_keys = ~w(digest format kind parent record schema_version sequence)
    payload = Map.delete(c, "digest")

    with :ok <-
           test(
             Enum.sort(Map.keys(c)) == expected_keys and
               c["format"] == "grand.g03.lifecycle.commit" and c["schema_version"] == 2 and
               c["kind"] in @kinds and c["sequence"] == sequence and
               valid_parent?(c["parent"], sequence),
             :corrupt_lifecycle_commit
           ),
         {:ok, bytes} <- JSON.encode(payload),
         :ok <-
           test(
             digest(bytes) == expected_hash and c["digest"] == expected_hash,
             :lifecycle_commit_hash_mismatch
           ),
         {:ok, canonical} <- JSON.encode(c),
         :ok <- test(canonical == encoded, :noncanonical_lifecycle_commit),
         {:ok, _} <- G03.validate(c["kind"], c["record"]) do
      :ok
    end
  end

  defp validate_commit(_, _, _, _), do: {:error, :corrupt_lifecycle_commit}

  defp replay(commits) do
    Enum.reduce_while(commits, {:ok, empty_state()}, fn c, {:ok, state} ->
      kind = c["kind"]
      record = c["record"]
      id = record["id"]
      versions = get_in(state, [kind, id]) || []
      previous = List.last(versions)

      with :ok <- G03.transition(kind, previous, record),
           :ok <- validate_links(state, kind, record) do
        updated = put_in(state, [kind, id], versions ++ [record])
        {:cont, {:ok, updated}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp empty_state do
    %{"candidate" => %{}, "requirement" => %{}, "assumption" => %{}, "obligation" => %{}}
  end

  defp read_file(path) do
    with {:ok, stat} <- File.stat(path),
         :ok <- test(stat.type == :regular and stat.size <= @max_bytes, :invalid_lifecycle_file) do
      File.read(path)
    end
  end

  defp acquire(root) do
    case File.mkdir(lock_path(root)) do
      :ok -> :ok
      {:error, :eexist} -> {:error, :lifecycle_writer_busy}
      error -> error
    end
  end

  defp directory(root), do: Path.join(root, "g03_lifecycle_v2")
  defp head_path(root), do: Path.join(directory(root), "HEAD.json")
  defp lock_path(root), do: Path.join(directory(root), "writer.lock")
  defp commit_path(root, hash), do: Path.join([directory(root), "commits", hash <> ".json"])
  defp sha?(value), do: is_binary(value) and Regex.match?(@sha, value)
  defp digest(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp test(true, _), do: :ok
  defp test(_, reason), do: {:error, reason}
end
