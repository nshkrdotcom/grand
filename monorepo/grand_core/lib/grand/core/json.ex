defmodule Grand.Core.JSON do
  @moduledoc """
  Small, dependency-free JSON codec for bounded, data-only inputs.

  Decode rejects duplicate object keys, invalid Unicode, excessive nesting, excess
  node count and oversized inputs. It never creates atoms from untrusted strings.
  Encode sorts all object keys, making emitted JSON byte-deterministic.
  """

  @default_bytes 4_000_000
  @default_depth 32
  @default_nodes 100_000
  @number ~r/\A-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/

  @spec decode(binary(), keyword()) :: {:ok, term()} | {:error, term()}
  def decode(json, opts \\ [])

  def decode(json, opts) when is_binary(json) do
    max_bytes = Keyword.get(opts, :max_bytes, @default_bytes)
    max_depth = Keyword.get(opts, :max_depth, @default_depth)
    max_nodes = Keyword.get(opts, :max_nodes, @default_nodes)

    cond do
      not valid_limit?(max_bytes) or not valid_limit?(max_depth) or not valid_limit?(max_nodes) ->
        {:error, {:invalid_json, :invalid_limits}}

      byte_size(json) > max_bytes ->
        {:error, {:invalid_json, :too_large}}

      not String.valid?(json) ->
        {:error, {:invalid_json, :invalid_unicode}}

      true ->
        decode_value(json, max_depth, max_nodes)
    end
  end

  def decode(_other, _opts), do: {:error, {:invalid_json, :not_binary}}

  defp decode_value(json, max_depth, max_nodes) do
    case value(ws(json), 0, max_depth, max_nodes) do
      {:ok, parsed, trailing, _remaining} -> finish_decode(parsed, ws(trailing))
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp finish_decode(parsed, ""), do: {:ok, parsed}
  defp finish_decode(_, _), do: {:error, {:invalid_json, :trailing_data}}

  @spec encode(term()) :: {:ok, binary()} | {:error, term()}
  def encode(value) do
    case emit(value) do
      {:ok, output} -> {:ok, IO.iodata_to_binary(output)}
      {:error, reason} -> {:error, {:invalid_json_value, reason}}
    end
  end

  defp valid_limit?(v), do: is_integer(v) and v > 0

  defp ws(<<?\s, rest::binary>>), do: ws(rest)
  defp ws(<<?\t, rest::binary>>), do: ws(rest)
  defp ws(<<?\r, rest::binary>>), do: ws(rest)
  defp ws(<<?\n, rest::binary>>), do: ws(rest)
  defp ws(rest), do: rest

  defp value(_text, _depth, _max_depth, 0), do: {:error, :node_limit}
  defp value(_text, depth, max_depth, _budget) when depth > max_depth, do: {:error, :depth_limit}

  defp value(<<?\", rest::binary>>, _depth, _max_depth, budget) do
    case string(rest, []) do
      {:ok, decoded, trailing} -> {:ok, decoded, trailing, budget - 1}
      error -> error
    end
  end

  defp value(<<?{, rest::binary>>, depth, max_depth, budget),
    do: object(ws(rest), depth + 1, max_depth, budget - 1, %{})

  defp value(<<?[, rest::binary>>, depth, max_depth, budget),
    do: array(ws(rest), depth + 1, max_depth, budget - 1, [])

  defp value(<<"true", rest::binary>>, _depth, _max_depth, budget),
    do: {:ok, true, rest, budget - 1}

  defp value(<<"false", rest::binary>>, _depth, _max_depth, budget),
    do: {:ok, false, rest, budget - 1}

  defp value(<<"null", rest::binary>>, _depth, _max_depth, budget),
    do: {:ok, nil, rest, budget - 1}

  defp value(input, _depth, _max_depth, budget), do: number(input, budget - 1)

  defp object(<<?}, rest::binary>>, _depth, _max_depth, budget, map),
    do: {:ok, map, rest, budget}

  defp object(input, depth, max_depth, budget, map) do
    with {:ok, key, after_key} <- object_key(input),
         false <- Map.has_key?(map, key),
         <<?:, after_colon::binary>> <- ws(after_key),
         {:ok, decoded, after_value, remaining} <-
           value(ws(after_colon), depth, max_depth, budget) do
      object_tail(ws(after_value), depth, max_depth, remaining, Map.put(map, key, decoded))
    else
      true -> {:error, :duplicate_key}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :malformed_object}
    end
  end

  defp object_tail(<<?}, rest::binary>>, _depth, _max_depth, budget, map),
    do: {:ok, map, rest, budget}

  defp object_tail(<<?,, rest::binary>>, depth, max_depth, budget, map) do
    case ws(rest) do
      <<?}, _::binary>> -> {:error, :trailing_comma}
      next -> object(next, depth, max_depth, budget, map)
    end
  end

  defp object_tail(_, _, _, _, _), do: {:error, :malformed_object}

  defp object_key(<<?\", rest::binary>>), do: string(rest, [])
  defp object_key(_), do: {:error, :object_key_not_string}

  defp array(<<?], rest::binary>>, _depth, _max_depth, budget, items),
    do: {:ok, Enum.reverse(items), rest, budget}

  defp array(input, depth, max_depth, budget, items) do
    with {:ok, decoded, tail, remaining} <- value(input, depth, max_depth, budget) do
      array_tail(ws(tail), depth, max_depth, remaining, [decoded | items])
    end
  end

  defp array_tail(<<?], rest::binary>>, _depth, _max_depth, budget, items),
    do: {:ok, Enum.reverse(items), rest, budget}

  defp array_tail(<<?,, rest::binary>>, depth, max_depth, budget, items) do
    case ws(rest) do
      <<?], _::binary>> -> {:error, :trailing_comma}
      next -> array(next, depth, max_depth, budget, items)
    end
  end

  defp array_tail(_, _, _, _, _), do: {:error, :malformed_array}

  defp number(input, budget) do
    case Regex.run(@number, input) do
      [part] when byte_size(part) <= 128 ->
        trailing = binary_part(input, byte_size(part), byte_size(input) - byte_size(part))

        parse_number(part, trailing, budget)

      _ ->
        {:error, :invalid_value}
    end
  end

  defp parse_number(part, trailing, budget) do
    result =
      if String.contains?(part, [".", "e", "E"]),
        do: Float.parse(part),
        else: Integer.parse(part)

    case result do
      {parsed, ""} -> {:ok, parsed, trailing, budget}
      _ -> {:error, :invalid_number}
    end
  end

  defp string(<<?\", rest::binary>>, acc),
    do: {:ok, IO.iodata_to_binary(Enum.reverse(acc)), rest}

  defp string(<<?\\, ?u, a, b, c, d, rest::binary>>, acc) do
    case hex4(<<a, b, c, d>>) do
      {:ok, codepoint} -> escaped_unicode(codepoint, rest, acc)
      _ -> {:error, :invalid_unicode_escape}
    end
  end

  defp string(<<?\\, escaped, rest::binary>>, acc) do
    replacement = string_escape(escaped)

    if replacement == nil,
      do: {:error, :invalid_string_escape},
      else: string(rest, [replacement | acc])
  end

  defp string(<<c, _rest::binary>>, _acc) when c < 0x20,
    do: {:error, :unescaped_control}

  defp string(<<cp::utf8, rest::binary>>, acc), do: string(rest, [<<cp::utf8>> | acc])
  defp string(_, _), do: {:error, :invalid_or_unterminated_string}

  defp string_escape(escaped),
    do:
      Map.get(
        %{
          ?" => "\"",
          ?\\ => "\\",
          ?/ => "/",
          ?b => <<8>>,
          ?f => <<12>>,
          ?n => "\n",
          ?r => "\r",
          ?t => "\t"
        },
        escaped
      )

  defp hex4(value) do
    case Integer.parse(value, 16) do
      {number, ""} -> {:ok, number}
      _ -> {:error, :invalid_hex}
    end
  end

  defp escaped_unicode(high, <<?\\, ?u, a, b, c, d, rest::binary>>, acc)
       when high >= 0xD800 and high <= 0xDBFF do
    with {:ok, low} <- hex4(<<a, b, c, d>>),
         true <- low >= 0xDC00 and low <= 0xDFFF do
      cp = 0x10000 + (high - 0xD800) * 1024 + low - 0xDC00
      string(rest, [<<cp::utf8>> | acc])
    else
      _ -> {:error, :invalid_surrogate_pair}
    end
  end

  defp escaped_unicode(high, _rest, _acc) when high >= 0xD800 and high <= 0xDBFF,
    do: {:error, :invalid_surrogate_pair}

  defp escaped_unicode(low, _rest, _acc) when low >= 0xDC00 and low <= 0xDFFF,
    do: {:error, :unpaired_surrogate}

  defp escaped_unicode(cp, rest, acc), do: string(rest, [<<cp::utf8>> | acc])

  defp emit(nil), do: {:ok, "null"}
  defp emit(true), do: {:ok, "true"}
  defp emit(false), do: {:ok, "false"}
  defp emit(v) when is_integer(v), do: {:ok, Integer.to_string(v)}

  defp emit(v) when is_float(v) do
    if abs(v) < 1.0e308,
      do: {:ok, Float.to_string(v)},
      else: {:error, :non_finite_float}
  end

  defp emit(v) when is_binary(v) do
    if String.valid?(v), do: {:ok, quoted(v)}, else: {:error, :invalid_unicode}
  end

  defp emit(values) when is_list(values) do
    with {:ok, encoded} <- emit_all(values) do
      {:ok, ["[", Enum.intersperse(encoded, ","), "]"]}
    end
  end

  defp emit(map) when is_map(map) do
    if Enum.all?(Map.keys(map), &is_binary/1) do
      emit_object(map)
    else
      {:error, :non_string_key}
    end
  end

  defp emit({key, value}) when is_binary(key) do
    with {:ok, encoded} <- emit(value) do
      {:ok, [quoted(key), ":", encoded]}
    end
  end

  defp emit(_), do: {:error, :unsupported_type}

  defp emit_object(map) do
    entries = map |> Map.keys() |> Enum.sort() |> Enum.map(&{&1, Map.fetch!(map, &1)})

    with {:ok, encoded} <- emit_all(entries) do
      {:ok, ["{", Enum.intersperse(encoded, ","), "}"]}
    end
  end

  defp emit_all(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case emit(item) do
        {:ok, encoded} -> {:cont, {:ok, [encoded | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp quoted(text) do
    encoded =
      text
      |> String.to_charlist()
      |> Enum.map(fn
        ?\" ->
          "\\\""

        ?\\ ->
          "\\\\"

        ?\b ->
          "\\b"

        ?\f ->
          "\\f"

        ?\n ->
          "\\n"

        ?\r ->
          "\\r"

        ?\t ->
          "\\t"

        codepoint when codepoint < 32 ->
          "\\u" <> String.pad_leading(Integer.to_string(codepoint, 16), 4, "0")

        codepoint ->
          <<codepoint::utf8>>
      end)

    ["\"", encoded, "\""]
  end
end
