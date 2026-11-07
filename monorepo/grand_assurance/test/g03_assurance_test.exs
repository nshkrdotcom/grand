defmodule Grand.Assurance.G03Test do
  use ExUnit.Case, async: true

  alias Grand.Assurance.G03
  alias Grand.Core.JSON
  alias Grand.Core.LifecycleStore

  @fixtures Path.expand("../../../fixtures", __DIR__)
  @at "2026-11-06T20:00:00Z"
  @review [actor: "human:fixture-reviewer", at: @at, ack_human: true]
  defp resolver, do: fn _ -> {:ok, %{"source_only" => true}} end

  setup do
    root =
      Path.join(System.tmp_dir!(), "grand-g03-assurance-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp input(name) do
    {:ok, value} = JSON.decode(File.read!(Path.join(@fixtures, "g03_#{name}_input.json")))
    value
  end

  defp opts, do: @review ++ [resolve_source: resolver()]

  defp approved(root) do
    {:ok, assumption} = G03.register_assumption(root, input("assumption"), opts())
    {:ok, draft} = G03.draft_requirement(root, input("requirement"), opts())
    {:ok, submitted} = G03.review_requirement(root, draft["id"], "submit", opts())
    {:ok, accepted} = G03.review_requirement(root, draft["id"], "approve", opts())
    {assumption, draft, submitted, accepted}
  end

  test "G03-TEST-01 human-only explicit approval and immutable revision history", %{root: root} do
    {:ok, _} = G03.register_assumption(root, input("assumption"), opts())
    {:ok, draft} = G03.draft_requirement(root, input("requirement"), opts())

    assert {:error, :explicit_human_review_ack_required_not_authenticated} =
             G03.review_requirement(root, draft["id"], "submit",
               actor: "agent:assistant",
               at: @at,
               ack_human: true
             )

    assert {:error, :explicit_human_review_ack_required_not_authenticated} =
             G03.review_requirement(root, draft["id"], "approve",
               actor: "human:reviewer",
               at: @at
             )

    assert {:error, :invalid_lifecycle_transition} =
             G03.review_requirement(root, draft["id"], "approve", opts())

    assert {:ok, pending} = G03.review_requirement(root, draft["id"], "submit", opts())
    assert pending["revision"] == 2
    assert {:ok, accepted} = G03.review_requirement(root, draft["id"], "approve", opts())
    assert accepted["revision"] == 3
    assert accepted["status"] == "approved"

    assert List.last(accepted["events"])["identity_assurance"] ==
             "self_attested_not_authenticated"

    assert {:ok, [^draft, ^pending, ^accepted]} = G03.history(root, "requirement", draft["id"])
  end

  test "G03-TEST-02 external attestation never discharges or proves assumption", %{root: root} do
    {assumption, _draft, _pending, approved} = approved(root)
    assert assumption["category"] == "external"
    assert {:ok, attested} = G03.revise_assumption(root, assumption["id"], "attest", opts())
    assert attested["status"] == "attested"

    assert {:error, _} =
             G03.revise_assumption(root, assumption["id"], "discharge", opts())

    assert {:ok, obligation} = G03.record_obligation(root, input("obligation"), opts())
    assert obligation["requirement"]["revision"] == approved["revision"]
    assert {:ok, receipt} = G03.receipt(root, obligation["id"])
    assert receipt["verification_result"]["status"] == "unrun"
    assert receipt["coverage_summary"]["status"] == "unassessed"
    assert receipt["assumption_revisions"] |> hd() |> get_in(["record", "status"]) == "open"

    assert receipt["assumption_revisions"] |> hd() |> get_in(["current", "status"]) ==
             "attested"

    assert receipt["conditional_on"] == [%{"id" => assumption["id"], "revision" => 1}]
    assert "No remote executed confirmation or service contract witness" in receipt["open_gaps"]
    assert receipt["guarantee"] == "none_unrun_conditional_record_not_a_proof"
  end

  test "G03-TEST-03 vacuity and contradiction are explicit challenges, not SAT string heuristics",
       %{root: root} do
    {_assumption, _draft, _pending, _approved} = approved(root)
    incomplete = put_in(input("obligation"), ["precondition_challenges"], [])
    assert {:error, _} = G03.record_obligation(root, incomplete, opts())
    assert {:ok, obligation} = G03.record_obligation(root, input("obligation"), opts())
    assert Enum.any?(obligation["precondition_challenges"], &(&1["kind"] == "contradiction"))
    assert {:ok, receipt} = G03.receipt(root, obligation["id"])
    assert receipt["eligibility"] == "blocked_for_witness_review"
    assert receipt["witness_challenge"]["feasibility"] == "not_checked"
  end

  test "G03-TEST-05 candidate remains non-normative even after proposal and rejection", %{
    root: root
  } do
    attrs = input("candidate")

    assert {:ok, proposed} =
             G03.propose(root, attrs,
               actor: "agent:source-spike",
               at: @at,
               resolve_source: resolver()
             )

    assert proposed["status"] == "proposed"
    assert {:error, _} = G03.latest(root, "requirement", proposed["id"])

    assert {:error, :explicit_human_review_ack_required_not_authenticated} =
             G03.decide_candidate(root, proposed["id"], "reject",
               actor: "ai:assistant",
               ack_human: true
             )

    assert {:ok, rejected} = G03.decide_candidate(root, proposed["id"], "reject", opts())
    assert rejected["status"] == "rejected"
    assert rejected["revision"] == 2

    assert {:error, :invalid_lifecycle_transition} =
             G03.decide_candidate(
               root,
               proposed["id"],
               "supersede",
               opts() ++ [replacement_id: "unknown"]
             )

    assert {:ok, [^proposed, ^rejected]} = G03.history(root, "candidate", proposed["id"])
  end

  test "G03-TEST-06 candidate keeps exact source context and counterhypothesis", %{root: root} do
    attrs = input("candidate")

    assert {:ok, proposed} =
             G03.propose(root, attrs, actor: "agent:motif", at: @at, resolve_source: resolver())

    assert proposed["counterhypothesis"] == attrs["counterhypothesis"]
    assert proposed["uncertainty"] == attrs["uncertainty"]
    assert proposed["source_refs"] == attrs["source_refs"]
    assert Enum.all?(proposed["source_refs"], &(&1["schema_version"] == 2))

    assert {:error, {:unresolved_exact_source, :missing}} =
             G03.propose(root, %{attrs | "id" => "other-question"},
               actor: "agent:motif",
               at: @at,
               resolve_source: fn _ -> {:error, :missing} end
             )
  end

  test "dangling and mismatched exact requirement, assumption and source links", %{root: root} do
    attrs = input("requirement")

    assert {:error, {:dangling_lifecycle_revision, "assumption", _, 1}} =
             G03.draft_requirement(root, attrs, opts())

    {:ok, _} = G03.register_assumption(root, input("assumption"), opts())
    wrong_scope = put_in(attrs, ["scope", "project_id"], "somewhere-else")
    assert {:error, _} = G03.draft_requirement(root, wrong_scope, opts())
    {_assumption, _draft, _pending, _approved} = approved_after_assumption(root)

    wrong_revision = put_in(input("obligation"), ["requirement", "revision"], 99)

    assert {:error, {:dangling_lifecycle_revision, "requirement", _, 99}} =
             G03.record_obligation(root, wrong_revision, opts())

    wrong_assumption = put_in(input("obligation"), ["assumptions", Access.at(0), "revision"], 2)

    assert {:error, :obligation_assumption_revisions_mismatch} =
             G03.record_obligation(root, wrong_assumption, opts())

    unapproved = put_in(input("obligation"), ["requirement", "revision"], 2)

    assert {:error, :requirement_revision_not_approved} =
             G03.record_obligation(root, unapproved, opts())

    original = input("obligation")

    forged =
      put_in(
        original,
        ["source_refs", Access.at(0), "object_id"],
        "entity:not-in-approved-requirement"
      )

    assert {:error, :obligation_reference_not_in_requirement} =
             G03.record_obligation(root, forged, opts())
  end

  test "supersession keeps approved old versions and refuses incompatible replacement", %{
    root: root
  } do
    {_assumption, _draft, _pending, accepted} = approved(root)

    assert {:error, _} =
             G03.review_requirement(
               root,
               accepted["id"],
               "supersede",
               opts() ++ [replacement_id: "missing"]
             )

    second = Map.put(input("requirement"), "id", "g03-approved-successor")
    assert {:ok, _} = G03.draft_requirement(root, second, opts())
    assert {:ok, _} = G03.review_requirement(root, second["id"], "submit", opts())
    assert {:ok, _} = G03.review_requirement(root, second["id"], "approve", opts())

    assert {:ok, superseded} =
             G03.review_requirement(
               root,
               accepted["id"],
               "supersede",
               opts() ++ [replacement_id: second["id"]]
             )

    assert superseded["revision"] == 4
    assert superseded["superseded_by"] == second["id"]
    assert {:ok, revisions} = G03.history(root, "requirement", accepted["id"])
    assert Enum.at(revisions, 2) == accepted
    assert length(revisions) == 4
    assert {:ok, state} = LifecycleStore.read(root)
    assert length(state["requirement"][accepted["id"]]) == 4
  end

  test "candidate successor can be explicitly superseded without creating requirement", %{
    root: root
  } do
    first_attrs = input("candidate")
    successor_attrs = Map.put(first_attrs, "id", "g03-successor-question")

    assert {:ok, successor} =
             G03.propose(root, successor_attrs,
               actor: "agent:spike",
               at: @at,
               resolve_source: resolver()
             )

    assert {:ok, proposed} =
             G03.propose(root, first_attrs,
               actor: "agent:spike",
               at: @at,
               resolve_source: resolver()
             )

    assert {:ok, superseded} =
             G03.decide_candidate(
               root,
               proposed["id"],
               "supersede",
               opts() ++ [replacement_id: successor["id"]]
             )

    assert superseded["status"] == "superseded"
    assert superseded["superseded_by"] == successor["id"]
    assert superseded["source_refs"] == proposed["source_refs"]
    assert {:ok, [^proposed, ^superseded]} = G03.history(root, "candidate", proposed["id"])
    assert {:error, _} = G03.latest(root, "requirement", proposed["id"])
  end

  test "four assumption categories and reviewed test evidence preserve original gaps", %{
    root: root
  } do
    for category <- ~w(external compiler model runtime) do
      attrs = input("assumption")
      attrs = %{attrs | "category" => category, "id" => "g03-#{category}-assumption"}
      assert {:ok, initial} = G03.register_assumption(root, attrs, opts())
      assert initial["category"] == category
      assert initial["revision"] == 1

      testing = %{
        "kind" => "test",
        "description" => "Reviewer-supplied local test evidence, not proof",
        "source_refs" => []
      }

      assert {:ok, assessed} =
               G03.revise_assumption(root, initial["id"], "test", opts() ++ [evidence: [testing]])

      assert assessed["revision"] == 2
      assert assessed["gaps"] == initial["gaps"]
      assert {:ok, discharged} = G03.revise_assumption(root, initial["id"], "discharge", opts())
      assert discharged["status"] == "discharged"
      assert discharged["gaps"] == initial["gaps"]

      assert {:ok, [^initial, ^assessed, ^discharged]} =
               G03.history(root, "assumption", initial["id"])
    end
  end

  test "candidate provenance cannot cross normative scope", %{root: root} do
    attrs = input("candidate")
    other_scope = %{attrs["scope"] | "project_id" => "other-project"}
    refs = Enum.map(attrs["source_refs"], &Map.put(&1, "project_id", "other-project"))

    assert {:ok, question} =
             G03.propose(
               root,
               %{attrs | "scope" => other_scope, "source_refs" => refs},
               actor: "agent:spike",
               resolve_source: resolver()
             )

    assert {:ok, _} = G03.register_assumption(root, input("assumption"), opts())
    draft = Map.put(input("requirement"), "source_candidate_id", question["id"])
    assert {:error, :candidate_scope_mismatch} = G03.draft_requirement(root, draft, opts())
    assert {:error, _} = G03.latest(root, "requirement", draft["id"])
  end

  test "conditional receipt resolves approved history after supersession", %{root: root} do
    {_assumption, _draft, _pending, accepted} = approved(root)
    successor = Map.put(input("requirement"), "id", "g03-new-intent")
    assert {:ok, _} = G03.draft_requirement(root, successor, opts())
    assert {:ok, _} = G03.review_requirement(root, successor["id"], "submit", opts())
    assert {:ok, _} = G03.review_requirement(root, successor["id"], "approve", opts())

    assert {:ok, _} =
             G03.review_requirement(
               root,
               accepted["id"],
               "supersede",
               opts() ++ [replacement_id: successor["id"]]
             )

    assert {:ok, obligation} = G03.record_obligation(root, input("obligation"), opts())
    assert {:ok, receipt} = G03.receipt(root, obligation["id"])
    assert receipt["requirement"] == accepted
    assert receipt["requirement"]["revision"] == 3
    assert receipt["verification_result"]["status"] == "unrun"
  end

  test "assumption evidence exact refs are resolved before publishing revision", %{root: root} do
    assert {:ok, original} = G03.register_assumption(root, input("assumption"), opts())

    evidence = %{
      "kind" => "test",
      "description" => "Untrusted claimed test evidence",
      "source_refs" => input("candidate")["source_refs"]
    }

    assert {:error, {:unresolved_exact_source, :forged_evidence}} =
             G03.revise_assumption(
               root,
               original["id"],
               "test",
               @review ++
                 [evidence: [evidence], resolve_source: fn _ -> {:error, :forged_evidence} end]
             )

    assert {:ok, [^original]} = G03.history(root, "assumption", original["id"])
  end

  test "human rejection is terminal and a forged initial approval is never published", %{
    root: root
  } do
    assert {:ok, _} = G03.register_assumption(root, input("assumption"), opts())
    assert {:ok, draft} = G03.draft_requirement(root, input("requirement"), opts())
    assert {:ok, pending} = G03.review_requirement(root, draft["id"], "submit", opts())
    assert {:ok, rejected} = G03.review_requirement(root, draft["id"], "reject", opts())
    assert rejected["status"] == "rejected"
    assert List.last(rejected["events"])["action"] == "reject"

    assert {:error, :invalid_lifecycle_transition} =
             G03.review_requirement(root, draft["id"], "approve", opts())

    assert {:ok, [^draft, ^pending, ^rejected]} = G03.history(root, "requirement", draft["id"])

    assert {:error, :requirement_revision_not_approved} =
             G03.record_obligation(root, input("obligation"), opts())

    approval = %{hd(draft["events"]) | "action" => "approve"}

    forged = %{
      draft
      | "id" => "g03-forged-approval",
        "status" => "approved",
        "events" => [approval]
    }

    assert {:error, :invalid_initial_lifecycle_event} =
             LifecycleStore.append(root, "requirement", forged, resolve_source: resolver())

    assert {:error, _} = G03.latest(root, "requirement", forged["id"])
  end

  defp approved_after_assumption(root) do
    {:ok, draft} = G03.draft_requirement(root, input("requirement"), opts())
    {:ok, pending} = G03.review_requirement(root, draft["id"], "submit", opts())
    {:ok, approved} = G03.review_requirement(root, draft["id"], "approve", opts())
    {nil, draft, pending, approved}
  end
end
