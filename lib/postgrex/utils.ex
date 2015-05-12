defmodule Postgrex.Utils do
  @moduledoc false

  def error(error, s) do
    reply(error, s)
    {:disconnect, error, s}
  end

  def reply(response, %{queue: queue, reply: reply}) do
    case :queue.out(queue) do
      {:empty, _queue} ->
        false
      {{:value, %{from: nil}}, _queue} ->
        false
      {{:value, %{reply: :no_reply, from: from}}, _queue} ->
        reply.(from, response)
        true
      {{:value, %{reply: {:reply, response}, from: from}}, _queue} ->
        reply.(from, response)
        true
    end
  end

  def reply(response, {_, _} = from, %{reply: reply}) do
    reply.(from, response)
    true
  end

  @doc """
  Converts pg major.minor.patch (http://www.postgresql.org/support/versioning) version to an integer
  """
  def version_to_int(version) do
    case version |> String.split(".") |> Enum.map(fn (part) -> elem(Integer.parse(part),0) end) do
      [major, minor, patch] -> major*10_000 + minor*100 + patch
      [major, minor] -> major*10_000 + minor*100
      [major] -> major*10_000 
    end
  end
end
