defmodule Postgrex.Extensions.HStore do
  @moduledoc false
  import Postgrex.BinaryUtils
  use Postgrex.BinaryExtension, type: "hstore"

  def encode(_, map, _, _) when is_map(map),
    do: encode_hstore(map)
  def encode(type_info, value, _, _) do
    raise ArgumentError, Postgrex.Utils.encode_msg(type_info, value, "a map")
  end

  def decode(_, bin, _, _),
    do: decode_hstore(bin)

  ## Helpers

  defp encode_hstore(hstore_map) do
    keys_and_values = Enum.reduce hstore_map, "", fn ({key, value}, acc) ->
        [acc, encode_hstore_key(key), encode_hstore_value(value)]
    end
    :erlang.iolist_to_binary([<<Map.size(hstore_map)::int32>> | keys_and_values])
  end

  defp encode_hstore_key(key) when is_binary(key) do
    encode_hstore_value key
  end

  defp encode_hstore_key(key) when is_nil(key) do
    raise ArgumentError, "hstore keys cannot be nil!"
  end

  defp encode_hstore_value(nil) do
    <<-1::int32>>
  end

  defp encode_hstore_value(value) when is_binary(value) do
    value_byte_size = byte_size(value)
    <<value_byte_size::int32>> <> value
  end

  def decode_hstore(<<_length::int32, pairs::binary>>) do
    decode_hstore_payload(pairs, %{})
  end

  defp decode_hstore_payload(<<>>, acc) do
    acc
  end

  # in the case of a NULL value, there won't be a length
  defp decode_hstore_payload(<<key_length::int32, key::binary(key_length),
                             -1::int32, rest::binary>>, acc) do
    decode_hstore_payload(rest, Map.put(acc, key, nil))
  end

  defp decode_hstore_payload(<<key_length::int32, key::binary(key_length),
                        value_length::int32, value::binary(value_length), rest::binary>>, acc) do
    decode_hstore_payload(rest, Map.put(acc, key, value))
  end
end
