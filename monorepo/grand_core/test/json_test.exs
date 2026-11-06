defmodule Grand.Core.JSONTest do
  use ExUnit.Case, async: true
  alias Grand.Core
  alias Grand.Core.JSON

  test "canonical object ordering and Unicode roundtrip" do
    data = %{"z" => [true, nil, "🌍"], "a" => %{"k" => 1}}
    assert {:ok, encoded} = JSON.encode(data)
    assert encoded == "{\"a\":{\"k\":1},\"z\":[true,null,\"🌍\"]}"
    assert {:ok, ^data} = JSON.decode(encoded)
    assert {:ok, %{"text" => "𝄞"}} = JSON.decode(~S({"text":"\uD834\uDD1E"}))
  end

  test "duplicate keys, malformed syntax, Unicode, and limits fail closed" do
    assert {:error, {:invalid_json, :duplicate_key}} = JSON.decode(~S({"a":1,"a":2}))
    assert {:error, {:invalid_json, :trailing_comma}} = JSON.decode(~S({"a":1,}))
    assert {:error, {:invalid_json, :unpaired_surrogate}} = JSON.decode(~S("\uDC00"))
    assert {:error, {:invalid_json, :invalid_surrogate_pair}} = JSON.decode(~S("\uD800"))
    assert {:error, {:invalid_json, :too_large}} = JSON.decode("{}", max_bytes: 1)
    assert {:error, {:invalid_json, :depth_limit}} = JSON.decode("[[1]]", max_depth: 1)
    assert {:error, {:invalid_json, :node_limit}} = JSON.decode("[1,2]", max_nodes: 2)
    assert {:error, {:invalid_json, :trailing_data}} = JSON.decode("true false")
  end

  test "number and escape parsing survive codec refactoring" do
    assert {:ok, [1, -2, 1.5, 100.0]} = JSON.decode("[1,-2,1.5,1e2]")
    assert {:ok, "\"\\/\b\f\n\r\t"} = JSON.decode(~S("\"\\\/\b\f\n\r\t"))
    assert {:error, {:invalid_json, :invalid_string_escape}} = JSON.decode(~S("\x"))
    assert {:error, {:invalid_json, :invalid_number}} = JSON.decode("1e9999")
    assert {:ok, encoded} = JSON.encode(%{"a" => [%{"b" => 1.5}]})
    assert {:ok, %{"a" => [%{"b" => 1.5}]}} = JSON.decode(encoded)
  end

  test "Grand normative schema rejects fabricated verified boolean" do
    run = %{
      "schema_version" => 1,
      "run_id" => "r1",
      "obligation_id" => "o1",
      "status" => "unrun",
      "input_fingerprint" => "sha256:example",
      "engine" => "none",
      "scope" => %{},
      "recorded_at" => "2026-11-06T00:00:00Z"
    }

    assert {:ok, ^run} = Core.validate("verification_result", run)

    assert {:error, {:invalid_record, "verification_result", errors}} =
             Core.validate("verification_result", Map.put(run, "verified", true))

    assert "unexpected \"verified\"" in errors

    assert {:error, {:invalid_record, "verification_result", _}} =
             Core.validate("verification_result", Map.put(run, "status", "success"))
  end
end
