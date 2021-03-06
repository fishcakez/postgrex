defmodule Postgrex.Extensions.Numeric do
  @moduledoc false
  import Postgrex.BinaryUtils
  use Postgrex.BinaryExtension, send: "numeric_send"

  @numeric_base 10_000
  @numeric_float_pad String.length(Integer.to_string(@numeric_base))

  def encode(_, n, _, _) when is_number(n),
    do: encode_numeric(Decimal.new(n))
  def encode(_, %Decimal{} = n, _, _),
    do: encode_numeric(n)
  def encode(type_info, value, _, _) do
    raise ArgumentError,
      Postgrex.Utils.encode_msg(type_info, value, {"a number", Decimal})
  end

  def decode(_, bin, _, _),
    do: decode_numeric(bin)

  ## Helpers

  defp encode_numeric(dec) do
    if Decimal.nan?(dec) do
      <<0 :: int16, 0 :: int16, 0xC000 :: uint16, 0 :: int16>>
    else
      string = Decimal.to_string(dec, :normal) |> :binary.bin_to_list

      if List.first(string) == ?- do
        [_|string] = string
        sign = 0x4000
      else
        sign = 0x0000
      end

      {int, float} = Enum.split_while(string, &(&1 != ?.))
      {weight, int_digits} = Enum.reverse(int) |> encode_numeric_int(0, [])

      if float != [] do
        [_|float] = float
        scale = length(float)
        float_digits = pad_to_numeric_base(float, scale) |> encode_numeric_float([])
      else
        scale = 0
        float_digits = []
      end

      digits = int_digits ++ float_digits
      bin = for digit <- digits, into: "", do: <<digit :: uint16>>
      ndigits = div(byte_size(bin), 2)

      [<<ndigits :: int16, weight :: int16, sign :: uint16, scale :: int16>> | bin]
    end
  end

  defp pad_to_numeric_base(float, scale) do
    if scale < @numeric_float_pad do
      float ++ List.duplicate(?0, @numeric_float_pad - scale)
    else
      float
    end
  end

  defp encode_numeric_float([], [digit|acc]) do
    [pad_float(digit)|acc]
    |> trim_zeros
    |> Enum.reverse
  end

  defp encode_numeric_float(list, acc) do
    {list, rest} = Enum.split(list, 4)
    digit = List.to_integer(list)

    encode_numeric_float(rest, [digit|acc])
  end

  defp encode_numeric_int([], weight, acc) do
    {weight, acc}
  end

  defp encode_numeric_int(list, weight, acc) do
    {list, rest} = Enum.split(list, 4)
    digit = Enum.reverse(list) |> List.to_integer

    if rest != [], do: weight = weight + 1

    encode_numeric_int(rest, weight, [digit|acc])
  end

  defp trim_zeros([0|tail]), do: trim_zeros(tail)
  defp trim_zeros(list), do: list

  defp pad_float(0) do
    0
  end

  defp pad_float(num) do
    num10 = num*10
    if num10 >= @numeric_base do
      num
    else
      pad_float(num10)
    end
  end

  defp decode_numeric(<<ndigits :: int16, weight :: int16, sign :: uint16, scale :: int16, tail :: binary>>) do
    decode_numeric(ndigits, weight, sign, scale, tail)
  end

  defp decode_numeric(0, _weight, 0xC000, _scale, "") do
    Decimal.new(1, :qNaN, 0)
  end

  defp decode_numeric(_num_digits, weight, sign, scale, bin) do
    {value, weight} = decode_numeric_int(bin, weight, 0)

    case sign do
      0x0000 -> sign = 1
      0x4000 -> sign = -1
    end

    {coef, exp} = scale(value, (weight+1)*4, -scale)
    Decimal.new(sign, coef, exp)
  end

  defp scale(coef, exp, scale) when scale == exp,
    do: {coef, exp}

  defp scale(coef, exp, scale) when scale > exp,
    do: scale(div(coef, 10), exp+1, scale)

  defp scale(coef, exp, scale) when scale < exp,
    do: scale(coef * 10, exp-1, scale)

  defp decode_numeric_int("", weight, acc), do: {acc, weight}

  defp decode_numeric_int(<<digit :: int16, tail :: binary>>, weight, acc) do
    acc = (acc * @numeric_base) + digit
    decode_numeric_int(tail, weight - 1, acc)
  end
end
